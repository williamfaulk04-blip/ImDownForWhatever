# ImDownForWhatever

A Flutter Android app for friends to join a room by code and decide what to do together.
The current prototype supports a lobby, host-only poll controls, live voting, and repeat polls in the same room. Category and activity wheels are planned, not implemented.

## Run locally

Use Python 3.11 (CI version), Flutter 3.47.2 / Dart 3.13.2 or a compatible newer stable SDK, Java 17+, and an Android emulator/device. The repository currently contains **Android** platform configuration only.

From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r server/requirements.txt
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000
```

In another terminal, with an Android emulator running:

```sh
cd mobile
flutter pub get
flutter run -d emulator-5554
```

Use `flutter devices` to find your device ID. Android emulators use `http://10.0.2.2:8000` by default. Check `http://127.0.0.1:8000/health` for `{"status":"healthy"}`.

For physical Android phones on the same trusted Wi-Fi, run the server with `--host 0.0.0.0` and use your computer's LAN IP:

```sh
flutter run -d YOUR_DEVICE_ID --dart-define=FASTPOLL_API_BASE=http://192.168.1.10:8000
```

Port 8000 must be reachable from the phone. Local HTTP is for development; internet deployment needs HTTPS/WSS and production hardening.

## Try it

1. Enter your name and **Create Room**. A loading view shows connection progress and the current step. Copy the four-character code from the lobby for a friend.
2. On another device, enter a name and the code, then **Join Room**.
3. The host can toggle **Allow new friends to join**. Locking stops new joins but permits existing members to reconnect.
4. The host creates a poll with two to five options and a duration. Everyone, including the host, can vote once.
5. End the poll or let it expire. Everyone transitions to a results screen showing the winner, a tie, or no-votes result. Use **Back to lobby** to return or **Start another poll** as the host.
6. Choose **Start another poll**. The room code and participants stay; votes reset for the new poll.
7. Return home and join the same code to resume your saved identity, host role, and vote on that installation.

Closing the screen does not destroy the room. The host does not transfer automatically. Restarting the server deletes all rooms; this is still an in-memory, single-worker prototype.

## Checks

From the root, with the Python environment active:

```sh
python -m pytest server/ -q
```

From `mobile/`:

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Optional Android device checks:

```sh
# Same twelve widget/service checks, executed on Android (no server needed):
flutter test integration_test/widget_suite_test.dart -d emulator-5554

# Real host UI + second network participant; start the server first:
flutter test integration_test/room_journey_test.dart -d emulator-5554
```

The real-server test creates disposable QA rooms. Device tests install a test build; run `flutter run -d emulator-5554` afterward to restore the normal app.

The **CI** workflow checks the server, Flutter analysis/tests, and Android build. The older **Build** workflow only packages the README; it is not an app validation check.

## Development

Read [HANDOVER.md](HANDOVER.md) for the current implementation contract, limitations, validation results, and prioritized next tasks. For new development, update `main` and create a new feature branch for your task. Preserve any existing uncommitted work before switching branches. The owner wants to demo changes **before any commits**; do not commit, push, or merge until that review is complete and authorized.
