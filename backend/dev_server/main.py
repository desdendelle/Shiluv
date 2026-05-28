from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, Response, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field

from .roster_generation import generate_duty_roster

TIMEZONE = ZoneInfo("Asia/Jerusalem")
MAX_UPLOAD_BYTES = 10 * 1024 * 1024
PASSWORD_ITERATIONS = 390_000
BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
FRONTEND_BUILD_DIR = REPO_ROOT / "frontend" / "build" / "web"


@dataclass(frozen=True)
class DevUser:
    id: str
    username: str
    display_name: str
    role: Literal["worker", "manager"]
    salt: str
    password_hash: str


# 1. These credentials are development-only and use hashes instead of plaintext.
DEV_USERS: dict[str, DevUser] = {
    "manager": DevUser(
        id="manager",
        username="manager",
        display_name="מנהל",
        role="manager",
        salt="shiluv-dev-manager",
        password_hash="6dbb850158bf4fe31188edec3fb56de51d87dc5bef7200c4e8b40fbd25a1595d",
    ),
    "user1": DevUser(
        id="user1",
        username="user1",
        display_name="משתמש 1",
        role="worker",
        salt="shiluv-dev-user1",
        password_hash="fc3e2613a37266039531f868c0044b7072f58816cb1ee683f714ffd143bc012e",
    ),
    "user2": DevUser(
        id="user2",
        username="user2",
        display_name="משתמש 2",
        role="worker",
        salt="shiluv-dev-user2",
        password_hash="047b7806f4127fcc94001e97c184e74c15d401a0b30394c5a08ffdaeaa85430a",
    ),
}


class ApiError(BaseModel):
    code: str
    message: str
    details: dict[str, object] | None = None


class ErrorResponse(BaseModel):
    error: ApiError


class HealthResponse(BaseModel):
    status: Literal["ok"]
    time: datetime


class ClientConfig(BaseModel):
    timezone: str = "Asia/Jerusalem"
    ui_language: Literal["he"] = "he"
    upload_deadline: str = "Monday morning"
    schedule_visible_from: str = "Monday 12:00"
    exclusion_cutoff: str = "Saturday 23:00"
    roster_review_from: str = "Sunday morning"
    roster_authorization_alert_after: str = "Tuesday 12:00"


class User(BaseModel):
    id: str
    username: str
    display_name: str
    role: Literal["worker", "manager"]
    active: bool = True


class Session(BaseModel):
    user: User


class Week(BaseModel):
    week_start: date
    timezone: str = "Asia/Jerusalem"
    programatsia_status: Literal["missing", "uploaded", "valid", "invalid", "converted"]
    schedule_status: Literal["not_available", "available"]
    roster_status: Literal["not_generated", "draft", "ready_for_review", "authorized"]


class ValidationIssue(BaseModel):
    code: str
    message: str
    row: int | None = Field(default=None, ge=1)
    column: str | None = None


class ProgramatsiaStatus(BaseModel):
    week_start: date
    status: Literal["missing", "uploaded", "valid", "invalid", "converted"]
    uploaded_at: datetime | None = None
    uploaded_by: str | None = None
    file_name: str | None = None
    validation_issues: list[ValidationIssue] = Field(default_factory=list)


class Shift(BaseModel):
    id: str
    starts_at: datetime
    ends_at: datetime
    label: str
    location: str | None = None
    required_workers: int = Field(default=1, ge=1)


class ShiftSchedule(BaseModel):
    week_start: date
    visible_from: datetime
    status: Literal["not_available", "available"]
    shifts: list[Shift]


class ShiftExclusionCreate(BaseModel):
    shift_id: str
    worker_id: str
    reason: str | None = Field(default=None, max_length=500)


class ShiftExclusion(BaseModel):
    id: str
    week_start: date
    shift_id: str
    worker_id: str
    reason: str | None = None
    created_at: datetime


class RosterAssignment(BaseModel):
    id: str
    shift_id: str
    worker_id: str
    notes: str | None = None


class GenerateRosterRequest(BaseModel):
    force: bool = False


class AuthorizeRosterRequest(BaseModel):
    approved: Literal[True]
    note: str | None = Field(default=None, max_length=1000)


class DutyRoster(BaseModel):
    week_start: date
    status: Literal["not_generated", "draft", "ready_for_review", "authorized"]
    generated_at: datetime | None = None
    generated_by: Literal["scheduled_job", "manager"] | None = None
    authorized_at: datetime | None = None
    authorized_by: str | None = None
    assignments: list[RosterAssignment] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class Alert(BaseModel):
    id: str
    week_start: date
    type: Literal[
        "missing_programatsia",
        "invalid_programatsia",
        "roster_not_authorized",
        "roster_generation_failed",
    ]
    severity: Literal["info", "warning", "critical"]
    status: Literal["open", "acknowledged", "resolved"]
    message: str
    created_at: datetime
    acknowledged_at: datetime | None = None
    acknowledged_by: str | None = None


@dataclass
class WeekState:
    week_start: date
    programatsia: ProgramatsiaStatus
    schedule: ShiftSchedule
    exclusions: dict[str, ShiftExclusion]
    roster: DutyRoster
    alerts: dict[str, Alert]


security = HTTPBasic()


def now() -> datetime:
    return datetime.now(TIMEZONE)


def to_public_user(user: DevUser) -> User:
    return User(
        id=user.id,
        username=user.username,
        display_name=user.display_name,
        role=user.role,
        active=True,
    )


def verify_password(user: DevUser, password: str) -> bool:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        user.salt.encode("utf-8"),
        PASSWORD_ITERATIONS,
    ).hex()
    return secrets.compare_digest(digest, user.password_hash)


def auth_error() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"code": "invalid_credentials", "message": "Invalid username or password"},
        headers={"WWW-Authenticate": "Basic"},
    )


def current_user(credentials: Annotated[HTTPBasicCredentials, Depends(security)]) -> DevUser:
    user = DEV_USERS.get(credentials.username)
    if user is None or not verify_password(user, credentials.password):
        raise auth_error()
    return user


def require_manager(user: DevUser) -> None:
    if user.role != "manager":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "manager_required", "message": "Manager role is required"},
        )


def parse_week_start(week_start: str) -> date:
    try:
        parsed = date.fromisoformat(week_start)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "invalid_week_start", "message": "weekStart must be an ISO date"},
        ) from exc
    if parsed.weekday() != 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "invalid_week_start", "message": "weekStart must be a Monday"},
        )
    return parsed


def visible_from(week_start: date) -> datetime:
    return datetime.combine(week_start, time(hour=12), tzinfo=TIMEZONE)


def exclusion_cutoff(week_start: date) -> datetime:
    return datetime.combine(week_start + timedelta(days=5), time(hour=23), tzinfo=TIMEZONE)


def sample_shifts(week_start: date) -> list[Shift]:
    return [
        Shift(
            id=f"{week_start.isoformat()}-sun-morning",
            starts_at=datetime.combine(week_start + timedelta(days=6), time(hour=8), tzinfo=TIMEZONE),
            ends_at=datetime.combine(week_start + timedelta(days=6), time(hour=16), tzinfo=TIMEZONE),
            label="משמרת בוקר",
            location="מוקד",
            required_workers=1,
        ),
        Shift(
            id=f"{week_start.isoformat()}-sun-evening",
            starts_at=datetime.combine(week_start + timedelta(days=6), time(hour=16), tzinfo=TIMEZONE),
            ends_at=datetime.combine(week_start + timedelta(days=6), time(hour=23), tzinfo=TIMEZONE),
            label="משמרת ערב",
            location="מוקד",
            required_workers=1,
        ),
        Shift(
            id=f"{week_start.isoformat()}-mon-morning",
            starts_at=datetime.combine(week_start + timedelta(days=7), time(hour=8), tzinfo=TIMEZONE),
            ends_at=datetime.combine(week_start + timedelta(days=7), time(hour=16), tzinfo=TIMEZONE),
            label="משמרת בוקר",
            location="שטח",
            required_workers=1,
        ),
    ]


def make_week_state(week_start: date) -> WeekState:
    programatsia = ProgramatsiaStatus(week_start=week_start, status="missing")
    schedule = ShiftSchedule(
        week_start=week_start,
        visible_from=visible_from(week_start),
        status="not_available",
        shifts=[],
    )
    roster = DutyRoster(week_start=week_start, status="not_generated")
    alerts = {
        f"{week_start.isoformat()}-missing-programatsia": Alert(
            id=f"{week_start.isoformat()}-missing-programatsia",
            week_start=week_start,
            type="missing_programatsia",
            severity="warning",
            status="open",
            message="Programatsia file has not been uploaded yet.",
            created_at=now(),
        )
    }
    return WeekState(
        week_start=week_start,
        programatsia=programatsia,
        schedule=schedule,
        exclusions={},
        roster=roster,
        alerts=alerts,
    )


WEEKS: dict[date, WeekState] = {}


def get_state(week_start: str) -> WeekState:
    parsed = parse_week_start(week_start)
    if parsed not in WEEKS:
        WEEKS[parsed] = make_week_state(parsed)
    return WEEKS[parsed]


def week_summary(state: WeekState) -> Week:
    return Week(
        week_start=state.week_start,
        programatsia_status=state.programatsia.status,
        schedule_status=state.schedule.status,
        roster_status=state.roster.status,
    )


def can_manage_worker(actor: DevUser, worker_id: str) -> bool:
    return actor.role == "manager" or actor.id == worker_id


def ensure_shift_exists(state: WeekState, shift_id: str) -> None:
    if not any(shift.id == shift_id for shift in state.schedule.shifts):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "shift_not_found", "message": "Shift was not found"},
        )


app = FastAPI(
    title="Shiluv API",
    version="0.1.0",
    description="FastAPI development stub for the Shiluv weekly roster workflow.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://localhost:5173",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.get("/health", response_model=HealthResponse, tags=["System"])
def get_health() -> HealthResponse:
    return HealthResponse(status="ok", time=now())


@app.get("/api/v1/config", response_model=ClientConfig, tags=["System"])
def get_config() -> ClientConfig:
    return ClientConfig()


@app.get("/api/v1/session", response_model=Session, tags=["Users"])
def get_session(user: Annotated[DevUser, Depends(current_user)]) -> Session:
    return Session(user=to_public_user(user))


@app.get("/api/v1/users", tags=["Users"])
def list_users(
    user: Annotated[DevUser, Depends(current_user)],
    role: Literal["worker", "manager"] | None = Query(default=None),
) -> dict[str, list[User]]:
    users = [to_public_user(candidate) for candidate in DEV_USERS.values()]
    if user.role != "manager":
        users = [to_public_user(user)]
    if role is not None:
        users = [candidate for candidate in users if candidate.role == role]
    return {"users": users}


@app.get("/api/v1/weeks", tags=["Weeks"])
def list_weeks(
    user: Annotated[DevUser, Depends(current_user)],
    from_date: date | None = Query(default=None, alias="from"),
    to_date: date | None = Query(default=None, alias="to"),
) -> dict[str, list[Week]]:
    _ = user
    if not WEEKS:
        monday = now().date() - timedelta(days=now().date().weekday())
        WEEKS[monday] = make_week_state(monday)
    weeks = [week_summary(state) for state in WEEKS.values()]
    if from_date is not None:
        weeks = [week for week in weeks if week.week_start >= from_date]
    if to_date is not None:
        weeks = [week for week in weeks if week.week_start <= to_date]
    return {"weeks": sorted(weeks, key=lambda week: week.week_start)}


@app.get("/api/v1/weeks/{week_start}", response_model=Week, tags=["Weeks"])
def get_week(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
) -> Week:
    _ = user
    return week_summary(get_state(week_start))


@app.get(
    "/api/v1/weeks/{week_start}/programatsia",
    response_model=ProgramatsiaStatus,
    tags=["Programatsia"],
)
def get_programatsia_status(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
) -> ProgramatsiaStatus:
    _ = user
    return get_state(week_start).programatsia


@app.post(
    "/api/v1/weeks/{week_start}/programatsia",
    response_model=ProgramatsiaStatus,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["Programatsia"],
)
async def upload_programatsia(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
    file: UploadFile = File(...),
) -> ProgramatsiaStatus:
    require_manager(user)
    state = get_state(week_start)
    file_name = file.filename or ""
    if not file_name.endswith(".xlsx"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "invalid_file_type", "message": "Only .xlsx files are accepted"},
        )
    content = await file.read(MAX_UPLOAD_BYTES + 1)
    if not content or len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "invalid_file_size", "message": "File is empty or too large"},
        )

    uploaded_at = now()
    state.programatsia = ProgramatsiaStatus(
        week_start=state.week_start,
        status="converted",
        uploaded_at=uploaded_at,
        uploaded_by=user.id,
        file_name=file_name,
    )
    state.schedule = ShiftSchedule(
        week_start=state.week_start,
        visible_from=visible_from(state.week_start),
        status="available",
        shifts=sample_shifts(state.week_start),
    )
    for alert in state.alerts.values():
        if alert.type == "missing_programatsia":
            alert.status = "resolved"
    return state.programatsia


@app.get("/api/v1/weeks/{week_start}/schedule", response_model=ShiftSchedule, tags=["Schedule"])
def get_shift_schedule(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
) -> ShiftSchedule:
    _ = user
    state = get_state(week_start)
    if state.schedule.status != "available":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "schedule_not_available", "message": "Schedule is not available yet"},
        )
    return state.schedule


@app.get("/api/v1/weeks/{week_start}/shift-exclusions", tags=["Exclusions"])
def list_shift_exclusions(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
    worker_id: str | None = Query(default=None),
) -> dict[str, list[ShiftExclusion]]:
    state = get_state(week_start)
    requested_worker = worker_id or (None if user.role == "manager" else user.id)
    if requested_worker is not None and not can_manage_worker(user, requested_worker):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "worker_forbidden", "message": "Cannot view another worker"},
        )
    exclusions = list(state.exclusions.values())
    if requested_worker is not None:
        exclusions = [item for item in exclusions if item.worker_id == requested_worker]
    return {"exclusions": exclusions}


@app.post(
    "/api/v1/weeks/{week_start}/shift-exclusions",
    response_model=ShiftExclusion,
    status_code=status.HTTP_201_CREATED,
    tags=["Exclusions"],
)
def create_shift_exclusion(
    week_start: str,
    payload: ShiftExclusionCreate,
    user: Annotated[DevUser, Depends(current_user)],
    x_allow_past_deadline: Annotated[bool, Header()] = False,
) -> ShiftExclusion:
    state = get_state(week_start)
    if not can_manage_worker(user, payload.worker_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "worker_forbidden", "message": "Cannot update another worker"},
        )
    if now() > exclusion_cutoff(state.week_start) and not x_allow_past_deadline:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "exclusion_cutoff_passed", "message": "Exclusion cutoff has passed"},
        )
    ensure_shift_exists(state, payload.shift_id)
    exclusion_id = f"{payload.worker_id}-{payload.shift_id}"
    exclusion = ShiftExclusion(
        id=exclusion_id,
        week_start=state.week_start,
        shift_id=payload.shift_id,
        worker_id=payload.worker_id,
        reason=payload.reason,
        created_at=now(),
    )
    state.exclusions[exclusion_id] = exclusion
    return exclusion


@app.delete(
    "/api/v1/weeks/{week_start}/shift-exclusions/{exclusion_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    tags=["Exclusions"],
)
def delete_shift_exclusion(
    week_start: str,
    exclusion_id: str,
    user: Annotated[DevUser, Depends(current_user)],
    x_allow_past_deadline: Annotated[bool, Header()] = False,
) -> Response:
    state = get_state(week_start)
    exclusion = state.exclusions.get(exclusion_id)
    if exclusion is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "exclusion_not_found", "message": "Exclusion was not found"},
        )
    if not can_manage_worker(user, exclusion.worker_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "worker_forbidden", "message": "Cannot update another worker"},
        )
    if now() > exclusion_cutoff(state.week_start) and not x_allow_past_deadline:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "exclusion_cutoff_passed", "message": "Exclusion cutoff has passed"},
        )
    del state.exclusions[exclusion_id]
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/api/v1/weeks/{week_start}/roster", response_model=DutyRoster, tags=["Roster"])
def get_duty_roster(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
) -> DutyRoster:
    _ = user
    return get_state(week_start).roster


@app.post(
    "/api/v1/weeks/{week_start}/roster/generate",
    response_model=DutyRoster,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["Roster"],
)
def generate_duty_roster_endpoint(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
    request: GenerateRosterRequest | None = None,
) -> DutyRoster:
    require_manager(user)
    state = get_state(week_start)
    if state.schedule.status != "available":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "schedule_not_available", "message": "Schedule is not available yet"},
        )
    if state.roster.status in {"ready_for_review", "authorized"} and not (request and request.force):
        return state.roster

    state.roster = generate_duty_roster(
        week_start=week_start,
        state=state,
        user=user,
        request=request,
    )
    return state.roster


@app.post("/api/v1/weeks/{week_start}/roster/authorize", response_model=DutyRoster, tags=["Roster"])
def authorize_duty_roster(
    week_start: str,
    request: AuthorizeRosterRequest,
    user: Annotated[DevUser, Depends(current_user)],
) -> DutyRoster:
    _ = request
    require_manager(user)
    state = get_state(week_start)
    if state.roster.status != "ready_for_review":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "roster_not_ready", "message": "Roster is not ready for review"},
        )
    state.roster.status = "authorized"
    state.roster.authorized_at = now()
    state.roster.authorized_by = user.id
    return state.roster


@app.get("/api/v1/weeks/{week_start}/alerts", tags=["Alerts"])
def list_alerts(
    week_start: str,
    user: Annotated[DevUser, Depends(current_user)],
    status_filter: Literal["open", "acknowledged", "resolved"] | None = Query(default=None, alias="status"),
) -> dict[str, list[Alert]]:
    require_manager(user)
    alerts = list(get_state(week_start).alerts.values())
    if status_filter is not None:
        alerts = [alert for alert in alerts if alert.status == status_filter]
    return {"alerts": alerts}


@app.post("/api/v1/weeks/{week_start}/alerts/{alert_id}/acknowledge", response_model=Alert, tags=["Alerts"])
def acknowledge_alert(
    week_start: str,
    alert_id: str,
    user: Annotated[DevUser, Depends(current_user)],
) -> Alert:
    require_manager(user)
    state = get_state(week_start)
    alert = state.alerts.get(alert_id)
    if alert is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "alert_not_found", "message": "Alert was not found"},
        )
    alert.status = "acknowledged"
    alert.acknowledged_at = now()
    alert.acknowledged_by = user.id
    return alert


@app.get("/{full_path:path}", include_in_schema=False)
def serve_frontend(full_path: str) -> FileResponse:
    if full_path.startswith("api/"):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "not_found", "message": "Resource was not found"},
        )

    index_path = FRONTEND_BUILD_DIR / "index.html"
    if not index_path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "frontend_not_built",
                "message": "Build the Flutter frontend before serving it from FastAPI.",
            },
        )

    build_dir = FRONTEND_BUILD_DIR.resolve()
    requested_path = (build_dir / full_path).resolve()
    if requested_path.is_relative_to(build_dir) and requested_path.is_file():
        return FileResponse(requested_path)

    return FileResponse(index_path)
