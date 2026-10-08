import random
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from data.exercises import get_exercises_for_equipment, filter_by_difficulty

# Exercise-count bounds per session, by experience. The actual count is
# chosen to fill the user's selected session length (see
# _fill_to_duration) — these only stop a beginner getting 9 exercises or an
# advanced lifter getting 2.
EXERCISE_COUNT_BOUNDS = {
    "beginner": (3, 6),
    "intermediate": (3, 7),
    "advanced": (3, 8),
}

# The user's selected session length (onboarding SessionDuration enum),
# in minutes. ~10 of those minutes are reserved for warm-up + cool-down;
# the rest is filled with working sets.
SESSION_MINUTES = {
    "thirtyMin": 30,
    "fortyFiveMin": 45,
    "sixtyMin": 60,
    "ninetyPlusMin": 90,
}
WARMUP_COOLDOWN_MINUTES = 10
SECONDS_PER_WORKING_SET = 45  # time under load + setup, per set
MAX_SETS_PER_EXERCISE = 5

# Muscle priority order per goal. Used to order the day's target muscles
# (higher priority muscles get the first exercise slots) and for the
# injury-fallback muscle choice.
GOAL_MUSCLE_PRIORITY = {
    "muscleGain":   ["chest", "back", "legs", "shoulders", "biceps", "triceps", "glutes", "abs"],
    "weightLoss":   ["legs", "glutes", "back", "chest", "abs", "shoulders", "biceps", "triceps"],
    "endurance":    ["legs", "abs", "back", "chest", "glutes", "shoulders", "biceps", "triceps"],
    "flexibility":  ["abs", "glutes", "legs", "back", "shoulders", "chest", "biceps", "triceps"],
}

# Goal-based prescription. The exercise library stores muscle-gain style
# defaults (roughly 8-12 reps); other goals shift reps up and rest down,
# following the ACSM resistance-training guidance that muscular endurance
# is trained with higher reps (15-20+) and short rest (30-60 s), and the
# common use of shorter rest intervals for higher energy expenditure in
# weight-loss programmes. `None` means "keep the library default".
#   (min_reps, max_reps, max_rest_seconds, set_delta)
GOAL_PRESCRIPTION = {
    "muscleGain":  None,
    "weightLoss":  (12, 15, 60, 0),
    "endurance":   (15, 20, 45, -1),
    "flexibility": (12, 15, 60, -1),
}

# Day name templates based on number of workout days per week
# Key = number of workout days selected by user
DAY_SPLITS = {
    1: ["Full Body"],
    2: ["Upper Body", "Lower Body"],
    3: ["Push", "Pull", "Legs"],
    4: ["Push", "Pull", "Legs", "Full Body"],
    5: ["Chest & Triceps", "Back & Biceps", "Legs", "Shoulders & Arms", "Full Body"],
    6: ["Chest", "Back", "Legs", "Shoulders", "Arms", "Full Body"],
    7: ["Chest", "Back", "Legs", "Shoulders", "Arms", "Full Body", "Active Recovery"],
}

# Which muscles each split day trains. "arms" is split into "biceps" and
# "triceps" here: they belong to opposite movement patterns (pull vs push),
# and treating them as one group put tricep dips / close-grip presses on
# Pull days — training the same muscles as the Push day before it.
SPLIT_MUSCLES = {
    "Full Body":           ["chest", "back", "legs", "shoulders", "abs", "biceps", "triceps"],
    "Upper Body":          ["chest", "back", "shoulders", "biceps", "triceps"],
    "Lower Body":          ["legs", "glutes", "abs"],
    "Push":                ["chest", "shoulders", "triceps"],
    "Pull":                ["back", "biceps"],
    "Legs":                ["legs", "glutes"],
    "Chest & Triceps":     ["chest", "triceps"],
    "Back & Biceps":       ["back", "biceps"],
    "Shoulders & Arms":    ["shoulders", "biceps", "triceps"],
    "Chest":               ["chest"],
    "Back":                ["back"],
    "Shoulders":           ["shoulders"],
    "Arms":                ["biceps", "triceps"],
    "Active Recovery":     ["abs"],
}

# Keywords that identify a tricep (push) exercise inside the library's
# single "arms" group. Anything else in "arms" is a curl (biceps).
_TRICEP_KEYWORDS = ("tricep", "dip", "skull", "close-grip", "pushdown", "extension")


def _target_group(ex: dict) -> str:
    """The muscle an exercise counts toward for split purposes: the
    library's muscle_group, except "arms" is resolved to biceps/triceps."""
    group = ex["muscle_group"]
    if group != "arms":
        return group
    name = ex["name"].lower()
    return "triceps" if any(k in name for k in _TRICEP_KEYWORDS) else "biceps"


def _expand_groups(groups) -> set[str]:
    """Client-facing vocabulary ("arms") -> split vocabulary (biceps +
    triceps). Used for focus areas and injury exclusions, which the app
    sends in the broad vocabulary."""
    out = set()
    for g in groups:
        if g == "arms":
            out.update({"biceps", "triceps"})
        elif g == "fullBody":
            continue  # a focus of "full body" doesn't favour any one muscle
        else:
            out.add(g)
    return out


# Maps the backend's internal muscle_group vocabulary
MUSCLE_GROUP_MAP = {
    "chest": "Chest",
    "back": "Back",
    "shoulders": "Shoulders",
    "arms": "Arms",
    "legs": "Legs",
    "glutes": "Glutes",
    "abs": "Core",
}


def generate_plan(
    uid: str,
    goal: str,
    experience: str,
    equipment: list[str],
    workout_days: list[int],   # e.g. [1, 3, 5] = Mon, Wed, Fri
    session_duration: str,     # "thirtyMin", "fortyFiveMin", "sixtyMin", "ninetyPlusMin"
    focus_areas: list[str],
) -> dict:

    available = filter_by_difficulty(get_exercises_for_equipment(equipment), experience)
    split_names = DAY_SPLITS.get(len(workout_days), ["Full Body"])

    days = []
    split_index = 0  # cycles through split_names for workout days

    for day_number in range(1, 8):  # days 1 through 7
        day_name = _day_name(day_number)

        if day_number in workout_days:
            split_name = split_names[split_index % len(split_names)]
            split_index += 1
            target_muscles = SPLIT_MUSCLES.get(split_name, ["chest"])

            raw_exercises = _build_session(
                available=available,
                target_muscles=target_muscles,
                goal=goal,
                experience=experience,
                session_duration=session_duration,
                focus_areas=focus_areas,
            )

            days.append({
                "dayPlanId": str(uuid.uuid4()),
                "dayNumber": day_number,
                "dayName": day_name,
                "dayType": "workout",
                "workoutName": split_name,
                "focusDescription": _focus_label(target_muscles),
                "durationMinutes": _session_minutes(raw_exercises),
                "exercises": [_format_exercise(ex) for ex in raw_exercises],
            })
        else:
            days.append({
                "dayPlanId": str(uuid.uuid4()),
                "dayNumber": day_number,
                "dayName": day_name,
                "dayType": "rest",
                "workoutName": "Rest Day",
                "focusDescription": "Recovery",
                "durationMinutes": 0,
                "exercises": [],
            })

    goal_label = {
        "muscleGain": "Muscle Gain",
        "weightLoss": "Weight Loss",
        "endurance": "Endurance",
        "flexibility": "Flexibility",
    }.get(goal, goal)

    return {
        "planId": str(uuid.uuid4()),
        "uid": uid,
        "planName": f"Week 1 — {goal_label}",
        "status": "active",
        # Timezone-aware UTC ("...+00:00") so the app parses it as an
        # absolute instant and converts to local time, instead of reading a
        # bare UTC timestamp as if it were Malaysia local time.
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "weekNumber": 1,
        "days": days,
    }


def regenerate_days(
    day_specs: list[dict],       # [{dayPlanId, dayNumber, dayName, workoutName(splitName)}]
    excluded_muscle_groups: list[str],
    goal: str,
    experience: str,
    equipment: list[str],
    session_duration: str,
    focus_areas: list[str],
) -> list[dict]:

    available = filter_by_difficulty(get_exercises_for_equipment(equipment), experience)
    muscle_priority = GOAL_MUSCLE_PRIORITY.get(goal, GOAL_MUSCLE_PRIORITY["muscleGain"])
    excluded_set = _expand_groups(excluded_muscle_groups)

    updated_days = []

    for spec in day_specs:
        split_name = spec.get("workoutName", "Full Body")
        # A day regenerated before may already carry the " (Adjusted)"
        # suffix — strip it so the original split's muscles are used.
        base_split = split_name.replace(" (Adjusted)", "")
        target_muscles = SPLIT_MUSCLES.get(base_split, ["chest"])

        # Remove injured muscle groups from this day's target focus
        safe_targets = [m for m in target_muscles if m not in excluded_set]

        # Edge case: the day's entire focus was excluded
        used_fallback = False
        if not safe_targets:
            safe_targets = [m for m in muscle_priority if m not in excluded_set][:2]
            used_fallback = True

        raw_exercises = []
        if safe_targets:
            raw_exercises = _build_session(
                available=available,
                target_muscles=safe_targets,
                goal=goal,
                experience=experience,
                session_duration=session_duration,
                focus_areas=[f for f in focus_areas if f not in excluded_set],
                excluded=excluded_set,
            )

        if not raw_exercises:
            # Every muscle group is excluded, or nothing safe is available
            updated_days.append({
                "dayPlanId": spec["dayPlanId"],
                "dayNumber": spec["dayNumber"],
                "dayName": spec["dayName"],
                "dayType": "rest",
                "workoutName": "Rest Day",
                "focusDescription": "Recovery (injury-adjusted)",
                "durationMinutes": 0,
                "exercises": [],
            })
            continue

        focus_label = _focus_label(safe_targets)
        if used_fallback:
            focus_label += " (Adjusted)"

        updated_days.append({
            "dayPlanId": spec["dayPlanId"],
            "dayNumber": spec["dayNumber"],
            "dayName": spec["dayName"],
            "dayType": "workout",
            "workoutName": base_split if not used_fallback else f"{base_split} (Adjusted)",
            "focusDescription": focus_label,
            "durationMinutes": _session_minutes(raw_exercises),
            "exercises": [_format_exercise(ex) for ex in raw_exercises],
        })

    return updated_days


# The app's users are in Malaysia, and the app writes completedAt as a
# local wall-clock time without an offset — so "this week" must be computed
# in the same local timezone, not UTC (otherwise, between Monday 00:00 and
# 08:00 local time, the server still thinks it's last week).
# Malaysia (UTC+8, no daylight saving). A fixed offset is used instead of
# zoneinfo("Asia/Kuala_Lumpur") because Windows has no system tz database,
# so zoneinfo would fail when running the backend locally.
DEFAULT_TIMEZONE = timezone(timedelta(hours=8))


def get_logged_day_numbers_this_week(
    db, uid: str, client_date: Optional[str] = None
) -> set[int]:
    """Weekdays (1=Mon..7=Sun) with a completed log in the current Mon-Sun week.

    client_date: the user's local date as "YYYY-MM-DD", if the app sent it.
    Falls back to today's date in DEFAULT_TIMEZONE.
    """
    today = _resolve_local_today(client_date)
    monday = today - timedelta(days=today.weekday())
    monday_start = datetime(monday.year, monday.month, monday.day)

    logs_ref = (
        db.collection("users").document(uid).collection("workoutLogs")
        .where("completedAt", ">=", monday_start.isoformat())
    )
    logged_weekdays = set()
    for doc in logs_ref.stream():
        data = doc.to_dict()
        completed_at = data.get("completedAt")
        if not completed_at:
            continue
        try:
            dt = datetime.fromisoformat(completed_at)
            logged_weekdays.add(dt.isoweekday())  # 1=Mon..7=Sun, matches dayNumber
        except (ValueError, TypeError):
            continue

    return logged_weekdays


def _resolve_local_today(client_date: Optional[str]) -> date:
    if client_date:
        try:
            return date.fromisoformat(client_date[:10])
        except ValueError:
            pass
    return datetime.now(DEFAULT_TIMEZONE).date()


def _build_session(
    available: list[dict],
    target_muscles: list[str],
    goal: str,
    experience: str,
    session_duration: str,
    focus_areas: list[str],
    excluded: Optional[set[str]] = None,
) -> list[dict]:
    """Selects and prescribes one workout day's exercises.

    1. Order the day's muscles: user focus areas first, then by the goal's
       muscle priority.
    2. Round-robin across those muscles, compounds before isolations within
       each muscle, so every muscle on the day gets work (previously all
       slots could go to one muscle, e.g. four chest moves on a Push day).
    3. Apply the goal's sets/reps/rest prescription.
    4. Add exercises (then extra sets) until the session fills the chosen
       session length, within the experience-level bounds.
    Exercises from muscles outside the day's split are never added, so a
    focus area can't put e.g. chest work on a Pull day.
    """
    excluded = excluded or set()
    focus = _expand_groups(focus_areas)
    priority = GOAL_MUSCLE_PRIORITY.get(goal, GOAL_MUSCLE_PRIORITY["muscleGain"])

    muscles = [m for m in target_muscles if m not in excluded]
    muscles.sort(key=lambda m: (
        0 if m in focus else 1,
        priority.index(m) if m in priority else len(priority),
    ))

    # Per-muscle queues: shuffled compounds first, then shuffled isolations
    queues = {}
    for m in muscles:
        pool = [ex for ex in available if _target_group(ex) == m]
        compounds = [ex for ex in pool if ex["is_compound"]]
        isolations = [ex for ex in pool if not ex["is_compound"]]
        random.shuffle(compounds)
        random.shuffle(isolations)
        queues[m] = compounds + isolations

    # Rotation: focus muscles appear twice per round so they get extra volume
    rotation = [m for m in muscles if m in focus] + muscles

    def next_exercise(used: set[str]) -> Optional[dict]:
        # Round-robin over the rotation, skipping exhausted queues
        for _ in range(len(rotation)):
            m = rotation[next_exercise.pos % len(rotation)]
            next_exercise.pos += 1
            q = queues.get(m, [])
            while q and q[0]["name"] in used:
                q.pop(0)
            if q:
                return q.pop(0)
        return None
    next_exercise.pos = 0

    min_count, max_count = EXERCISE_COUNT_BOUNDS.get(experience, (3, 6))
    target_work_seconds = (
        SESSION_MINUTES.get(session_duration, 60) - WARMUP_COOLDOWN_MINUTES
    ) * 60

    selected: list[dict] = []
    used_names: set[str] = set()
    if not rotation:
        return selected

    while len(selected) < max_count:
        candidate = next_exercise(used_names)
        if candidate is None:
            break
        prescribed = _prescribe(candidate, goal)
        projected = _work_seconds(selected) + _work_seconds([prescribed])
        if len(selected) >= min_count and projected > target_work_seconds:
            break
        selected.append(prescribed)
        used_names.add(candidate["name"])

    # Over the session length even at the minimum exercise count (e.g.
    # heavy 4x6 lifts with long rest in a 30-minute session)? Trim sets,
    # never below 2 per exercise.
    while _work_seconds(selected) > target_work_seconds:
        trimmable = [ex for ex in selected if ex["sets"] > 2]
        if not trimmable:
            break
        max(trimmable, key=lambda ex: ex["sets"] * ex["rest_seconds"])["sets"] -= 1

    # Still short of the session length (small pool, or the exercise cap
    # was hit)? Add sets to the compound lifts, one at a time.
    added = True
    while added and _work_seconds(selected) < target_work_seconds:
        added = False
        for ex in selected:
            if not ex["is_compound"] or ex["sets"] >= MAX_SETS_PER_EXERCISE:
                continue
            per_set = ex["rest_seconds"] + SECONDS_PER_WORKING_SET
            if _work_seconds(selected) + per_set > target_work_seconds:
                continue
            ex["sets"] += 1
            added = True

    return selected


def _prescribe(ex: dict, goal: str) -> dict:
    """Returns a copy of `ex` with the goal's sets/reps/rest applied.
    Timed holds (reps <= 1, e.g. plank) and low-rep skill moves keep their
    library values — their "reps" aren't comparable."""
    out = dict(ex)
    rule = GOAL_PRESCRIPTION.get(goal)
    if rule is None or ex["reps"] < 6:
        return out
    min_reps, max_reps, max_rest, set_delta = rule
    out["reps"] = max(min_reps, min(max_reps, ex["reps"]))
    out["rest_seconds"] = min(ex["rest_seconds"], max_rest)
    out["sets"] = max(2, ex["sets"] + set_delta)
    return out


def _work_seconds(exercises: list[dict]) -> int:
    return sum(
        ex["sets"] * (ex["rest_seconds"] + SECONDS_PER_WORKING_SET)
        for ex in exercises
    )


def _session_minutes(exercises: list[dict]) -> int:
    """Estimated total session length, including warm-up and cool-down."""
    if not exercises:
        return 0
    return round(_work_seconds(exercises) / 60) + WARMUP_COOLDOWN_MINUTES


def _focus_label(muscles: list[str]) -> str:
    names = []
    for m in muscles:
        label = "Arms" if m in ("biceps", "triceps") else MUSCLE_GROUP_MAP.get(m, m.title())
        if label not in names:
            names.append(label)
    return ", ".join(names)


def _format_exercise(ex: dict) -> dict:
    """
    Strips internal fields and returns only what Flutter needs to display.
    We don't send is_compound or difficulty to Flutter —
    those are internal plan-generation fields only.
    """
    return {
        "exerciseId": str(uuid.uuid4()),
        "exerciseName": ex["name"],
        "muscleGroup": MUSCLE_GROUP_MAP[ex["muscle_group"]],
        "secondaryMuscles": [m.title() for m in ex["secondary_muscles"]],
        "sets": ex["sets"],
        "reps": ex["reps"],
        "restSeconds": ex["rest_seconds"],
        "equipment": ex["equipment"],
        "wgerId": ex.get("wger_id"),
    }


def _day_name(day_number: int) -> str:
    """Converts day number 1-7 to day name."""
    return ["Monday", "Tuesday", "Wednesday",
            "Thursday", "Friday", "Saturday", "Sunday"][day_number - 1]