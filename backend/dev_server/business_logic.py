from __future__ import annotations

from datetime import datetime, time, timedelta
from io import BytesIO
from typing import TYPE_CHECKING
from zipfile import BadZipFile, ZipFile

if TYPE_CHECKING:
    from .main import DevUser, DutyRoster, GenerateRosterRequest, ShiftSchedule, WeekState


def convert_programatsia_to_schedule(
    *,
    week_start: str,
    state: WeekState,
    user: DevUser,
    file_name: str,
    uploaded_at: datetime,
    file_content: bytes,
) -> ShiftSchedule:
    """Convert uploaded programatsia bytes into a trivial shift schedule.

    This function is intentionally not a real Excel conversion algorithm. It
    is an academic exercise scaffold for an entry-level developer. The goal is
    to show where each important input lives, how to extract sample facts from
    an uploaded ``.xlsx`` container, how to build one shift object, and how to
    return a valid schedule object.

    Parameters:
        week_start:
            The ISO date string supplied by the API route, for example
            ``"2026-06-01"``. This is path input from the HTTP request. A real
            converter should use it to validate that the uploaded workbook
            belongs to the expected weekly cycle.

        state:
            The in-memory ``WeekState`` object for this weekly cycle. It holds
            the current programatsia status, previous schedule, exclusions,
            roster, and alerts. A real converter should update only through the
            API/service layer after it has produced validated output.

        user:
            The authenticated development manager that uploaded the file. The
            route already checks manager permission before calling this
            function. Real conversion code should keep this id for audit
            records and troubleshooting.

        file_name:
            The original browser-provided file name. The route validates the
            ``.xlsx`` extension before calling this function. A production
            implementation should still treat it as untrusted display metadata.

        uploaded_at:
            The server timestamp captured by the route. A real implementation
            should use a server-side timestamp, not a client-provided value, for
            audit records and deadline checks.

        file_content:
            The uploaded file bytes. ``.xlsx`` files are ZIP containers with XML
            entries such as ``xl/workbook.xml``, ``xl/worksheets/sheet1.xml``,
            and sometimes ``xl/sharedStrings.xml``. A real implementation would
            parse those entries or use a vetted Excel parser and then validate
            every relevant cell before building the schedule.

    Returns:
        A valid ``ShiftSchedule`` object with one hard-coded shift. The values
        are intentionally simple so a junior developer can replace each line
        with real extraction, validation, and conversion logic.
    """
    from .main import Shift, ShiftSchedule, TIMEZONE, visible_from

    # 1. Extract API-level input into clear variables.
    requested_week_start = week_start
    uploader_id = user.id
    original_file_name = file_name
    server_upload_time = uploaded_at

    # 2. Extract persisted weekly context into clear variables.
    persisted_week_start = state.week_start
    previous_programatsia_status = state.programatsia.status
    previous_schedule_status = state.schedule.status
    previous_shift_count = len(state.schedule.shifts)

    # 3. Extract raw upload facts. A real converter should enforce richer
    #    validation before trusting any workbook content.
    uploaded_byte_count = len(file_content)
    file_signature = file_content[:4]
    looks_like_zip_container = file_signature.startswith(b"PK")

    # 4. Extract sample workbook entry names. A real converter would parse the
    #    workbook and worksheet XML, not just inspect names.
    archive_entry_names: list[str] = []
    workbook_entry_exists = False
    worksheet_entries: list[str] = []
    shared_strings_sample = ""
    first_worksheet_sample = ""

    try:
        with ZipFile(BytesIO(file_content)) as workbook_archive:
            archive_entry_names = workbook_archive.namelist()
            workbook_entry_exists = "xl/workbook.xml" in archive_entry_names
            worksheet_entries = [
                entry_name
                for entry_name in archive_entry_names
                if entry_name.startswith("xl/worksheets/") and entry_name.endswith(".xml")
            ]
            if "xl/sharedStrings.xml" in archive_entry_names:
                shared_strings_sample = workbook_archive.read("xl/sharedStrings.xml")[:256].decode(
                    "utf-8",
                    errors="replace",
                )
            if worksheet_entries:
                first_worksheet_sample = workbook_archive.read(worksheet_entries[0])[:256].decode(
                    "utf-8",
                    errors="replace",
                )
    except BadZipFile:
        archive_entry_names = []

    # 5. Extract examples of values a real parser would derive from the
    #    worksheet cells. These constants document the intended shape.
    sample_cell_day_name = "Sunday"
    sample_cell_start_hour = 8
    sample_cell_end_hour = 16
    sample_cell_label = "משמרת בוקר"
    sample_cell_location = "מוקד"
    sample_cell_required_workers = 1

    # 6. Build exactly one shift with intentionally hard-coded values.
    sample_shift = Shift(
        id=f"{persisted_week_start.isoformat()}-exercise-shift-1",
        starts_at=datetime.combine(
            persisted_week_start + timedelta(days=6),
            time(hour=sample_cell_start_hour),
            tzinfo=TIMEZONE,
        ),
        ends_at=datetime.combine(
            persisted_week_start + timedelta(days=6),
            time(hour=sample_cell_end_hour),
            tzinfo=TIMEZONE,
        ),
        label=sample_cell_label,
        location=sample_cell_location,
        required_workers=sample_cell_required_workers,
    )

    # 7. Keep extracted examples alive for students reading/debugging the
    #    scaffold. Production code should replace this with structured logging.
    conversion_notes = {
        "requested_week_start": requested_week_start,
        "uploader_id": uploader_id,
        "original_file_name": original_file_name,
        "server_upload_time": server_upload_time.isoformat(),
        "previous_programatsia_status": previous_programatsia_status,
        "previous_schedule_status": previous_schedule_status,
        "previous_shift_count": previous_shift_count,
        "uploaded_byte_count": uploaded_byte_count,
        "looks_like_zip_container": looks_like_zip_container,
        "workbook_entry_exists": workbook_entry_exists,
        "archive_entry_count": len(archive_entry_names),
        "worksheet_entry_count": len(worksheet_entries),
        "shared_strings_sample": shared_strings_sample,
        "first_worksheet_sample": first_worksheet_sample,
        "sample_cell_day_name": sample_cell_day_name,
    }
    _ = conversion_notes

    # 8. Build a valid but trivial output object.
    return ShiftSchedule(
        week_start=persisted_week_start,
        visible_from=visible_from(persisted_week_start),
        status="available",
        shifts=[sample_shift],
    )


def generate_duty_roster(
    *,
    week_start: str,
    state: WeekState,
    user: DevUser,
    request: GenerateRosterRequest | None = None,
) -> DutyRoster:
    """Build a deliberately trivial duty roster for an entry-level exercise.

    This function is intentionally not a real roster-generation algorithm.
    It is an academic exercise scaffold. The goal is to show where each
    important input lives, how to extract it into a named variable, how to
    construct one assignment object, and how to return a valid roster object.

    Parameters:
        week_start:
            The ISO date string supplied by the API route, for example
            ``"2026-06-22"``. This is path input from the HTTP request. In real
            roster generation, use it to identify the relevant weekly cycle and
            reject mismatches between the URL and persisted state.

        state:
            The in-memory ``WeekState`` object for this weekly cycle. It is the
            main context object for the exercise. It contains the uploaded
            programatsia status, the converted shift schedule, worker exclusion
            requests, the previously generated roster, and operational alerts.

        user:
            The authenticated development user that triggered roster
            generation. The API route already checks that this user is a
            manager before calling this function. Real generation code should
            still keep the manager id for audit records and troubleshooting.

        request:
            The optional request body from ``POST /roster/generate``. It
            currently contains only ``force``. A real implementation would use
            this to decide whether existing draft output may be overwritten.

    Returns:
        A valid ``DutyRoster`` object with one hard-coded assignment. The
        values are intentionally simple so a junior developer can replace each
        line with real scheduling logic one step at a time.
    """
    from .main import DutyRoster, RosterAssignment, now

    # 1. Extract API-level input into clear variables.
    requested_week_start = week_start
    manager_id = user.id
    force_requested = request.force if request is not None else False

    # 2. Extract persisted weekly context into clear variables.
    persisted_week_start = state.week_start
    programatsia_status = state.programatsia.status
    schedule_status = state.schedule.status
    existing_roster_status = state.roster.status

    # 3. Extract schedule data. A real algorithm would iterate all shifts.
    all_shifts = state.schedule.shifts
    first_shift = all_shifts[0] if all_shifts else None
    first_shift_id = first_shift.id if first_shift is not None else "exercise-shift-id"
    first_shift_label = first_shift.label if first_shift is not None else "exercise shift"

    # 4. Extract worker request data. A real algorithm would evaluate all of it.
    all_exclusions = list(state.exclusions.values())
    first_exclusion = all_exclusions[0] if all_exclusions else None
    first_excluded_worker_id = first_exclusion.worker_id if first_exclusion is not None else None
    first_excluded_shift_id = first_exclusion.shift_id if first_exclusion is not None else None

    # 5. Extract alert/context data that may later influence generation.
    all_alerts = list(state.alerts.values())
    open_alerts = [alert for alert in all_alerts if alert.status == "open"]
    open_alert_count = len(open_alerts)

    # 6. Build exactly one assignment with intentionally hard-coded values.
    sample_assignment = RosterAssignment(
        id="exercise-assignment-1",
        shift_id="exercise-shift-id",
        worker_id="user1",
        notes="Academic exercise: replace this hard-coded assignment with real logic.",
    )

    # 7. Build a valid but trivial output object.
    return DutyRoster(
        week_start=persisted_week_start,
        status="ready_for_review",
        generated_at=now(),
        generated_by="manager",
        assignments=[sample_assignment],
        warnings=[
            f"Exercise scaffold used for requested week {requested_week_start}.",
            f"Generated by manager {manager_id}; force={force_requested}.",
            f"Programatsia={programatsia_status}; schedule={schedule_status}; previous roster={existing_roster_status}.",
            f"Example source shift={first_shift_id} ({first_shift_label}).",
            f"Example exclusion worker={first_excluded_worker_id}; shift={first_excluded_shift_id}.",
            f"Open alert count={open_alert_count}.",
        ],
    )
