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

The FastAPI development stub is implemented in `backend/src/shiluv_api`.

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

The backend is available at `http://localhost:8000`. Its generated API docs are available at `http://localhost:8000/docs`.
If `frontend/build/web` exists, the same FastAPI process serves the Flutter static site at `http://localhost:8000/`.

Run backend tests:

```bash
cd backend
PYTHONPATH=src venv/bin/pytest tests
```

### Frontend draft

The first Flutter Web draft is implemented in `frontend`.

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
flutter build web --release --dart-define=API_BASE_URL=https://api.example.invalid
```

The generated static site is written to `frontend/build/web`.

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
