# AI handover — ImDownForWhatever

Updated: 2026-09-24. Treat this as project context; the user's current instructions take precedence.

## Read this first

- The product is a friends' decision app: create/join a room by code, host-created polls, then a category wheel and an activity wheel within the selected category.
- For new development, start from an up-to-date `main` and create a new feature branch for the task. Preserve any existing uncommitted work before switching branches.
- Confirm the working checkout and branch with `git rev-parse --show-toplevel` and `git branch --show-current` before editing; do not assume a developer's local directory layout.
- The room/host slice and loading/results QOL follow-up have been demoed and received positive feedback. The reviewing developer explicitly authorized committing and publishing these changes after the demos and documentation review. They will create the pull request and merge it themselves. Preserve the demo-before-commit workflow for subsequent changes.
- Start by reading `git status`, this file, and relevant source/tests. Preserve uncommitted work. Do not reset, clean, switch branches, publish, or merge to tidy up.
- At the end of each session, replace stale facts here: what changed, checks actually run, current demo state, unresolved issues, and the next concrete task. Never claim tests or physical-device checks passed without evidence.

## What this development slice implements

- Rooms exist independently of polls. Creation opens an empty lobby; friends join by a four-character code and display name.
- The server assigns a random private session token and public participant ID. Host authority is enforced on the server, never inferred from a name or a client-provided role.
- The host can allow/lock **new joins**, create a poll, and end the current poll. Locking is distinct from ending a poll. Existing members can reconnect to a locked room.
- Repeated polls keep the same room and members. A new poll gets a fresh ID and vote map; delayed votes/close requests referencing old polls are rejected.
- Voting is first-valid-vote-wins per member per poll. The client shows a pending state and waits for the server's personalized `selected_option` before claiming success.
- The server broadcasts countdown/state snapshots once per second while a room with a poll has connections, including automatic expiration and results. Clients do not decide final closure independently.
- Finished polls transition with a short fade to a dedicated results screen (winner, tie, or zero votes). Results are driven by the room snapshot, not a new socket/stacked route; the next open poll returns everyone to voting automatically. Android back/Back to lobby reveals the lobby; repeated closed-poll heartbeats do not reopen dismissed results. View results reopens them.
- Removed the redundant "Your vote is counted." message. The selected option stays highlighted and exposes selected accessibility semantics; the pending confirmation message remains until the server acknowledges.
- Room entry has a full loading view with a bottom indeterminate progress bar, actual REST/session/socket stage messages, and a slow-connection explanation after five seconds. It deliberately does not invent completion percentages. Retry messages include the retry delay; errors still exit to the existing recovery UI.
- Participants are shown as online/away. Back navigation disconnects the socket but retains membership.
- Sessions are saved locally by server URL + room code with `shared_preferences`. Joining the same code restores the identity/host role/vote. A stale token is cleared on 401/404; the next explicit join can create a new membership.
- Sockets authenticate in the first JSON frame (not URL query strings) and retry transient disconnects after 1/2/4/8/15 seconds. Closed/invalid sessions stop retrying. Controls are disabled until a fresh state arrives.
- Copy-code button, uppercase/alphanumeric/four-character input formatter, and root README instructions are included.
- App-visible title is ImDownForWhatever. Dart package `fastpoll`, Android application ID `com.fastpoll.fastpoll`, and configuration key `FASTPOLL_API_BASE` intentionally remain unchanged.

## Source map

| File | Responsibility |
|---|---|
| `server/main.py` | Pydantic request validation, Room/Member/Poll/Wheel state, host authorization, REST, authenticated WebSocket voting, lifespan ticker |
| `server/test_main.py` | REST/WebSocket permission, expiration, validation, polls, wheel editing/spins/broadcasts/reconnect |
| `mobile/lib/models/poll_model.dart` | Typed session, participant, room and poll snapshots; result labels; incorporates wheel snapshot |
| `mobile/lib/models/wheel_model.dart` | Typed category, activity, and authoritative wheel result models |
| `mobile/lib/models/wheel_preset.dart` | Built-in editable starter sets for category/activity wheels |
| `mobile/lib/services/api_service.dart` | REST, session persistence, socket authentication/retry, host wheel editing and spin requests |
| `mobile/lib/screens/choices_screen.dart` | Host category/activity editor, built-in wheel starter sets, and full-page edit forms |
| `mobile/lib/widgets/wheel_panel.dart` | Category/activity list, host editing and spins, guest observation, authoritative result display |
| `mobile/lib/screens/home_screen.dart` | Name, create/join room, code input formatting, recent saved rooms |
| `mobile/lib/screens/host_screen.dart` | Poll creation form within an existing room |
| `mobile/lib/screens/vote_screen.dart` | Room coordinator, lobby/host/voting controls, socket lifetime, results transition and back handling |
| `mobile/lib/screens/poll_results_screen.dart` | Dedicated winner/tie/no-vote screen, tallies, back and next-poll actions |
| `mobile/lib/widgets/room_loading_view.dart` | Bottom progress bar, current status, five-second slow-connection message |
| `mobile/test/widget_test.dart` | UI/model/service checks using fake sockets and mock preferences/HTTP; currently 20 tests |
| `mobile/integration_test/widget_suite_test.dart` | Executes the same widget suite on Android |
| `mobile/integration_test/room_journey_test.dart` | Host Flutter UI and a second real network session against a running server |
| `.github/workflows/ci.yml` | Existing real server/mobile CI; not changed in this slice |
| `.github/workflows/build.yml` | Legacy README artifact workflow; not app verification |

## API contract (breaking change from the original scaffold)

Base URL: `http://10.0.2.2:8000` on Android emulator. Override with `--dart-define=FASTPOLL_API_BASE=...`.

- `GET /health` → `{"status":"healthy"}`.
- `POST /api/rooms` with `{"name":"Alex"}` → 201 session `{room_code, session_token, name}`. No poll is created.
- `POST /api/rooms/{code}/join` with `{name, session_token?}` → session. Omit token only for a new participant; a valid saved token resumes membership even when locked.
- `PATCH /api/rooms/{code}` with `{"is_open":false}` → personalized room snapshot. Host only.
- `POST /api/rooms/{code}/polls` with `{topic, options, duration}` → 201 room snapshot. Host only; reject if a poll is still open. Duration is integer seconds, 1–3600. Topic max 200; 2–5 distinct nonblank options, max 100 each.
- `POST /api/rooms/{code}/polls/{poll_id}/close` → room snapshot. Host only; poll ID must be current. Repeated close of the same poll is safe.
- `POST /api/rooms/{code}/categories` with `{"name":"Games"}`; `PATCH`/`DELETE /api/rooms/{code}/categories/{category_id}`.
- `POST /api/rooms/{code}/categories/{category_id}/activities` with `{"name":"Mario Kart"}`; `PATCH`/`DELETE /api/rooms/{code}/categories/{category_id}/activities/{activity_id}`.
- `POST /api/rooms/{code}/wheel/category-spin` chooses a category on the server and clears any old activity result. `POST /api/rooms/{code}/wheel/activity-spin` chooses from the current category and retains that category. All wheel editing and spin routes are host-only.
- Category/activity names are trimmed, nonblank, at most 100 characters, and unique case-insensitively within their list. Missing IDs return 404; empty spin lists or an activity spin without a usable selected category return 409.
- Host endpoints take `Authorization: Bearer <session_token>`. Never send tokens in room broadcasts or expose them in UI/logs.
- `WS /ws/{code}`: first frame `{"session_token":"..."}` within 10 seconds. Unknown room closes 4404; invalid token closes 4401.
- Vote frame: `{"action":"CAST_VOTE","poll_id":"...","option_id":0}`. Invalid messages produce `{event:"ERROR", message:"..."}`.

Snapshot shape:

```json
{
  "event": "STATE_UPDATE",
  "room_code": "AB12",
  "is_open": true,
  "is_host": true,
  "participant_id": "public-member-id",
  "participants": [{"id":"public-member-id","name":"Alex","is_host":true,"online":true}],
  "poll": {
    "id": "unique-poll-id",
    "topic": "Dinner?",
    "status": "open",
    "time_left": 60,
    "options": [{"id":0,"text":"Tacos","votes":0},{"id":1,"text":"Pizza","votes":0}],
    "selected_option": null,
    "winner_ids": []
  },
  "categories": [{"id":"category-id","name":"Games","activities":[{"id":"activity-id","name":"Mario Kart"}]}],
  "wheel": {
    "spin_id":"server-generated-id",
    "phase":"activity",
    "selected_category_id":"category-id",
    "selected_activity_id":"activity-id",
    "result":"Mario Kart",
    "status":"finished"
  }
}
```

`poll` is null in an empty lobby. `selected_option` is private to the recipient. Winner IDs are populated only after closure, and empty when there were no votes.

## Run, check, and demo

See README for normal setup commands. Use one Uvicorn worker. SQLite restores saved rooms on restart; socket connections reconnect.

Use the environment available in your checkout:
- Reference toolchain: Flutter 3.47.2 / Dart 3.13.2; CI uses Python 3.11. Check installed versions with `flutter --version` and `python --version`.
- Create and activate an ignored `.venv` in the repository root, then install `server/requirements.txt`; see README for platform-specific activation commands.
- From the repository root, run `python -m uvicorn server.main:app --host 127.0.0.1 --port 8000`.
- Discover available devices with `flutter devices`; substitute the selected ID for `<device-id>` in the commands below.
- From `mobile/`, run `flutter analyze`, `flutter test`, and `flutter build apk --debug -t lib/main.dart`.
- If the host test runner cannot start, investigate the environment separately from test failures. The same widget suite can run on Android with `flutter test integration_test/widget_suite_test.dart -d <device-id>`. Record which runner actually passed.
- To check CI font/layout behavior on Android, run `flutter run -t integration_test/widget_suite_test.dart -d <device-id> --use-test-fonts` and inspect the test summary before quitting. The home test explicitly uses CI's 800×600 viewport. Device tests with normal fonts alone missed the validation-message failure described below.
- With the server running, run `flutter test integration_test/room_journey_test.dart -d <device-id>` for the real-server journey. Physical devices need the `FASTPOLL_API_BASE` override described in README.
- After device tests, use `flutter run -t lib/main.dart -d <device-id>` to restore the normal app for a demo; do not leave the integration-test build installed as the demo.
- Diagnose build warnings by their cause and final exit status. Do not equate a warning with a failed build or a runner startup failure with a passing test.

Demo checklist before committing:
1. Create a room and join from another device/session; see both participants.
2. Host locks joins: new join is refused, existing friend reconnects successfully.
3. Start a poll, cast votes, see synchronized counts and server-confirmed selection.
4. End it early and verify result; also allow a separate poll to expire naturally.
5. Start a second poll without leaving; old selections reset and the code stays the same.
6. Return home/rejoin or restart the app; saved identity and vote return while the server remains running.
7. Check copy-code and lowercase/pasted code input.
8. Obtain the reviewing developer’s demo feedback/authorization before any commit or push.

## Important limitations — do not mark these done

- SQLite room recovery is implemented (see 2026-10-01 persistence update). Still single-process with no room deletion/TTL, multi-worker pub/sub, or historical poll collection. Only the latest poll/spin is retained; old rooms/members accumulate in the database.
- Private bearer sessions are not accounts. Clearing app data or joining from another installation can create another voter; this is not abuse-proof identity. Tokens in `shared_preferences` are not encrypted secure storage. Use platform secure storage and HTTPS/WSS before a public launch.
- No host transfer, kick/ban, permanent room close, or explicit membership deletion. Back means disconnect/away, not leave permanently.
- Wheel results are immediate server decisions. The client animates the relevant category/activity wheel toward the authoritative selected segment; the server does not wait for animation completion.
- No iOS/macOS/web platform scaffold; Android is the current target.
- Reconnect has no jitter or application-level dead-connection timeout. A silently blackholed connection may need stronger heartbeat detection. Server send timeouts drop stale sockets from the room list.
- Network retry/session persistence tests cover key state behavior, but airplane-mode/process-kill testing on physical phones remains outstanding.
- Local device integration uses a host UI plus a second programmatic real WebSocket participant; it does NOT prove two physical phones work.
- No public hosting/deployment or branch-protection change. `main` was unprotected at the earlier review; verify current settings before changing anything.
- New API is incompatible with the original app. Upgrade both server and client together.

## Next work, in order

1. **Review and demo the wheel feature.** The implementation is on `codex/wheel-feature`. Complete Android device/demo validation when the SDK/device runner is available, then follow the team's established review and pull-request ownership before landing it.
2. **Persistence and lifecycle.** Decide with the team whether a durable single-server store is enough. Separate storage access from route handlers, persist rooms/members/polls/wheel data, introduce room expiry and a deliberate host recovery policy. Multiple workers require shared broadcasts as well as a shared database; a database alone does not solve sockets. Keep tokens private at rest and in queries.
3. **Reliability and real devices.** Run the README flow on two physical Android devices over LAN; cover app background/resume, airplane mode, failed vote confirmation, host reconnect, and server restart. Add heartbeat timeout/backoff jitter where the observed behavior warrants it. Demo the category/activity editor and both spins on Android when the SDK/device runner is available.
4. **Team housekeeping.** Enable branch protection/required server and mobile CI checks if requested by the team; consider retiring the legacy README-only Build workflow. Pin tool/dependency versions for repeatability. Rename internal FastPoll identifiers only in a separate coordinated change if desired.

When changing the contract: update Python schemas/state, Dart parsing/service, both sides' tests, and this file together. Preserve server-side host checks, poll ID validation, first-vote semantics, and personalized selection. Never replace failing checks with placeholders to make CI green.

## End-of-session validation / review state

Verified locally on 2026-09-24:
- `pytest server/ -q`: **14 passed** (Python 3.9 local environment; CI uses 3.11).
- `flutter analyze`: **no issues**.
- Android `integration_test/widget_suite_test.dart`: **12 passed**.
- Android `integration_test/room_journey_test.dart`: **1 passed** against the real local server, covering host UI + a second independent network participant, locked joins, repeat polls, shared result, and restored vote after reconnect. QOL follow-up also passed automatic expiration → dedicated results coverage.
- `flutter build apk --debug -t lib/main.dart`: **passed**; normal app build verified for the demo.
- `git diff --check`: clean.
- Host-based `flutter test` was not verified because its runner could not start in the validation environment. The Android wrapper ran the same twelve tests successfully; do not report the host runner as passing.
- Two physical phones have **not** been tested. Local results above do not establish remote CI status; check the latest GitHub Actions run after publication.

The feature and QOL builds have been demoed and received positive feedback. Documentation review is complete, and committing/publishing has been authorized. Pull-request creation and merging are reserved for the reviewing developer. Start a fresh server/app session using the commands above rather than assuming a previous developer's processes are running. Wheels and persistence are the next feature work.

### QOL follow-up (2026-09-24)

Requested QOL changes: clearer room loading, remove redundant vote-confirmed text, and a dedicated results screen. Implemented all three. Updated widget checks cover slow loading, actual progress callbacks, selection without confirmation text, results/back/heartbeat behavior, guest restrictions, and tie/zero-vote outcomes. Widget suite: **12 passed on Android**. Live-server Android journey: **1 passed**, including manual ending and natural expiration into the dedicated results screen. Normal Android debug APK: **built, installed, and launched**. Flutter analysis and diff whitespace checks: **clean**. The QOL demo received positive feedback; committing and publishing have been explicitly authorized. The reviewing developer will handle the pull request and merge.

### CI test follow-up (2026-09-24)

PR CI reported 11 passing Flutter tests and one failure: the home test could not find `Enter your name first.`. Reproduced locally on Android using the 800×600 viewport **and** `--use-test-fonts`; the same viewport with normal device fonts passed. The test font wraps the form enough that the validation message is an unbuilt child of the scrolling list. The test now scrolls the vertical form to the message and locates the room-code field by its label before entering text. No application behavior changed, and no assertions were removed.

All **12 suite tests passed** after the fix with the test font and CI viewport (the live runner additionally counts its teardown). The native host runner still crashes before executing tests; do not claim a native `flutter test` pass. The user authorized fixing and pushing this CI follow-up to the existing development branch. Verify the new GitHub Actions result after publication; a closed pull request must be reopened by the reviewing developer for PR CI to run. Pull-request merging remains their responsibility.

### Poll templates follow-up (2026-09-25)

Added editable Activities, Food, and Time presets plus Custom (clears the draft) to the existing host poll form. Selecting a template replaces the draft; the form explains this. Duration is preserved. All fields remain mounted while scrolling so validation covers the whole form. The closed-poll lobby now displays the existing result summary (winner, tie, or no votes), and lobby/live vote counts use singular wording for one vote.

Work is on `codex/poll-templates`, created from the current local main. No remote freshness check, commit, push, or merge was performed. Existing local iOS scaffold, metadata, analysis options, and lockfile changes were preserved. This supersedes the earlier no-iOS-scaffold note for this working checkout; the scaffold is user work and has not been validated here.

Validation: Flutter analysis passed; all 13 native Flutter tests passed, including editing a template, switching to a shorter template, and clearing with Custom. This supersedes the earlier native runner limitation for this machine. Simulator visual review of these new changes remains pending. Next: hot restart the app, open Start another poll, and demo template editing and closed-poll results before committing.

### Two-stage wheel implementation (2026-09-28)

Implemented room-owned categories and activity lists with stable server-generated IDs, host-only CRUD routes, category/activity spin routes, and wheel state in every `STATE_UPDATE` snapshot. The server chooses the result and spin ID. Category re-spins clear the old activity selection; activity spins retain the selected category. Empty spin lists and missing/stale selections return 409; missing category/activity IDs return 404. Name validation trims values and rejects blanks or case-insensitive duplicates.

Flutter now parses wheel snapshots, exposes authenticated wheel/category APIs, and renders a dedicated category/activity wheel panel with host-only editing/spinning, guest observation, reconnect restoration, and an animation that lands on the server-selected segment. Poll coordination and APIs remain in place.

Validation in this checkout: `python -m py_compile server/main.py server/test_main.py` passed; `python -m pytest server/ -q` passed (**18 passed**, one Starlette/httpx deprecation warning); `flutter analyze` passed (**no issues**); the widget test suite passed (**16 passed**) in a temporary clean copy to avoid stale build-cache references. Android device/integration tests and APK build were not run because the sandbox could not access the configured Android SDK's `adb.exe`. The Flutter animation has not had a device visual review. No commit or push was made. The active working branch is `codex/wheel-feature`.

### Wheel pointer polish (2026-10-01)

On `codex/wheel-pointer`, changed the fixed pointer to face inward and overlap the rim, with a contrasting outline and shadow. Added a continuous rim and outlined hub detail. Corrected repeated-spin rotation to travel from the current angle to the authoritative target without a completion jump; restored results now initialize at the selected angle. No server/API changes. Flutter analysis passed and all 17 existing Flutter tests passed; diff whitespace check passed. Simulator visual demo remains pending: hot restart and check initial/restored results plus repeated category/activity spins. No commit or push performed.

### Delayed wheel reveal (2026-10-01)

Category and activity result cards now stay hidden until the local animation reports completion. The selected-slice outline is also hidden during animation. The panel shows Spinning… and disables wheel editing/spin actions while spinning. Repeated snapshots do not reset reveal timing; already completed results show immediately on initial mount. Added a regression test covering both phases and an intervening repeated snapshot. Flutter analysis passed; all 18 tests passed. Simulator visual demo remains pending. Changes remain uncommitted on codex/wheel-pointer alongside the pointer improvements.


### Durable rooms and choices (2026-10-01)

Added server/storage.py using transactional SQLite snapshots. The server restores rooms at startup and saves changes before successful mutation responses or broadcasts; unchanged heartbeats do not rewrite the database. Persisted: members (token digests only), host, join lock, current poll/options/votes/deadline/closed state, categories/activities, and latest wheel selection. Connections and locks are recreated, never persisted. Expired polls close after downtime. Storage failures return 503 for REST mutations and roll back in-memory room data to its committed snapshot; failed vote saves report an error instead of confirmation. Ticker save failures retry on subsequent ticks.

Default database: server/data/rooms.sqlite3, ignored by Git, owner-only permissions. FASTPOLL_DB_PATH overrides its location. Continue running one worker; no distributed broadcasts, TTL, full history, or account-based host recovery. Existing rooms in a running pre-persistence server cannot be recovered after it stops. The first restart enables persistence for newly created rooms. No running server was stopped in this change.

Verification: all 21 server tests passed using a temporary Python environment. New tests exercise lifecycle restart recovery, host/member authentication in a locked room, saved votes/wheel choices, online status reset, explicit poll closure, offline deadline expiration, token privacy, and failed-save rollback. Existing Flutter edits from the wheel reveal task are preserved. No commit/push performed. Next demo: restart the backend once, create a room and choices, then restart again and rejoin the same code on the same app installation.


### Choices pages and appearance polish (2026-10-01)

User requested full-page category/activity editing, a less crowded host lobby, and a custom palette with dark mode. The user demoed the changes, approved them, and authorized committing to the development branch. The user will handle the merge to main.

- `mobile/lib/screens/choices_screen.dart`: host management page plus full-page add/rename forms. Forms validate blank/duplicate names, preserve drafts on failure, prevent double submissions, and surface server errors where the user is editing. Deletion still uses confirmation. `VoteScreen` owns a `ValueNotifier<ChoicesState>` so the open editor receives the existing socket's room and connection updates without starting a second socket. Server host authorization remains unchanged.
- `WheelPanel` now shows a compact category/activity count and **Manage choices** action instead of inline editing. Spin animation/reveal behavior is preserved.
- `mobile/lib/theme/app_theme.dart`: shared cream/teal light palette and slate/teal dark palette, rounded controls, typography, and appearance menu. `FastPollApp` restores/saves the system/light/dark preference with SharedPreferences under `appearance`. Choice pages, home, and lobby expose the menu; the theme applies across all routes. Wheel labels now use theme-aware contrast.
- Validation: Flutter analysis passed; all **20** widget/service checks passed on Android, also passed on the Android live runner with the CI test font. The theme preference test was rerun successfully after refining its menu-item finder. Native host runner was not used for this follow-up due the previously observed startup crash. Debug APK built successfully. Manual emulator review covered light/dark home/lobby/choices screens and creating a category and activity through the running local server. No backend or API changes.
- Demo review complete: the user reported that everything looks good and authorized the development-branch commit. The running backend was preserved; restarting it is required to load any previously merged backend updates, so do not treat this UI demo as persistence-restart validation.


### Wheel starter sets and recent rooms (2026-10-01)

Added editable Food & drinks, Game night, and Out & about starter sets in the host choices page. Applying a set adds missing categories and activities through the existing host-authenticated endpoints, skips case-insensitive duplicates, preserves the room's current choices, and reports partial progress/errors. New add endpoints expose their returned room snapshot to support reliable category IDs while importing.

The home screen now lists up to 12 recently entered rooms, newest first. Saved credentials continue using the existing server-scoped session keys; a separate ordered index supports the list, migrates older saved-room keys, and is cleaned up when sessions are removed or rejected by the server. Tapping a room rejoins with its saved name/token; the close action forgets that room on this device.

Changed: `mobile/lib/models/wheel_preset.dart`, `mobile/lib/services/api_service.dart`, `mobile/lib/screens/choices_screen.dart`, `mobile/lib/screens/home_screen.dart`, and this handover file. Dart formatting was run. Flutter analysis/tests and emulator review were not run in this session. No commit or push made.
