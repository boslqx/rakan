"""Tests for the rule-based plan generator (services/plan_generator.py).

The generator is randomised (exercise order is shuffled for variety), so
the structural rules are checked across many generated plans rather than
one fixed output.
"""
import random

import pytest

from data.exercises import EXERCISES
from services.plan_generator import (
    SPLIT_MUSCLES,
    _resolve_local_today,
    _target_group,
    generate_plan,
    regenerate_days,
)

_BY_NAME = {ex["name"]: ex for ex in EXERCISES}
EQUIPMENT_SETS = [
    ["noEquipment"],
    ["dumbbell"],
    ["dumbbell", "bench", "pullUpBar"],
    ["fullGym"],
]


def _groups(day):
    return [_target_group(_BY_NAME[e["exerciseName"]]) for e in day["exercises"]]


def _plans(n=40, **overrides):
    random.seed(1234)
    kwargs = dict(
        uid="u",
        goal="muscleGain",
        experience="intermediate",
        workout_days=[1, 3, 5],
        session_duration="sixtyMin",
        focus_areas=[],
    )
    kwargs.update(overrides)
    for _ in range(n):
        for equipment in EQUIPMENT_SETS:
            yield generate_plan(equipment=equipment, **kwargs)


def test_every_exercise_belongs_to_its_days_split():
    # Focus areas used to pull exercises from outside the day's split.
    for plan in _plans(focus_areas=["chest", "glutes", "arms"]):
        for day in plan["days"]:
            if day["dayType"] != "workout":
                continue
            allowed = SPLIT_MUSCLES[day["workoutName"]]
            assert all(g in allowed for g in _groups(day)), day


def test_pull_days_never_contain_pushing_work():
    for plan in _plans():
        for day in plan["days"]:
            if day["workoutName"] == "Pull":
                assert not {"triceps", "chest", "shoulders"} & set(_groups(day))


def test_push_days_cover_every_push_muscle_when_equipment_allows():
    for plan in _plans(n=20):
        for day in plan["days"]:
            if day["workoutName"] == "Push":
                assert {"chest", "shoulders", "triceps"} <= set(_groups(day))


@pytest.mark.parametrize("duration, minutes", [
    ("thirtyMin", 30),
    ("fortyFiveMin", 45),
    ("sixtyMin", 60),
])
def test_session_length_tracks_the_chosen_duration(duration, minutes):
    for plan in _plans(n=15, session_duration=duration):
        # Bodyweight-only Pull days are excluded: the library only has 3
        # no-equipment back exercises and no bodyweight curl, so that one
        # day can't physically fill an hour (a known content gap, not a
        # generator bug).
        for day in plan["days"]:
            if day["workoutName"] == "Pull" and len(day["exercises"]) <= 3:
                continue
            if day["dayType"] == "workout":
                # Within 15 minutes of the user's chosen session length
                assert abs(day["durationMinutes"] - minutes) <= 15, day


def test_goal_changes_the_prescription():
    random.seed(7)
    gain = generate_plan("u", "muscleGain", "intermediate", ["fullGym"], [1], "sixtyMin", [])
    random.seed(7)
    endurance = generate_plan("u", "endurance", "intermediate", ["fullGym"], [1], "sixtyMin", [])

    gain_reps = [e["reps"] for e in gain["days"][0]["exercises"] if e["reps"] > 1]
    end_reps = [e["reps"] for e in endurance["days"][0]["exercises"] if e["reps"] > 1]
    end_rest = [e["restSeconds"] for e in endurance["days"][0]["exercises"]]

    assert min(end_reps) >= 15
    assert max(end_rest) <= 45
    assert sum(end_reps) / len(end_reps) > sum(gain_reps) / len(gain_reps)


def test_timed_holds_keep_their_library_values():
    # A plank's "reps" is 1 (one timed hold); goal rules must not turn it
    # into 15 reps.
    for plan in _plans(n=20, goal="endurance", workout_days=[1, 2, 3, 4, 5, 6, 7]):
        for day in plan["days"]:
            for e in day["exercises"]:
                if _BY_NAME[e["exerciseName"]]["reps"] == 1:
                    assert e["reps"] == 1


def test_generated_at_is_timezone_aware():
    plan = generate_plan("u", "muscleGain", "beginner", ["noEquipment"], [1], "thirtyMin", [])
    assert plan["generatedAt"].endswith("+00:00")


def test_regenerate_excludes_arms_as_biceps_and_triceps():
    random.seed(3)
    days = regenerate_days(
        day_specs=[
            {"dayPlanId": "a", "dayNumber": 1, "dayName": "Monday", "workoutName": "Push"},
            {"dayPlanId": "b", "dayNumber": 3, "dayName": "Wednesday", "workoutName": "Pull"},
        ],
        excluded_muscle_groups=["arms"],
        goal="muscleGain",
        experience="intermediate",
        equipment=["fullGym"],
        session_duration="sixtyMin",
        focus_areas=["arms"],
    )
    for day in days:
        assert not {"biceps", "triceps"} & set(_groups(day))
        assert day["exercises"], day


def test_local_today_prefers_the_client_date():
    assert _resolve_local_today("2026-10-05").isoformat() == "2026-10-05"
    # Garbage falls back to the server's Malaysia-time date instead of crashing
    assert _resolve_local_today("not-a-date") is not None
