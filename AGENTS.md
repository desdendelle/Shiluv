## Permanent directives from the user

The following are "always true" directives. Follow them throughout the session unless I explicitly override one.

### Environment and permissions
- You are running inside a dedicated Docker container, so the potential for "local" damage is very small. Act accordingly and do not be overly cautious about routine commands.
- Do not spin up an additional sandbox to run local commands — the Docker container is itself the sandbox.
- Do not ask for permission to perform routine operations. Ask only in genuinely risky situations, specifically:
  - Deletion of whole files or directories
  - Force-pushes, branch deletions, or history rewrites 
  - Any network access to resources other than OpenAI, **except** for resources I explicitly request

### Quality and priorities
- Precision and correctness are more important than response time. Take the time needed to get it right.
- Treat cybersecurity as the highest priority in any code you produce: no hardcoded secrets, validate all external inputs, use safe defaults, and avoid known-vulnerable patterns and deprecated cryptography. **[SUGGESTED additions to the existing rule]**
- Do not hesitate to point out difficulties, ambiguities, or risks in my requests *before* executing them. This is especially important for anything involving cybersecurity or privacy — but speak up on any reservation. I want your opinion and to learn from your judgment.
- If a task is infeasible or under-specified, stop and ask the user rather than silently producing partial or guessed output. When you must assume something, state the assumption at the top of your response.

### Communication
- Correct my wording and spelling when you spot mistakes, but notify me when you do.
-  Prefer one focused clarifying question over silent assumptions when a request is ambiguous.
-  Keep status updates concise — summarize what changed, why, and any follow-ups. No filler.

### Documentation
- Automatically update `README.md` and `AGENTS.md` to reflect any changes you make to behavior, structure, or setup.
- If the current folder is a git repository and `README.md` exists, by default:
  - Add a section noting the project is licensed under MIT
  - Add a local copy of the MIT license (typically `LICENSE` at the repo root)
  - Link from the `README.md` to the local license file
  -  If a non-MIT license is already present, or if I've indicated a different license elsewhere, do not silently override it — ask first.

### Version control
- Refuse to commit files that contain sensitive information, including (but not limited to) usernames, internal IP addresses, hostnames, passwords, API keys, tokens, private keys, `.env` files, and connection strings.
- whenever a file with secrets exists (E.g., credentials.yaml), create an example file with place-holder secrets. The example file name should end with _example (E.g., credentials.yaml_example)
- Before any commit, scan staged content for secret-like patterns (long hex/base64 strings, `password=`, `api_key=`, `BEGIN PRIVATE KEY`, AWS-style `AKIA...` prefixes, etc.) and flag anything suspicious to me before proceeding.
- Maintain a sensible `.gitignore` (virtualenvs, `__pycache__`, build artifacts, local secrets, IDE files). Update it when you introduce new tooling.
- Use conventional commit messages (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`) with a short summary line and a body when context helps.

### Language preferences
- Prefer Python over other languages. Specifically, unless the script is short and trivial, prefer Python over sh/bash.
- For Python: target a current supported version, use type hints, follow PEP 8, prefer the standard library before reaching for third-party dependencies, and prefer `pathlib` over `os.path`.
- When adding any third-party dependency, briefly justify why it's needed and pin a version in the relevant manifest (`requirements.txt`, `pyproject.toml`, etc.).
- Prefer serialization to YAML and end those file-names with ".yaml"

### Code commenting style
Comment code using the following numbered format:

```python
# 1. This code does X
code
code
#    1.1  Sub-functionality
code
```

### Testing
- After any non-trivial change, run the existing test suite and report the results. Do not declare a task done if tests fail.
- Write tests for new features and regression tests for any bug you fix. If you cannot, say why.
- If a critical path you touched has no test coverage, mention it explicitly.

### Error handling and logging
- Fail loudly on unexpected states; do not silently swallow exceptions. Catch narrowly, not broadly.
- Use the `logging` module rather than `print` for anything beyond throwaway scripts.

## Project-specific decisions

### Product scope
- This project manages a weekly shift schedule and duty roster for a small group of workers and managers.
- All user-facing UI text must be Hebrew. No other UI language support is required.
- Use `Asia/Jerusalem` as the canonical timezone name in code, APIs, and persisted data. Avoid ambiguous timezone labels such as `IST`.

### API
- Maintain the suggested OpenAPI specification in `backend/docs/openapi.yaml`.
- Treat the OpenAPI file as the frontend-backend contract. Update it when endpoint behavior, schemas, roles, or workflow states change.
- Keep API enum values stable, ASCII, and developer-facing. Render all user-facing labels and messages in Hebrew in the frontend.
- The development backend uses HTTP Basic authentication with the dummy users documented in `README.md`.
- Production code must replace development authentication with server-validated identity and authorization.

### Backend
- Implement the backend in Python.
- Keep all backend-owned code, tests, dependency manifests, and API docs under `backend`.
- The local development backend is a FastAPI application under `backend/dev_server`.
- Run backend Python commands from `backend` with `PYTHONPATH=.` so the `dev_server` package resolves correctly.
- Keep the FastAPI stub aligned with `backend/docs/openapi.yaml` as the protocol evolves.
- The production AWS backend will be implemented as a Python-based CDK stack.
- Use `backend/requirements.txt` for runtime dependencies and `backend/requirements-dev.txt` for test/development dependencies until the project adopts a different Python packaging approach.
- The development FastAPI server should serve `frontend/build/web` at `/` when the frontend has already been built. This is a localhost-only convenience so backend developers can inspect the frontend without Flutter or a separate static web server.
- Run the development server from `backend` with `./run_dev_server` after activating the existing virtualenv.
- `backend/run_dev_server` should invoke `python -m uvicorn` from the active virtualenv rather than a direct `uvicorn` console script, because moved virtualenvs can leave stale shebang paths.
- Keep the academic roster-generation exercise in `backend/dev_server/roster_generation.py`.
- Run backend tests from `backend` with `PYTHONPATH=. python -m pytest tests` after installing development dependencies in the active virtualenv.

### Frontend
- Implement the frontend as a Flutter Web mobile-first static app.
- Keep the Flutter project under `frontend`.
- The frontend build output should be suitable for static hosting on Cloudflare Pages.
- A local Node/npm and Flutter toolchain may exist under `.tools`; keep `.tools` untracked.
- Keep generated Flutter artifacts untracked, including `frontend/.dart_tool`, `frontend/build`, pub caches, coverage output, and symbol/map files.
- In this container, run Flutter with workspace-local environment variables:
  - `PATH=/workspace/code/.tools/flutter/bin:/workspace/code/.tools/node/bin:$PATH`
  - `HOME=/workspace/code/.tools/home`
  - `XDG_CONFIG_HOME=/workspace/code/.tools/home/.config`
  - `PUB_CACHE=/workspace/code/.tools/pub-cache`
  - `FLUTTER_SUPPRESS_ANALYTICS=true`
- Flutter and Dart analytics must remain disabled.
- Suggested core packages are `go_router` for routing and `flutter_riverpod` for async state management. Add pinned versions in the Flutter manifest when the frontend project is created.
- Organize frontend code by feature, for example:
  - `lib/features/schedule/`
  - `lib/features/roster/`
  - `lib/features/uploads/`
  - `lib/features/auth/`
  - `lib/api/`
  - `lib/models/`
  - `lib/shared/`
- Expected worker screens:
  - Weekly shift schedule view
  - Shift details
  - Shift exclusion and cancellation flow
  - Submitted exclusions summary
- Expected manager screens:
  - Programatsia upload
  - Upload validation and conversion status
  - Shift schedule review
  - Duty roster review
  - Roster authorization
  - Operational alerts and missed-deadline status
- Shared screens and components should include:
  - Current week selector
  - Role-aware navigation
  - Server time and deadline display
  - Loading, empty, error, and retry states
- The frontend may hide actions after deadlines, but the backend must enforce all role permissions, upload validity, cutoff times, and authorization rules.
