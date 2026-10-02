# Public API deployment

The mobile app can share rooms across different computers, emulators, phones, and
networks when every installation connects to the same public API deployment.
Room codes identify rooms inside one server; they do not locate a server by
themselves.

## Architecture

- `Dockerfile` packages the FastAPI application on Python 3.11.
- Uvicorn binds to the hosting platform's `PORT` on `0.0.0.0`.
- Exactly one Uvicorn worker and one service instance are used because live
  WebSocket connections and broadcasts are held in that process.
- `FASTPOLL_DB_PATH=/data/rooms.sqlite3` puts SQLite on the attached persistent
  disk. The database uses WAL journaling and full synchronous commits.
- `/health` checks that SQLite can answer a query before reporting healthy.
- The hosting load balancer terminates TLS. Mobile clients use HTTPS for REST and
  WSS for room updates.

This is an appropriate small-team deployment. It is not horizontally scalable.
Moving to multiple instances later requires a shared database and cross-instance
pub/sub for WebSocket broadcasts.

## Deploy with Render

Render is the checked-in deployment target because its web services support
HTTPS, WebSockets, health checks, Docker, and persistent disks. A persistent disk
requires a paid web service; do not switch this Blueprint to the free plan because
free filesystems are ephemeral and rooms would be lost on restart.

1. Commit and push `Dockerfile`, `.dockerignore`, `render.yaml`, and the server
   changes to the GitHub branch that should be deployed.
2. In the Render Dashboard, choose **New > Blueprint** and connect this GitHub
   repository.
3. Select the branch and review the `imdownforwhatever-api` service before
   applying it. The Blueprint requests one `0.5c-512mb` instance and a 1 GB disk.
4. Deploy the Blueprint. Keep the instance count at one.
5. Copy the assigned URL, such as
   `https://imdownforwhatever-api.onrender.com`.
6. Open `https://YOUR-SERVICE.onrender.com/health`. Deployment is ready only when
   it returns `{"status":"healthy"}`.

Render documentation:

- <https://render.com/docs/infrastructure-as-code>
- <https://render.com/docs/disks>
- <https://render.com/docs/websocket>
- <https://render.com/docs/health-checks>

The Docker image is not Render-specific. Another host is suitable if it provides
public HTTPS/WSS, passes a `PORT`, mounts durable writable storage at `/data`, and
runs exactly one instance.

## Connect the Android app

The server URL is not a secret. On each installation, open **Settings** from the
home screen, enter the public HTTPS origin under **Server address**, and save it.
The setting persists locally and overrides the build-time default. Do not add a
path; trailing slashes are removed automatically.

For release artifacts that should ship with a public default, the build-time
configuration remains available:

Run on an emulator or connected phone:

```sh
cd mobile
flutter run -d YOUR_DEVICE_ID \
  --dart-define=FASTPOLL_API_BASE=https://YOUR-SERVICE.onrender.com
```

Build an installable release APK:

```sh
cd mobile
flutter build apk --release \
  --dart-define=FASTPOLL_API_BASE=https://YOUR-SERVICE.onrender.com
```

Give all testers the same public URL, whether it is entered in Settings or supplied
as the build default. Existing local sessions will not appear against the public
server because sessions are intentionally keyed by API URL. Create a fresh room
after selecting the public server.

## Cross-network acceptance test

1. Confirm `/health` over the public HTTPS URL.
2. On computer A, start an Android emulator, enter the public URL in Settings,
   and create a room.
3. On computer B on a different network, start an emulator, enter the same URL
   in Settings, and join the code.
4. Confirm both participant names appear and online status updates.
5. Create and vote in a poll from different emulators.
6. Add choices and spin both wheels; confirm both clients receive the result.
7. Restart the deployed service, then rejoin the existing room on both emulators
   to verify SQLite recovery from the persistent disk.

Do not describe cross-network support as verified until this test has been run
against the live deployment.

## Operations and backups

- Keep one service instance and one Uvicorn worker.
- Monitor the `/health` endpoint and disk usage.
- Render persistent disks receive platform snapshots, but a deliberate export is
  still recommended before risky changes.
- For a manual SQLite copy, stop the service first so the database and WAL files
  cannot change during the copy.
- Increasing disk size is supported; shrinking it is not.
- A service with an attached disk cannot use horizontal autoscaling or
  zero-downtime replacement. Brief downtime during deployment is expected, and
  clients will use their existing reconnect loop afterward.
