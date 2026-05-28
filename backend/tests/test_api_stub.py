from __future__ import annotations

import base64

from fastapi.testclient import TestClient
import pytest

from dev_server.main import FRONTEND_BUILD_DIR
from dev_server.main import app


client = TestClient(app)


def auth(username: str, password: str) -> dict[str, str]:
    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    return {"Authorization": f"Basic {token}"}


def upload_week(week_start: str) -> None:
    response = client.post(
        f"/api/v1/weeks/{week_start}/programatsia",
        headers=auth("manager", "manager"),
        files={"file": ("programatsia.xlsx", b"stub", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
    )
    assert response.status_code == 202


def test_health_is_public() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_frontend_static_site_is_served_when_built() -> None:
    if not (FRONTEND_BUILD_DIR / "index.html").is_file():
        pytest.skip("Flutter frontend has not been built")

    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


def test_dummy_manager_can_authenticate() -> None:
    response = client.get("/api/v1/session", headers=auth("manager", "manager"))
    assert response.status_code == 200
    body = response.json()
    assert body["user"]["id"] == "manager"
    assert body["user"]["role"] == "manager"


def test_invalid_credentials_are_rejected() -> None:
    response = client.get("/api/v1/session", headers=auth("manager", "wrong"))
    assert response.status_code == 401


def test_worker_cannot_upload_programatsia() -> None:
    response = client.post(
        "/api/v1/weeks/2026-06-01/programatsia",
        headers=auth("user1", "user1"),
        files={"file": ("programatsia.xlsx", b"stub", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
    )
    assert response.status_code == 403


def test_manager_upload_exposes_schedule() -> None:
    upload_week("2026-06-01")

    schedule = client.get("/api/v1/weeks/2026-06-01/schedule", headers=auth("user1", "user1"))
    assert schedule.status_code == 200
    assert len(schedule.json()["shifts"]) >= 1


def test_worker_can_create_own_exclusion() -> None:
    upload_week("2026-06-08")
    schedule = client.get("/api/v1/weeks/2026-06-08/schedule", headers=auth("user1", "user1"))
    shift_id = schedule.json()["shifts"][0]["id"]

    response = client.post(
        "/api/v1/weeks/2026-06-08/shift-exclusions",
        headers={**auth("user1", "user1"), "X-Allow-Past-Deadline": "true"},
        json={"shift_id": shift_id, "worker_id": "user1", "reason": "לא זמין"},
    )
    assert response.status_code == 201
    assert response.json()["worker_id"] == "user1"


def test_worker_cannot_create_exclusion_for_other_worker() -> None:
    upload_week("2026-06-15")
    schedule = client.get("/api/v1/weeks/2026-06-15/schedule", headers=auth("user1", "user1"))
    shift_id = schedule.json()["shifts"][0]["id"]

    response = client.post(
        "/api/v1/weeks/2026-06-15/shift-exclusions",
        headers={**auth("user1", "user1"), "X-Allow-Past-Deadline": "true"},
        json={"shift_id": shift_id, "worker_id": "user2"},
    )
    assert response.status_code == 403


def test_manager_can_generate_and_authorize_roster() -> None:
    upload_week("2026-06-22")
    generated = client.post(
        "/api/v1/weeks/2026-06-22/roster/generate",
        headers=auth("manager", "manager"),
        json={"force": True},
    )
    assert generated.status_code == 202
    assert generated.json()["status"] == "ready_for_review"
    assert generated.json()["assignments"] == [
        {
            "id": "exercise-assignment-1",
            "shift_id": "exercise-shift-id",
            "worker_id": "user1",
            "notes": "Academic exercise: replace this hard-coded assignment with real logic.",
        }
    ]

    authorized = client.post(
        "/api/v1/weeks/2026-06-22/roster/authorize",
        headers=auth("manager", "manager"),
        json={"approved": True},
    )
    assert authorized.status_code == 200
    assert authorized.json()["status"] == "authorized"
