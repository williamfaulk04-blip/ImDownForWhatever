"""Verify that a public deployment supports shared REST and WebSocket room state."""

import argparse
import asyncio
import json
from urllib.parse import urlparse

import httpx
import websockets


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a disposable two-person room through a public API URL."
    )
    parser.add_argument("base_url", help="HTTPS base URL without a trailing slash")
    return parser.parse_args()


def validate_base_url(value: str) -> str:
    base_url = value.rstrip("/")
    parsed = urlparse(base_url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.path:
        raise ValueError("base_url must be an HTTPS origin without a path")
    return base_url


def create_sessions(base_url: str) -> tuple[dict, dict]:
    with httpx.Client(base_url=base_url, timeout=15) as client:
        host_response = client.post("/api/rooms", json={"name": "Tunnel QA Host"})
        host_response.raise_for_status()
        host = host_response.json()

        guest_response = client.post(
            f"/api/rooms/{host['room_code']}/join",
            json={"name": "Tunnel QA Guest"},
        )
        guest_response.raise_for_status()
        return host, guest_response.json()


async def receive_shared_state(socket) -> dict:
    for _ in range(10):
        message = json.loads(await asyncio.wait_for(socket.recv(), timeout=5))
        if message.get("event") == "STATE_UPDATE" and len(message["participants"]) == 2:
            return message
    raise RuntimeError("The shared two-person room state was not received")


async def verify_websockets(base_url: str, host: dict, guest: dict) -> None:
    websocket_base = "wss://" + urlparse(base_url).netloc
    websocket_url = f"{websocket_base}/ws/{host['room_code']}"

    async with websockets.connect(websocket_url, open_timeout=15) as host_socket:
        await host_socket.send(json.dumps({"session_token": host["session_token"]}))
        async with websockets.connect(websocket_url, open_timeout=15) as guest_socket:
            await guest_socket.send(json.dumps({"session_token": guest["session_token"]}))
            host_state, guest_state = await asyncio.gather(
                receive_shared_state(host_socket),
                receive_shared_state(guest_socket),
            )

    expected_names = {"Tunnel QA Host", "Tunnel QA Guest"}
    for state in (host_state, guest_state):
        actual_names = {participant["name"] for participant in state["participants"]}
        if actual_names != expected_names:
            raise RuntimeError(f"Unexpected participants: {sorted(actual_names)}")


async def main() -> None:
    base_url = validate_base_url(parse_arguments().base_url)
    host, guest = await asyncio.to_thread(create_sessions, base_url)
    await verify_websockets(base_url, host, guest)
    print(
        f"Public REST and WebSocket verification passed for room {host['room_code']} "
        "with 2 participants."
    )


if __name__ == "__main__":
    asyncio.run(main())
