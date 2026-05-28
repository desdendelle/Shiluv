## Requirements:

ID|Requirement|Note
--|-----------|----
R1|This sw will be used by a small group| Up to 15 users
R2|Roles are: workers, manager
R3|This sw works on a weekly cycle
R4|The "programatsia" .xlsx file will be uploaded to the sw weekly|On or before Monday morning|
R5|The "programatsia" file will be automatically converted to the shift schedule|
R6|The shift schedule will be available for viewing starting Monday noon|
R7|An alert will be sent if the "programatsia" file is not uploaded on time or not valid
R8|Workers shall be able to exclude shifts from the shift schedule until Saturday at 2300 hours.
R9|The duty roster shall be made available for manager review on Sunday morning
R10|The sw will alert the manager if no roster was authorized after Tuesday noon
R11|All UI shall be in Hebrew|No other language support is needed

## Implementation Highlights:

ID|Item|Note
--|-----------|----
IH1|All times are Israel local time|Use the `Asia/Jerusalem` timezone; hours will move with IDT|
IH2|Roster generation (Hence: RG): A Python function will run weekly| at 0100 hours Sunday|
IH3|Inputs to RG: context + requests| Context: output of the previous run. Requests: user requests|
IH4|Output of RG: context + roster|
IH5|The backend will be initially implemented using FastAPI|with development-only dummy authentication, to support the development and testing of the front-end and of the RG function
IH6|The production backend will be AWS based|Using Lambda, S3, REST-API GW|
IH7|The backend will have a documented REST API|Documented using OpenAPI|
IH8|The frontend will be a static site|
IH9|The frontend will be a mobile-first app/site|
IH10|The frontend will be hosted on Cloudflare|
IH11|The production AWS backend will be implemented as a Python-based CDK stack|

## API Specification

A suggested OpenAPI draft is available at [backend/docs/openapi.yaml](backend/docs/openapi.yaml).

## Development

### Backend stub

The FastAPI development stub is implemented in `backend/dev_server`. Run
backend commands from the `backend` directory so the `dev_server` package is on
the Python import path.
Academic exercise scaffolds for backend business logic live in
`backend/dev_server/business_logic.py`. The current upload conversion function
accepts the uploaded programatsia bytes, extracts example workbook metadata, and
returns a constant but valid shift schedule.

Development users:

| Username | Password | Role |
| -------- | -------- | ---- |
| manager | manager | manager |
| user1 | user1 | worker |
| user2 | user2 | worker |

Run locally:

```bash
cd backend
python3 -m venv venv
. venv/bin/activate
pip install -r requirements-dev.txt
./run_dev_server
```

`run_dev_server` uses the active virtualenv's `python -m uvicorn` entry point and
sets `PYTHONPATH` to the `backend` directory.

The backend is available at `http://localhost:8000`. Its generated API docs are available at `http://localhost:8000/docs`.
If `frontend/build/web` exists, the same FastAPI process serves the Flutter static site at `http://localhost:8000/`.

Run backend tests:

```bash
cd backend
PYTHONPATH=. python -m pytest tests
```

### Frontend draft

The first Flutter Web draft is implemented in `frontend`.
The manager upload screen accepts `.xlsx` programatsia files only and sends the
selected file to the FastAPI development backend for schedule conversion.
The schedule screen checks programatsia status before requesting the converted
schedule, so a missing upload does not generate an expected `409 Conflict` in
the development server logs.
The Flutter API client decodes response bytes as UTF-8 explicitly so Hebrew
strings returned by the backend render correctly.

This container has a local Node/npm and Flutter toolchain installed under `.tools`.
Use these environment variables when running Flutter in this container so Flutter
uses the workspace-local cache and analytics opt-out settings:

```bash
export PATH="$PWD/.tools/flutter/bin:$PWD/.tools/node/bin:$PATH"
export HOME="$PWD/.tools/home"
export XDG_CONFIG_HOME="$PWD/.tools/home/.config"
export PUB_CACHE="$PWD/.tools/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
```

Run locally:

```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Build the static frontend:

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=http://localhost:8000
```

The generated static site is written to `frontend/build/web`. The committed
development snapshot should target `http://localhost:8000` so the backend dev
server can run the full local flow.
The FastAPI development server sends no-cache headers for the static frontend,
and the Flutter HTML template unregisters old service workers so local browsers
do not keep serving a stale UI.

### Committed frontend build snapshot

For now, `frontend/build/web` is intentionally committed to git. This is a
temporary development convenience: backend developers can run the FastAPI dev
server end-to-end without installing Flutter, Node.js, npm, or any additional
static-file server.

This is a deliberate tradeoff and a technical debt. Build outputs are normally
kept out of git because repeated rebuilds increase repository size, make diffs
noisy, and can leave the committed static site stale relative to `frontend/lib`
or `backend/docs/openapi.yaml`.

Best practices while this snapshot is committed:

- Commit `frontend/build/web` only for intentional handoff snapshots.
- Do not commit every local frontend rebuild.
- Rebuild and recommit the snapshot after user-visible frontend changes that
  backend developers need for local end-to-end testing.
- Keep `frontend/.dart_tool`, pub caches, coverage output, and non-web build
  outputs ignored.
- Replace this with a CI-produced downloadable artifact when the project has a
  GitHub Actions workflow.

Installed local tool versions:

- Node.js `v26.2.0`
- npm/npx `11.13.0`
- Flutter `3.44.0`
- Dart `3.12.0`

## Dependency Notes

- `fastapi` is used for the local API stub because it matches the planned backend framework and generates OpenAPI documentation.
- `uvicorn` is used as the local ASGI development server for FastAPI.
- `python-multipart` is required by FastAPI for `.xlsx` file uploads.
- `pytest` and `httpx` are used for backend API tests.
- `go_router` is used for Flutter route management.
- `flutter_riverpod` is used for frontend state management.
- `http` is used by the Flutter frontend to call the backend API.
- `web` is used for browser file-upload APIs without deprecated `dart:html` imports.
- `cupertino_icons` is included so Flutter's web icon font bundle is complete when framework widgets reference Cupertino icon data.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
