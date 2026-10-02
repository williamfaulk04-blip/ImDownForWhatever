"""Single-process room/poll server with durable SQLite room snapshots."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, suppress
from dataclasses import asdict, dataclass, field
import hashlib
import logging
import os
from pathlib import Path
import sqlite3
import math
import secrets
import string
import time
from typing import Annotated, Literal, Optional

from fastapi import FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, StringConstraints

from server.storage import RoomStore

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
    members: dict[str, Member]  # SHA-256 token digest -> public participant
    is_open: bool = True
    poll: Optional[Poll] = None
    categories: list[WheelCategory] = field(default_factory=list)
    wheel: WheelState = field(default_factory=WheelState)
    connections: dict[WebSocket, str] = field(default_factory=dict)
    broadcast_lock: asyncio.Lock = field(default_factory=asyncio.Lock)


rooms: dict[str, Room] = {}

store: Optional[RoomStore] = None


def _token_key(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _encode_room(room: Room) -> dict:
    return {
        'code': room.code, 'host_id': room.host_id, 'is_open': room.is_open,
        'members': {key: asdict(member) for key, member in room.members.items()},
        'poll': asdict(room.poll) if room.poll else None,
        'categories': [asdict(category) for category in room.categories],
        'wheel': asdict(room.wheel),
    }


def _decode_room(data: dict) -> Room:
    return Room(
        code=data['code'], host_id=data['host_id'], is_open=data['is_open'],
        members={key: Member(**member) for key, member in data['members'].items()},
        poll=Poll(**data['poll']) if data['poll'] else None,
        categories=[WheelCategory(category['id'], category['name'],
                    [WheelActivity(**activity) for activity in category['activities']])
                    for category in data['categories']],
        wheel=WheelState(**data['wheel']),
    )


def _persist(room: Room) -> None:
    if store is None:
        raise RuntimeError('Room storage has not been initialized')
    try:
        store.save(room.code, _encode_room(room))
    except sqlite3.Error as error:
        # Keep clients and memory on the last committed version after a disk error.
        previous = store.previous(room.code)
        if previous is not None:
            restored = _decode_room(previous)
            for name in ('host_id', 'members', 'is_open', 'poll', 'categories', 'wheel'):
                setattr(room, name, getattr(restored, name))
        raise HTTPException(503, 'Could not save changes. Please try again.') from error


def _expire(room: Room) -> bool:
    if room.poll and not room.poll.closed and time.time() >= room.poll.ends_at:
        room.poll.closed = True
        _persist(room)
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
    _persist(room)
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
                try:
                    _expire(room)
                    await _broadcast(room)
                except HTTPException:
                    logging.getLogger(__name__).warning('Room save failed; will retry on the next tick')


@asynccontextmanager
async def lifespan(app: FastAPI):
    global store
    store = RoomStore(os.environ.get('FASTPOLL_DB_PATH', str(Path(__file__).resolve().parent / 'data' / 'rooms.sqlite3')))
    rooms.clear()
    for data in store.load():
        room = _decode_room(data)
        rooms[room.code] = room
        _expire(room)
    ticker = asyncio.create_task(_ticker())
    try:
        yield
    finally:
        ticker.cancel()
        with suppress(asyncio.CancelledError):
            await ticker
        store.close()
        store = None


app = FastAPI(title="ImDownForWhatever", version="0.2.0", lifespan=lifespan)


def _room(code: str) -> Room:
    room = rooms.get(code.upper())
    if room is None:
        raise HTTPException(404, "Room not found. Check the room code.")
    return room


def _member(room: Room, authorization: Optional[str], host: bool = False) -> str:
    token = authorization.removeprefix("Bearer ") if authorization else ""
    token = _token_key(token)
    if not authorization or not authorization.startswith("Bearer ") or token not in room.members:
        raise HTTPException(401, "Your room session is no longer valid. Join again.")
    if host and room.members[token].id != room.host_id:
        raise HTTPException(403, "Only the host can do that.")
    return token


def _session(room: Room, token: str) -> dict:
    return {"room_code": room.code, "session_token": token, "name": room.members[_token_key(token)].name}


@app.get("/health")
async def health():
    if store is None:
        raise HTTPException(503, "Room storage is not ready.")
    try:
        store.check()
    except sqlite3.Error as error:
        raise HTTPException(503, "Room storage is not ready.") from error
    return {"status": "healthy"}


@app.post("/api/rooms", status_code=201)
async def create_room(payload: JoinRequest):
    code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(4))
    while code in rooms:
        code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(4))
    token, member_id = secrets.token_urlsafe(32), secrets.token_hex(12)
    room = Room(code=code, host_id=member_id, members={_token_key(token): Member(member_id, payload.name)})
    _persist(room)
    rooms[code] = room
    return _session(room, token)


@app.post("/api/rooms/{code}/join")
async def join_room(code: str, payload: JoinRequest):
    room = _room(code)
    if payload.session_token:
        if _token_key(payload.session_token) not in room.members:
            raise HTTPException(401, "Saved session expired. Join again to start a new session.")
        # Existing members can reconnect even when new joins are locked.
        return _session(room, payload.session_token)
    if not room.is_open:
        raise HTTPException(403, "The host has locked this room to new friends.")
    token = secrets.token_urlsafe(32)
    room.members[_token_key(token)] = Member(secrets.token_hex(12), payload.name)
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
        token = _token_key(token) if isinstance(token, str) else None
        if token not in room.members:
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
                try:
                    await _broadcast(room)
                except HTTPException as failure:
                    await socket.send_json({'event': 'ERROR', 'message': failure.detail})
    except WebSocketDisconnect:
        pass
    except (asyncio.TimeoutError, ValueError):
        await socket.close(code=4401, reason="Authentication required")
    finally:
        room.connections.pop(socket, None)
        await _broadcast(room)
