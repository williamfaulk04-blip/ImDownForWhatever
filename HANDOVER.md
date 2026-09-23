# FastPoll Handover

## Git workflow

Start each change from a clean `main`, then create a focused feature branch:

```bash
git checkout main
git pull --ff-only
git checkout -b feat/<feature-name>
```

Before merging, run `pytest server/`, `flutter analyze`, `flutter test`, and the relevant build. Commit only after every check passes. Then merge with:

```bash
git add .
git commit -m "feat: describe the verified change"
git checkout main
git merge feat/<feature-name>
git push origin main
git branch -d feat/<feature-name>
```

Never merge failing or unverified work into `main`.

## Architecture and layout

```text
FastPoll/
├── server/                 FastAPI REST and WebSocket service
│   ├── main.py             Routes, room state, votes, broadcasts
│   └── test_main.py        Server endpoint tests
├── mobile/                 Flutter Android client
│   ├── lib/models/         REST/WebSocket contract models
│   ├── lib/services/       HTTP and WebSocket clients
│   └── lib/screens/        Home, host, and voting UI
└── .github/workflows/      Automated server and mobile checks
```

Rooms and votes are currently process-local and disappear when the server restarts. Each WebSocket client receives the current state at connection time. Votes are idempotent by `client_id`: the first valid vote is retained.

## API schemas

Create a room with `POST /api/rooms`:

```json
{
  "topic": "Where should we eat?",
  "options": ["Tacos", "Pizza"],
  "duration": 60
}
```

The response has HTTP 201 and includes a four-character `room_code` plus the initial state:

```json
{
  "room_code": "A7K2",
  "event": "STATE_UPDATE",
  "topic": "Where should we eat?",
  "status": "open",
  "time_left": 60,
  "options": [{"id": 0, "text": "Tacos", "votes": 0}]
}
```

Connect to `/ws/{room_code}/{client_id}` and cast a vote with:

```json
{"action": "CAST_VOTE", "option_id": 0}
```

Every client receives state updates in this form:

```json
{
  "event": "STATE_UPDATE",
  "room_code": "A7K2",
  "topic": "Where should we eat?",
  "status": "open",
  "time_left": 42,
  "options": [
    {"id": 0, "text": "Tacos", "votes": 3},
    {"id": 1, "text": "Pizza", "votes": 1}
  ]
}
```

## Run locally

Server (from the repository root):

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r server/requirements.txt
uvicorn server.main:app --reload --host 0.0.0.0 --port 8000
```

Mobile, using the Android emulator's host alias:

```bash
cd mobile
flutter pub get
flutter run
```

For a physical phone, connect it to the same LAN and pass the development machine's address:

```bash
flutter run --dart-define=FASTPOLL_API_BASE=http://192.168.1.10:8000
```

Allow port 8000 through the development machine's firewall if needed. The Android project can also be opened from the `mobile` directory in Android Studio.

## Current Sprint Status

- [x] FastAPI health and room creation endpoints
- [x] In-memory rooms and idempotent real-time voting
- [x] Flutter Android scaffold and network configuration
- [x] Create, join, vote, countdown, and live-result screens
- [x] Server tests and Flutter widget smoke test
- [x] GitHub Actions server/mobile pipeline
- [ ] Persistent database and room recovery
- [ ] Authentication and host-only poll controls
- [ ] Automated WebSocket integration tests
- [ ] iOS configuration and device validation

## Next Immediate Tasks

1. Add WebSocket integration coverage for first-vote-wins behavior, invalid options, broadcasts, and expired polls.
2. Replace process-local storage with a shared persistent store so rooms survive restarts and multiple workers can broadcast consistently.
3. Add a host identity and explicit close-poll controls.
4. Test physical-device discovery and consider a configurable in-app server address for development.
5. Add reconnect/backoff behavior and preserve the generated client identity across transient connections.
