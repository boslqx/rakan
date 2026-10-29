"""ID-token check on every endpoint (D-15 / P0-1, V-07).

Runs the real app through TestClient with verify_token mocked, against a
stand-in for firebase_config so no Firebase project is touched.
"""
import importlib
import sys
import types
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

import auth

GOOD_TOKEN = "good-token"
TOKEN_UID = "user-a"
HEADERS = {"Authorization": f"Bearer {GOOD_TOKEN}"}

PROFILE = dict(
    goal="muscleGain",
    experience="beginner",
    equipment=["noEquipment"],
    session_duration="sixtyMin",
    focus_areas=[],
)
BODIES = {
    "/generate-plan": {**PROFILE, "workout_days": [1, 3, 5]},
    "/regenerate-plan": {**PROFILE, "plan_id": "p1", "excluded_muscle_groups": []},
    "/adapt-plan": {
        "avg_rpe": 6, "max_rpe": 7, "session_duration": 45,
        "exercises_count": 4, "completion_rate": 1, "experience_level": 0,
    },
    "/commit-adaptations": {"current_volume": 1000, "past_volumes": [], "proposals": []},
}


def _fake_verify(token):
    if token != GOOD_TOKEN:
        raise ValueError("bad token")
    return {"uid": TOKEN_UID}


@pytest.fixture
def app_modules(monkeypatch):
    """main.app imported against a mock db, with verify_token mocked."""
    fake_config = types.ModuleType("firebase_config")
    fake_config.db = MagicMock()
    monkeypatch.setitem(sys.modules, "firebase_config", fake_config)
    monkeypatch.setattr(auth, "verify_token", _fake_verify)
    names = ("main", "routers.plan_router", "routers.adapt_router",
             "routers.adaptation_engine_router")
    for name in names:
        sys.modules.pop(name, None)
    main = importlib.import_module("main")
    yield main, sys.modules["routers.plan_router"]
    for name in names:
        sys.modules.pop(name, None)


@pytest.fixture
def client(app_modules):
    return TestClient(app_modules[0].app)


@pytest.mark.parametrize("path", list(BODIES))
def test_missing_token_is_401(client, path):
    assert client.post(path, json=BODIES[path]).status_code == 401


@pytest.mark.parametrize("path", list(BODIES))
def test_invalid_token_is_401(client, path):
    response = client.post(
        path, json=BODIES[path], headers={"Authorization": "Bearer forged"})
    assert response.status_code == 401


@pytest.mark.parametrize("header", ["good-token", "Basic good-token", "Bearer "])
def test_malformed_header_is_401(client, header):
    response = client.post(
        "/adapt-plan", json=BODIES["/adapt-plan"], headers={"Authorization": header})
    assert response.status_code == 401


@pytest.mark.parametrize("path", ["/generate-plan", "/regenerate-plan"])
def test_token_for_another_uid_is_403(client, path):
    # ST-14: user A's token with user B's uid in the body.
    body = {**BODIES[path], "uid": "user-b"}
    assert client.post(path, json=body, headers=HEADERS).status_code == 403


def test_valid_token_uses_the_token_uid(app_modules, monkeypatch):
    main, plan_router = app_modules
    seen = {}

    def logged_days(db, uid, client_date=None):
        seen["uid"] = uid
        return set()

    monkeypatch.setattr(plan_router, "get_logged_day_numbers_this_week", logged_days)
    client = TestClient(main.app)

    # Matching body uid (older app builds) and no body uid are both fine.
    for body in (BODIES["/regenerate-plan"],
                 {**BODIES["/regenerate-plan"], "uid": TOKEN_UID}):
        response = client.post("/regenerate-plan", json=body, headers=HEADERS)
        assert response.status_code == 200
        assert response.json()["updatedCount"] == 0
    assert seen["uid"] == TOKEN_UID


@pytest.mark.parametrize("path", ["/adapt-plan", "/commit-adaptations"])
def test_valid_token_reaches_adaptation_endpoints(client, path):
    assert client.post(path, json=BODIES[path], headers=HEADERS).status_code == 200


def test_root_needs_no_token(client):
    assert client.get("/").status_code == 200
