"""FastPoll FastAPI server."""

from __future__ import annotations

import asyncio
import math
import secrets
import string
import time
from collections import defaultdict
from typing import Any

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


class RoomCreate(BaseModel):
    topic: str = Field(min_length=1, max_length=200)
    options: list[str] = Field(min_length=2, max_length=5)
    duration: int = Field(gt=0, le=86_400)


app = FastAPI(title="FastPoll", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

rooms: dict[str, dict[str, Any]] = {}
connections: dict[str, set[WebSocket]] = defaultdict(set)
room_lock = asyncio.Lock()


def _new_room_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    while True:
        code = "".join(secrets.choice(alphabet) for _ in range(4))
        if code not in rooms:
            return code


def _state(room_code: str) -> dict[str, Any]:
    room = rooms[room_code]
    time_left = max(0, math.ceil(room["ends_at"] - time.time()))
    counts = [0] * len(room["options"])
    for option_id in room["votes"].values():
        counts[option_id] += 1
    return {
        "event": "STATE_UPDATE",
        "room_code": room_code,
        "topic": room["topic"],
        "status": "open" if time_left > 0 else "closed",
        "time_left": time_left,
        "options": [
            {"id": index, "text": text, "votes": counts[index]}
            for index, text in enumerate(room["options"])
        ],
    }


async def _broadcast(room_code: str) -> None:
    message = _state(room_code)
    stale: list[WebSocket] = []
    for websocket in list(connections[room_code]):
        try:
            await websocket.send_json(message)
        except Exception:
            stale.append(websocket)
    for websocket in stale:
        connections[room_code].discard(websocket)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.post("/api/rooms", status_code=201)
async def create_room(payload: RoomCreate) -> dict[str, Any]:
    topic = payload.topic.strip()
    options = [option.strip() for option in payload.options]
    if not topic or any(not option for option in options):
        raise HTTPException(status_code=422, detail="Topic and options cannot be blank")

    async with room_lock:
        room_code = _new_room_code()
        rooms[room_code] = {
            "topic": topic,
            "options": options,
            "duration": payload.duration,
            "ends_at": time.time() + payload.duration,
            "votes": {},
        }
    return {"room_code": room_code, **_state(room_code)}


@app.websocket("/ws/{room_code}/{client_id}")
async def room_socket(websocket: WebSocket, room_code: str, client_id: str) -> None:
    room_code = room_code.upper()
    if room_code not in rooms:
        await websocket.close(code=4404, reason="Room not found")
        return

    await websocket.accept()
    connections[room_code].add(websocket)
    await websocket.send_json(_state(room_code))
    try:
        while True:
            message = await websocket.receive_json()
            if message.get("action") != "CAST_VOTE":
                await websocket.send_json({"event": "ERROR", "message": "Unknown action"})
                continue

            option_id = message.get("option_id")
            room = rooms[room_code]
            if (
                not isinstance(option_id, int)
                or isinstance(option_id, bool)
                or option_id < 0
                or option_id >= len(room["options"])
            ):
                await websocket.send_json({"event": "ERROR", "message": "Invalid option_id"})
                continue
            if _state(room_code)["status"] == "closed":
                await websocket.send_json({"event": "ERROR", "message": "Poll is closed"})
                continue

            async with room_lock:
                room["votes"].setdefault(client_id, option_id)
            await _broadcast(room_code)
    except WebSocketDisconnect:
        pass
    finally:
        connections[room_code].discard(websocket)
        if not connections[room_code]:
            connections.pop(room_code, None)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
