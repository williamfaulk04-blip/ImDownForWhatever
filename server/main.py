"""Single-process room/poll prototype. Session tokens are private bearer credentials."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass, field
import math
import secrets
import string
import time
from typing import Annotated, Literal, Optional

from fastapi import FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, StringConstraints

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]
Option = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
WheelName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class JoinRequest(BaseModel):
    name: Name
    session_token: Optional[str] = Field(default=None, max_length=200)


class PollCreate(BaseModel):
    topic: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
    options: list[Option] = Field(min_length=2, max_length=5)
    duration: int = Field(strict=True, gt=0, le=3600)


class RoomAccess(BaseModel):
    is_open: bool = Field(strict=True)


class WheelNameRequest(BaseModel):
    name: WheelName


@dataclass
class Member:
    id: str
    name: str


@dataclass
class Poll:
    id: str
    topic: str
    options: list[str]
    ends_at: float
    votes: dict[str, int] = field(default_factory=dict)
    closed: bool = False


@dataclass
class WheelActivity:
    id: str
    name: str


@dataclass
class WheelCategory:
    id: str
    name: str
    activities: list[WheelActivity] = field(default_factory=list)


@dataclass
class WheelState:
    spin_id: Optional[str] = None
    phase: Optional[Literal["category", "activity"]] = None
    selected_category_id: Optional[str] = None
    selected_activity_id: Optional[str] = None
    result: Optional[str] = None
    status: Literal["idle", "finished"] = "idle"


@dataclass
class Room:
    code: str
    host_id: str
    members: dict[str, Member]  # private token -> public participant
    is_open: bool = True
    poll: Optional[Poll] = None
    categories: list[WheelCategory] = field(default_factory=list)
    wheel: WheelState = field(default_factory=WheelState)
    connections: dict[WebSocket, str] = field(default_factory=dict)
    broadcast_lock: asyncio.Lock = field(default_factory=asyncio.Lock)


rooms: dict[str, Room] = {}


def _expire(room: Room) -> bool:
    if room.poll and not room.poll.closed and time.time() >= room.poll.ends_at:
        room.poll.closed = True
        return True
    return False


def _state(room: Room, token: str) -> dict:
    _expire(room)
    member = room.members[token]
    online = set(room.connections.values())
    poll_state = None
    if poll := room.poll:
        counts = [0] * len(poll.options)
        for option in poll.votes.values():
            counts[option] += 1
        maximum = max(counts)
        winners = [i for i, count in enumerate(counts) if count == maximum] if maximum else []
        poll_state = {
            "id": poll.id, "topic": poll.topic,
            "status": "closed" if poll.closed else "open",
            "time_left": 0 if poll.closed else max(0, math.ceil(poll.ends_at - time.time())),
            "options": [{"id": i, "text": text, "votes": counts[i]} for i, text in enumerate(poll.options)],
            "selected_option": poll.votes.get(member.id),
            "winner_ids": winners if poll.closed else [],
        }
    return {
        "event": "STATE_UPDATE", "room_code": room.code, "is_open": room.is_open,
        "is_host": member.id == room.host_id, "participant_id": member.id,
        "participants": [{"id": m.id, "name": m.name, "is_host": m.id == room.host_id,
                          "online": t in online} for t, m in room.members.items()],
        "poll": poll_state,
        "categories": [
            {
                "id": category.id,
                "name": category.name,
                "activities": [
                    {"id": activity.id, "name": activity.name}
                    for activity in category.activities
                ],
            }
            for category in room.categories
        ],
        "wheel": {
            "spin_id": room.wheel.spin_id,
            "phase": room.wheel.phase,
            "selected_category_id": room.wheel.selected_category_id,
            "selected_activity_id": room.wheel.selected_activity_id,
            "result": room.wheel.result,
            "status": room.wheel.status,
        },
    }


def _category(room: Room, category_id: str) -> WheelCategory:
    category = next((item for item in room.categories if item.id == category_id), None)
    if category is None:
        raise HTTPException(404, "Category not found.")
    return category


def _check_unique_name(names: list[str], name: str, kind: str) -> None:
    if any(existing.casefold() == name.casefold() for existing in names):
        raise HTTPException(422, f"Give each {kind} a different name.")


def _reset_wheel(room: Room) -> None:
    room.wheel = WheelState()


async def _broadcast(room: Room) -> None:
    # Serialize snapshots so an older broadcast cannot overtake a newer one.
    async with room.broadcast_lock:
        for socket, token in list(room.connections.items()):
            try:
                await asyncio.wait_for(socket.send_json(_state(room, token)), timeout=2)
            except Exception:
                room.connections.pop(socket, None)


async def _ticker() -> None:
    while True:
        await asyncio.sleep(1)
        for room in list(rooms.values()):
            if room.poll and room.connections:
                _expire(room)
                await _broadcast(room)


@asynccontextmanager
async def lifespan(app: FastAPI):
    ticker = asyncio.create_task(_ticker())
    try:
        yield
    finally:
        ticker.cancel()
        with suppress(asyncio.CancelledError):
            await ticker


app = FastAPI(title="ImDownForWhatever", version="0.2.0", lifespan=lifespan)


def _room(code: str) -> Room:
    room = rooms.get(code.upper())
    if room is None:
        raise HTTPException(404, "Room not found. It may have ended or the server restarted.")
    return room


def _member(room: Room, authorization: Optional[str], host: bool = False) -> str:
    token = authorization.removeprefix("Bearer ") if authorization else ""
    if not authorization or not authorization.startswith("Bearer ") or token not in room.members:
        raise HTTPException(401, "Your room session is no longer valid. Join again.")
    if host and room.members[token].id != room.host_id:
        raise HTTPException(403, "Only the host can do that.")
    return token


def _session(room: Room, token: str) -> dict:
    return {"room_code": room.code, "session_token": token, "name": room.members[token].name}


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.post("/api/rooms", status_code=201)
async def create_room(payload: JoinRequest):
    code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(4))
    while code in rooms:
        code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(4))
    token, member_id = secrets.token_urlsafe(32), secrets.token_hex(12)
    room = Room(code=code, host_id=member_id, members={token: Member(member_id, payload.name)})
    rooms[code] = room
    return _session(room, token)


@app.post("/api/rooms/{code}/join")
async def join_room(code: str, payload: JoinRequest):
    room = _room(code)
    if payload.session_token:
        if payload.session_token not in room.members:
            raise HTTPException(401, "Saved session expired. Join again to start a new session.")
        # Existing members can reconnect even when new joins are locked.
        return _session(room, payload.session_token)
    if not room.is_open:
        raise HTTPException(403, "The host has locked this room to new friends.")
    token = secrets.token_urlsafe(32)
    room.members[token] = Member(secrets.token_hex(12), payload.name)
    await _broadcast(room)
    return _session(room, token)


@app.patch("/api/rooms/{code}")
async def set_access(code: str, payload: RoomAccess, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    room.is_open = payload.is_open
    await _broadcast(room)
    return _state(room, token)


@app.post("/api/rooms/{code}/categories", status_code=201)
async def add_category(code: str, payload: WheelNameRequest, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    _check_unique_name([category.name for category in room.categories], payload.name, "category")
    room.categories.append(WheelCategory(secrets.token_hex(12), payload.name))
    await _broadcast(room)
    return _state(room, token)


@app.patch("/api/rooms/{code}/categories/{category_id}")
async def rename_category(code: str, category_id: str, payload: WheelNameRequest, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    category = _category(room, category_id)
    _check_unique_name([item.name for item in room.categories if item.id != category_id], payload.name, "category")
    category.name = payload.name
    if room.wheel.selected_category_id == category_id and room.wheel.phase == "category":
        room.wheel.result = category.name
    await _broadcast(room)
    return _state(room, token)


@app.delete("/api/rooms/{code}/categories/{category_id}")
async def remove_category(code: str, category_id: str, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    category = _category(room, category_id)
    room.categories.remove(category)
    if room.wheel.selected_category_id == category_id:
        _reset_wheel(room)
    await _broadcast(room)
    return _state(room, token)


@app.post("/api/rooms/{code}/categories/{category_id}/activities", status_code=201)
async def add_activity(code: str, category_id: str, payload: WheelNameRequest, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    category = _category(room, category_id)
    _check_unique_name([activity.name for activity in category.activities], payload.name, "activity")
    category.activities.append(WheelActivity(secrets.token_hex(12), payload.name))
    await _broadcast(room)
    return _state(room, token)


@app.patch("/api/rooms/{code}/categories/{category_id}/activities/{activity_id}")
async def rename_activity(code: str, category_id: str, activity_id: str, payload: WheelNameRequest, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    category = _category(room, category_id)
    activity = next((item for item in category.activities if item.id == activity_id), None)
    if activity is None:
        raise HTTPException(404, "Activity not found.")
    _check_unique_name([item.name for item in category.activities if item.id != activity_id], payload.name, "activity")
    activity.name = payload.name
    if room.wheel.selected_category_id == category_id and room.wheel.selected_activity_id == activity_id:
        room.wheel.result = activity.name
    await _broadcast(room)
    return _state(room, token)


@app.delete("/api/rooms/{code}/categories/{category_id}/activities/{activity_id}")
async def remove_activity(code: str, category_id: str, activity_id: str, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    category = _category(room, category_id)
    activity = next((item for item in category.activities if item.id == activity_id), None)
    if activity is None:
        raise HTTPException(404, "Activity not found.")
    category.activities.remove(activity)
    if room.wheel.selected_category_id == category_id and room.wheel.selected_activity_id == activity_id:
        _reset_wheel(room)
    await _broadcast(room)
    return _state(room, token)


@app.post("/api/rooms/{code}/wheel/category-spin")
async def spin_category(code: str, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    if not room.categories:
        raise HTTPException(409, "Add at least one category before spinning.")
    category = secrets.choice(room.categories)
    room.wheel = WheelState(
        spin_id=secrets.token_hex(16),
        phase="category",
        selected_category_id=category.id,
        result=category.name,
        status="finished",
    )
    await _broadcast(room)
    return _state(room, token)


@app.post("/api/rooms/{code}/wheel/activity-spin")
async def spin_activity(code: str, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    if room.wheel.selected_category_id is None:
        raise HTTPException(409, "Spin for a category first.")
    category = next(
        (item for item in room.categories if item.id == room.wheel.selected_category_id),
        None,
    )
    if category is None:
        _reset_wheel(room)
        raise HTTPException(409, "The selected category is no longer available.")
    if not category.activities:
        raise HTTPException(409, "Add at least one activity to the selected category before spinning.")
    activity = secrets.choice(category.activities)
    room.wheel = WheelState(
        spin_id=secrets.token_hex(16),
        phase="activity",
        selected_category_id=category.id,
        selected_activity_id=activity.id,
        result=activity.name,
        status="finished",
    )
    await _broadcast(room)
    return _state(room, token)


@app.post("/api/rooms/{code}/polls", status_code=201)
async def create_poll(code: str, payload: PollCreate, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    _expire(room)
    if room.poll and not room.poll.closed:
        raise HTTPException(409, "End the current poll before starting another.")
    if len({option.casefold() for option in payload.options}) != len(payload.options):
        raise HTTPException(422, "Give each option a different name.")
    room.poll = Poll(secrets.token_hex(12), payload.topic, payload.options, time.time() + payload.duration)
    await _broadcast(room)
    return _state(room, token)


@app.post("/api/rooms/{code}/polls/{poll_id}/close")
async def close_poll(code: str, poll_id: str, authorization: Optional[str] = Header(default=None)):
    room = _room(code)
    token = _member(room, authorization, host=True)
    if not room.poll or room.poll.id != poll_id:
        raise HTTPException(409, "This poll is no longer current.")
    room.poll.closed = True
    await _broadcast(room)
    return _state(room, token)


@app.websocket("/ws/{code}")
async def room_socket(socket: WebSocket, code: str):
    await socket.accept()
    room = rooms.get(code.upper())
    if room is None:
        await socket.close(code=4404, reason="Room not found")
        return
    try:
        # Credentials stay out of URLs/access logs. Authenticate in the first frame.
        auth = await asyncio.wait_for(socket.receive_json(), timeout=10)
        token = auth.get("session_token") if isinstance(auth, dict) else None
        if not isinstance(token, str) or token not in room.members:
            await socket.close(code=4401, reason="Invalid room session")
            return
        room.connections[socket] = token
        await _broadcast(room)
        while True:
            try:
                message = await socket.receive_json()
            except ValueError:
                await socket.send_json({"event": "ERROR", "message": "Send a JSON object."})
                continue
            error = None
            if not isinstance(message, dict) or message.get("action") != "CAST_VOTE":
                error = "Unknown action."
            else:
                _expire(room)
                poll = room.poll
                option = message.get("option_id")
                if not poll or message.get("poll_id") != poll.id:
                    error = "This poll is no longer current."
                elif poll.closed:
                    error = "Poll is closed."
                elif type(option) is not int or not 0 <= option < len(poll.options):
                    error = "Invalid option."
                else:
                    # No await between validation and mutation: atomic on this event loop.
                    poll.votes.setdefault(room.members[token].id, option)
            if error:
                await socket.send_json({"event": "ERROR", "message": error})
            else:
                await _broadcast(room)
    except WebSocketDisconnect:
        pass
    except (asyncio.TimeoutError, ValueError):
        await socket.close(code=4401, reason="Authentication required")
    finally:
        room.connections.pop(socket, None)
        await _broadcast(room)
