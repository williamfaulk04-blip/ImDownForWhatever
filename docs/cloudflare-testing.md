# Free cross-network test with Cloudflare Quick Tunnel

This workflow exposes the local API through a temporary public HTTPS address so
two Android emulators on different computers and networks can join the same room.
It is for development testing, not permanent hosting.

The computer running the API must remain powered on with the tunnel launcher open.
The URL changes whenever a new Quick Tunnel starts, and Cloudflare provides no
uptime guarantee for Quick Tunnels.

## Start with the double-click launcher

On Windows, double-click `Start Shared Test Server.cmd` in the repository root.
On first use it downloads and verifies Cloudflare's signed executable, then it
starts the API and tunnel on local port 8010, leaving port 8000 available for
ordinary Android Studio development. Keep the window open for the entire test.

The Python environment is still a one-time prerequisite. If the launcher reports
that `.venv` is missing, complete the setup below once and double-click it again.

## Manual setup and launch

Create the Python environment if it does not already exist:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r server\requirements-dev.txt
```

Install Cloudflare's signed standalone executable into the ignored `.tools`
directory:

```powershell
.\scripts\install-cloudflared.ps1
```

The installer downloads from Cloudflare's official GitHub release and rejects the
file unless Windows reports a valid Cloudflare Authenticode signature. It does not
install a Windows service or require a Cloudflare account.

From the repository root on the server computer, the PowerShell launcher can also
be run directly:

```powershell
.\scripts\start-quick-tunnel.ps1
```

The launcher:

1. Starts one local Uvicorn worker.
2. Uses `%LOCALAPPDATA%\ImDownForWhatever\rooms.sqlite3` so test rooms survive
   tunnel restarts without mixing tunnel data with repository-local development.
3. Waits for the database-backed `/health` check.
4. Starts a Cloudflare Quick Tunnel.
5. Prints the temporary `https://...trycloudflare.com` URL, in-app Settings
   instructions, and an optional Flutter command for automated builds.
6. Stops both processes when the launcher exits.

Keep this PowerShell window open for the entire test.

Optionally verify the public REST and WebSocket paths before opening emulators:

```powershell
.\.venv\Scripts\python.exe scripts\verify-public-server.py https://EXAMPLE.trycloudflare.com
```

This creates one disposable QA room and succeeds only when two independent socket
clients both receive the shared two-participant state.

## Connect both emulators

Run the app on each developer computer. Open **Settings** from the home screen,
paste the exact URL printed by the tunnel launcher into **Server address**, and
select **Save server**. Do not add a trailing slash.

There is no need to rebuild the app when the temporary tunnel URL changes. Return
home before changing servers; server editing is deliberately disabled in an active
room.

For automated or command-line builds, the build-time option remains available:

```powershell
flutter run -d YOUR_DEVICE_ID --dart-define=FASTPOLL_API_BASE=https://EXAMPLE.trycloudflare.com
```

One emulator creates a new room. The other enters that room code. Both builds must
use the same tunnel URL; a room created against `10.0.2.2` exists only on that
computer's local server.

## Acceptance test

1. Create a room on emulator A.
2. Join it from emulator B on a different network.
3. Confirm both participants appear online.
4. Vote in a poll from both emulators and verify synchronized counts/results.
5. Add choices and spin both wheels; verify both clients receive the result.
6. Stop and restart only the tunnel launcher, update both apps through Settings
   with the new URL, and confirm the local SQLite database still contains the room.

Saved mobile sessions are scoped to the API URL. Because a Quick Tunnel gets a new
URL on restart, the app treats it as a different server even though the local
SQLite room still exists. For the simplest test, create a fresh room each time the
tunnel URL changes.

## Troubleshooting

- If `cloudflared` cannot be found, rerun `scripts/install-cloudflared.ps1`.
- If port 8000 is busy, use `scripts/start-quick-tunnel.ps1 -Port 8010`; the public
  URL remains HTTPS and does not expose that local port number.
- The launcher refuses to reuse an occupied port so it cannot accidentally expose
  a different local development service.
- If the tunnel does not start and `%USERPROFILE%\.cloudflared\config.yml` exists,
  temporarily move that existing Cloudflare configuration out of the directory;
  Quick Tunnels do not use an account tunnel configuration.
- Corporate or campus networks may block Cloudflare Tunnel traffic. Try another
  network if the connector cannot reach Cloudflare.
- Never commit `.tools`, SQLite files, room session tokens, or tunnel logs.

Official references:

- <https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/>
- <https://developers.cloudflare.com/tunnel/downloads/>
