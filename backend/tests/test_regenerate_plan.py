"""Tests for injury regeneration and the restore path of /regenerate-plan.

The endpoint tests run against a small in-memory stand-in for Firestore, so
they check exactly which day documents get rewritten.
"""
import asyncio
import importlib
import random
import sys
import types

import pytest

from services.plan_generator import (
    INJURY_REST_FOCUS,
    SPLIT_MUSCLES,
    _target_group,
    regenerate_days,
    select_days_to_regenerate,
)
from data.exercises import EXERCISES

_BY_NAME = {ex["name"]: ex for ex in EXERCISES}
ALL_GROUPS = ["chest", "back", "shoulders", "arms", "legs", "glutes", "abs"]
PROFILE = dict(
    goal="muscleGain",
    experience="intermediate",
    equipment=["fullGym"],
    session_duration="sixtyMin",
    focus_areas=[],
)


def _groups(day):
    return {_target_group(_BY_NAME[e["exerciseName"]]) for e in day["exercises"]}


def _day(day_id, number, name, day_type, workout_name, focus, **extra):
    return {
        "dayPlanId": day_id,
        "dayNumber": number,
        "dayName": name,
        "dayType": day_type,
        "workoutName": workout_name,
        "focusDescription": focus,
        "durationMinutes": 0 if day_type == "rest" else 50,
        **extra,
    }


def _week():
    """A Push/Pull/Legs week where Pull was rested and Legs adjusted for
    injuries, Tuesday is an injury rest day that's already been logged, and
    Sunday is an ordinary rest day."""
    return [
        _day("mon", 1, "Monday", "workout", "Push", "Chest, Shoulders, Triceps"),
        _day("tue", 2, "Tuesday", "rest", "Rest Day", INJURY_REST_FOCUS,
             originalWorkoutName="Full Body"),
        _day("wed", 3, "Wednesday", "rest", "Rest Day", INJURY_REST_FOCUS,
             originalWorkoutName="Pull"),
        _day("fri", 5, "Friday", "workout", "Legs (Adjusted)", "Chest, Back (Adjusted)",
             originalWorkoutName="Legs"),
        _day("sun", 7, "Sunday", "rest", "Rest Day", "Recovery"),
    ]


# --- regenerate_days ------------------------------------------------------

def test_injury_rest_day_keeps_its_original_split():
    random.seed(7)
    [day] = regenerate_days(
        day_specs=[{"dayPlanId": "a", "dayNumber": 1, "dayName": "Monday",
                    "workoutName": "Push"}],
        excluded_muscle_groups=ALL_GROUPS,
        **PROFILE,
    )
    assert day["dayType"] == "rest"
    assert day["focusDescription"] == INJURY_REST_FOCUS
    assert day["originalWorkoutName"] == "Push"


def test_adjusted_day_keeps_its_original_split():
    random.seed(7)
    [day] = regenerate_days(
        day_specs=[{"dayPlanId": "a", "dayNumber": 3, "dayName": "Wednesday",
                    "workoutName": "Pull (Adjusted)"}],
        excluded_muscle_groups=["back", "arms"],
        **PROFILE,
    )
    assert day["workoutName"] == "Pull (Adjusted)"
    assert day["originalWorkoutName"] == "Pull"


def test_unadjusted_day_has_no_original_split():
    random.seed(7)
    [day] = regenerate_days(
        day_specs=[{"dayPlanId": "a", "dayNumber": 1, "dayName": "Monday",
                    "workoutName": "Push"}],
        excluded_muscle_groups=["legs"],
        **PROFILE,
    )
    assert day["workoutName"] == "Push"
    assert "originalWorkoutName" not in day


# --- select_days_to_regenerate -------------------------------------------

def test_restore_selects_only_injury_adjusted_days():
    specs = select_days_to_regenerate(_week(), logged_days={2}, restore_only=True)
    assert [(s["dayPlanId"], s["workoutName"]) for s in specs] == [
        ("wed", "Pull"),             # rest day -> its saved split
        ("fri", "Legs (Adjusted)"),  # regenerate_days strips the suffix
    ]


def test_injuries_still_active_also_retry_injury_rest_days():
    # One injury recovered, another is still active: the rested Pull day is
    # retried (it may be trainable again); ordinary rest days are not.
    specs = select_days_to_regenerate(_week(), logged_days=set(), restore_only=False)
    assert [s["dayPlanId"] for s in specs] == ["mon", "tue", "wed", "fri"]


def test_legacy_injury_rest_day_infers_its_split():
    # Saved before originalWorkoutName existed: Mon/Wed/Fri trained = PPL, so
    # Wednesday (second training day) was Pull.
    week = [
        _day("mon", 1, "Monday", "workout", "Push", "Chest"),
        _day("wed", 3, "Wednesday", "rest", "Rest Day", INJURY_REST_FOCUS),
        _day("fri", 5, "Friday", "workout", "Legs", "Legs"),
        _day("sun", 7, "Sunday", "rest", "Rest Day", "Recovery"),
    ]
    [spec] = select_days_to_regenerate(week, logged_days=set(), restore_only=True)
    assert spec["workoutName"] == "Pull"


# --- /regenerate-plan endpoint -------------------------------------------

class _Snap:
    def __init__(self, ref, data):
        self.reference = ref
        self.id = ref.path[-1]
        self._data = data

    def to_dict(self):
        return dict(self._data)


class _Ref:
    """Document or collection reference: just a path into the store."""

    def __init__(self, db, path):
        self._db = db
        self.path = path

    def collection(self, name):
        return _Ref(self._db, self.path + (name,))

    def document(self, doc_id):
        return _Ref(self._db, self.path + (doc_id,))

    def get(self):  # collection read: direct children only
        depth = len(self.path) + 1
        return [
            _Snap(_Ref(self._db, p), data)
            for p, data in sorted(self._db.store.items())
            if len(p) == depth and p[:-1] == self.path
        ]


class _Batch:
    def __init__(self, db):
        self._db = db
        self._ops = []

    def set(self, ref, data):
        self._ops.append((ref.path, dict(data)))

    def delete(self, ref):
        self._ops.append((ref.path, None))

    def commit(self):
        for path, data in self._ops:
            self._db.written.add(path)
            if data is None:
                self._db.store.pop(path, None)
            else:
                self._db.store[path] = data


class _FakeDb:
    def __init__(self):
        self.store = {}
        self.written = set()

    def collection(self, name):
        return _Ref(self, (name,))

    def batch(self):
        return _Batch(self)


DAYS = ("users", "u1", "workoutPlans", "p1", "days")


@pytest.fixture
def plan_router(monkeypatch):
    """routers.plan_router imported against the fake db instead of the real
    Firebase project (firebase_config connects on import)."""
    db = _FakeDb()
    fake_config = types.ModuleType("firebase_config")
    fake_config.db = db
    monkeypatch.setitem(sys.modules, "firebase_config", fake_config)
    sys.modules.pop("routers.plan_router", None)
    module = importlib.import_module("routers.plan_router")
    yield module, db
    sys.modules.pop("routers.plan_router", None)


def _seed(db, days):
    for day in days:
        db.store[DAYS + (day["dayPlanId"],)] = {
            k: v for k, v in day.items() if k != "exercises"
        }
        db.store[DAYS + (day["dayPlanId"], "exercises", "old")] = {"exerciseName": "Old"}


def _call(module, monkeypatch, excluded, logged_days):
    monkeypatch.setattr(
        module, "get_logged_day_numbers_this_week",
        lambda db, uid, client_date=None: set(logged_days),
    )
    request = module.RegeneratePlanRequest(
        uid="u1", plan_id="p1", excluded_muscle_groups=excluded, **PROFILE,
    )
    return asyncio.run(module.regenerate_plan_endpoint(request))


def _exercises(db, day_id):
    prefix = DAYS + (day_id, "exercises")
    return [d for p, d in db.store.items() if p[:-1] == prefix]


def test_restore_with_no_exclusions_rebuilds_injury_rest_day(plan_router, monkeypatch):
    module, db = plan_router
    _seed(db, _week())
    random.seed(11)

    result = _call(module, monkeypatch, excluded=[], logged_days={2})

    assert result["updatedCount"] == 2
    wed = db.store[DAYS + ("wed",)]
    assert wed["dayType"] == "workout"
    assert wed["workoutName"] == "Pull"
    assert "originalWorkoutName" not in wed
    wed_exercises = _exercises(db, "wed")
    assert wed_exercises and all(
        _target_group(_BY_NAME[e["exerciseName"]]) in SPLIT_MUSCLES["Pull"]
        for e in wed_exercises
    )
    fri = db.store[DAYS + ("fri",)]
    assert fri["workoutName"] == "Legs"
    assert "originalWorkoutName" not in fri


def test_restore_leaves_unaffected_days_untouched(plan_router, monkeypatch):
    module, db = plan_router
    week = _week()
    _seed(db, week)
    before = dict(db.store)

    _call(module, monkeypatch, excluded=[], logged_days={2})

    rewritten_days = {p[5] for p in db.written}
    assert rewritten_days == {"wed", "fri"}
    # Monday's (adapted) workout, the logged Tuesday and the plain rest day
    # keep their documents and exercises exactly as they were.
    for day_id in ("mon", "tue", "sun"):
        assert db.store[DAYS + (day_id,)] == before[DAYS + (day_id,)]
        assert _exercises(db, day_id) == [{"exerciseName": "Old"}]


def test_restore_with_nothing_adjusted_writes_nothing(plan_router, monkeypatch):
    module, db = plan_router
    _seed(db, [
        _day("mon", 1, "Monday", "workout", "Push", "Chest"),
        _day("sun", 7, "Sunday", "rest", "Rest Day", "Recovery"),
    ])

    result = _call(module, monkeypatch, excluded=[], logged_days=set())

    assert result["updatedCount"] == 0
    assert db.written == set()


def test_injury_rest_day_is_saved_with_its_original_split(plan_router, monkeypatch):
    module, db = plan_router
    _seed(db, [_day("mon", 1, "Monday", "workout", "Push", "Chest")])

    _call(module, monkeypatch, excluded=ALL_GROUPS, logged_days=set())

    mon = db.store[DAYS + ("mon",)]
    assert mon["workoutName"] == "Rest Day"
    assert mon["focusDescription"] == INJURY_REST_FOCUS
    assert mon["originalWorkoutName"] == "Push"
    assert _exercises(db, "mon") == []
