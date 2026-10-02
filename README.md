# ImDownForWhatever

A Flutter Android app for friends to join a room by code and decide what to do together.
The app supports a lobby, host-only poll controls, live voting, repeat polls, editable category/activity choices, and synchronized wheels.

## Public server

The repository includes a production Docker image and a Render Blueprint in
[`render.yaml`](render.yaml). The deployment runs one API instance, accepts public
HTTPS/WSS traffic, and stores its SQLite database on a persistent disk. See
[`docs/deployment.md`](docs/deployment.md) for provisioning, verification, Android
build commands, backups, and operational limitations.

Every app installation that should share rooms must use the same public API URL.
Open **Settings** from the app bar, paste the URL under **Server address**, and
save it. The selection persists on that installation. A build-time default remains
available for packaged deployments:

```sh
cd mobile
flutter run -d YOUR_DEVICE_ID \
  --dart-define=FASTPOLL_API_BASE=https://YOUR-SERVICE.onrender.com
```

This works for physical phones and Android emulators on different computers and
different networks. Create new rooms after switching API URLs because saved room
sessions are intentionally scoped to the server that created them.

For a free temporary cross-network test without provisioning a hosted service,
use the signed Cloudflare Quick Tunnel workflow in
[`docs/cloudflare-testing.md`](docs/cloudflare-testing.md). The server computer
must remain running during this test, and each tunnel restart produces a new URL.
On Windows, double-click **Start Shared Test Server.cmd** in the repository root;
it installs the signed tunnel executable on first use and then starts the server.

## Run locally

Use Python 3.11 (CI version), Flutter 3.47.2 / Dart 3.13.2 or a compatible newer stable SDK, Java 17+, and an Android emulator/device. Android is the currently supported and tested mobile target; an iOS scaffold exists but has not been validated.

From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r server/requirements-dev.txt
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

Port 8000 must be reachable from the phone. Local HTTP is for development only;
use the public HTTPS/WSS deployment for devices on different networks.

## Try it

1. Enter your name and **Create Room**. A loading view shows connection progress and the current step. Copy the four-character code from the lobby for a friend.
2. On another device, enter a name and the code, then **Join Room**.
3. The host can toggle **Allow new friends to join**. Locking stops new joins but permits existing members to reconnect.
4. The host creates a poll with two to five options and a duration. Everyone, including the host, can vote once.
5. End the poll or let it expire. Everyone transitions to a results screen showing the winner, a tie, or no-votes result. Use **Back to lobby** to return or **Start another poll** as the host.
6. Choose **Start another poll**. The room code and participants stay; votes reset for the new poll.
7. Return home and join the same code to resume your saved identity, host role, and vote on that installation.

Closing the screen does not destroy the room. The host does not transfer automatically. Rooms, members, host access, join locks, the current poll and votes, wheel categories/activities, and the latest wheel result are saved automatically to SQLite. Restarting restores them; poll deadlines keep running while the server is offline. Rejoin using the same room code on the same app installation to restore your identity.

The default database is `server/data/rooms.sqlite3` (ignored by Git). Set
`FASTPOLL_DB_PATH` to an absolute path to use another location. Hosted deployments
must point it at persistent storage; `render.yaml` uses `/data/rooms.sqlite3`.
SQLite uses WAL journaling, waits briefly for active locks, and is checked by the
`/health` readiness endpoint. Session credentials are stored as SHA-256 digests
and the database is created with owner-only permissions. Use **one Uvicorn
worker**: live room state and socket broadcasts are still managed by one process.
This saves the current poll/latest spin, not a full decision history.

On the first upgrade from the older in-memory server, existing unsaved rooms cannot be recovered after that server stops. Create a room after restarting with this version; subsequent restarts preserve it.

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
# Widget/service checks, executed on Android (no server needed):
flutter test integration_test/widget_suite_test.dart -d emulator-5554

# Real host UI + second network participant; start the server first:
flutter test integration_test/room_journey_test.dart -d emulator-5554
```

The real-server test creates disposable QA rooms. Device tests install a test build; run `flutter run -d emulator-5554` afterward to restore the normal app.

The **CI** workflow checks the server, Flutter analysis/tests, and Android build. The older **Build** workflow only packages the README; it is not an app validation check.
CI also builds the production server image so packaging failures are caught before deployment.

## Development

Read [HANDOVER.md](HANDOVER.md) for the current implementation contract, limitations, validation results, and prioritized next tasks. For new development, update `main` and create a new feature branch for your task. Preserve any existing uncommitted work before switching branches. The owner wants to demo changes **before any commits**; do not commit, push, or merge until that review is complete and authorized.

### Choices and appearance

Hosts open **Manage choices** from the lobby to manage categories and activities on a separate page. Add and rename actions open full-page forms; failed saves preserve the entered name for retry. The lobby keeps the wheel, result, and spin controls without the editor list.

Use the **Settings** icon in the home, room, or choices app bar to select **Light
mode**, **Dark mode**, or **Use device theme**. Settings also shows the current
server address. Change servers from the home screen; server editing is disabled
inside an active room so its REST calls and live socket cannot diverge. Both the
appearance and custom server are saved on that installation.
