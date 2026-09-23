from fastapi.testclient import TestClient

from server.main import app, rooms


client = TestClient(app)


def setup_function() -> None:
    rooms.clear()


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_create_room() -> None:
    response = client.post(
        "/api/rooms",
        json={"topic": "Lunch?", "options": ["Tacos", "Pizza"], "duration": 60},
    )
    assert response.status_code == 201
    body = response.json()
    assert len(body["room_code"]) == 4
    assert body["room_code"].isalnum()
    assert body["room_code"] == body["room_code"].upper()
    assert body["topic"] == "Lunch?"
    assert body["status"] == "open"
    assert body["options"] == [
        {"id": 0, "text": "Tacos", "votes": 0},
        {"id": 1, "text": "Pizza", "votes": 0},
    ]
