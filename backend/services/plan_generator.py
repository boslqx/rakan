import random
import uuid
from datetime import datetime
from data.exercises import get_exercises_for_equipment, filter_by_difficulty

# How many exercises per workout session based on experience
EXERCISES_PER_SESSION = {
    "beginner": 4,
    "intermediate": 5,
    "advanced": 6,
}

# Which muscle groups to train based on fitness goal
# muscleGain → hit all major groups with push/pull/legs split
# weightLoss → full body + cardio-style exercises
# endurance  → full body, higher reps
# flexibility → lighter, more isolation
GOAL_MUSCLE_PRIORITY = {
    "muscleGain":   ["chest", "back", "legs", "shoulders", "arms", "glutes", "abs"],
    "weightLoss":   ["legs", "abs", "chest", "back", "shoulders", "glutes", "arms"],
    "endurance":    ["legs", "abs", "back", "chest", "shoulders", "arms", "glutes"],
    "flexibility":  ["abs", "glutes", "legs", "shoulders", "back", "chest", "arms"],
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

# Which muscle groups each split day focuses on
SPLIT_MUSCLES = {
    "Full Body":           ["chest", "back", "legs", "shoulders", "arms", "abs"],
    "Upper Body":          ["chest", "back", "shoulders", "arms"],
    "Lower Body":          ["legs", "glutes", "abs"],
    "Push":                ["chest", "shoulders", "arms"],
    "Pull":                ["back", "arms"],
    "Legs":                ["legs", "glutes"],
    "Chest & Triceps":     ["chest", "arms"],
    "Back & Biceps":       ["back", "arms"],
    "Shoulders & Arms":    ["shoulders", "arms"],
    "Chest":               ["chest"],
    "Back":                ["back"],
    "Shoulders":           ["shoulders"],
    "Arms":                ["arms"],
    "Active Recovery":     ["abs"],
}


def generate_plan(
    uid: str,
    goal: str,
    experience: str,
    equipment: list[str],
    workout_days: list[int],   # e.g. [1, 3, 5] = Mon, Wed, Fri
    session_duration: str,     # "thirtyMin", "sixtyMin"
    focus_areas: list[str],
) -> dict:
    """
    Main plan generation function.
    Returns a structured plan dict ready to be saved to Firestore.

    The logic flow:
    1. Filter exercise pool by equipment + difficulty
    2. Determine the split based on number of workout days
    3. For each workout day, select exercises matching that day's muscle focus
    4. For rest days, mark as rest
    5. Return structured plan
    """

    # Step 1: Get exercises this user can actually do
    available = get_exercises_for_equipment(equipment)
    available = filter_by_difficulty(available, experience)

    # Step 2: Determine exercises per session from experience level
    ex_per_session = EXERCISES_PER_SESSION.get(experience, 4)

    # Step 3: Adjust for session duration
    # Shorter sessions = fewer exercises
    if session_duration == "thirtyMin":
        ex_per_session = max(3, ex_per_session - 1)
    elif session_duration == "ninetyPlusMin":
        ex_per_session = ex_per_session + 1

    # Step 4: Get the split template for this many workout days
    num_workout_days = len(workout_days)
    split_names = DAY_SPLITS.get(num_workout_days, ["Full Body"])

    # Step 5: Get muscle priority order for this goal
    muscle_priority = GOAL_MUSCLE_PRIORITY.get(goal, GOAL_MUSCLE_PRIORITY["muscleGain"])

    # Step 6: Build the 7-day plan
    days = []
    split_index = 0  # cycles through split_names for workout days

    for day_number in range(1, 8):  # days 1 through 7
        day_name = _day_name(day_number)

        if day_number in workout_days:
            # This is a workout day
            split_name = split_names[split_index % len(split_names)]
            split_index += 1

            # Get muscle groups for this split
            target_muscles = SPLIT_MUSCLES.get(split_name, ["chest"])

            # Select raw exercises first (still have rest_seconds at this point)
            raw_exercises = _select_raw_exercises(
                available=available,
                target_muscles=target_muscles,
                muscle_priority=muscle_priority,
                count=ex_per_session,
                focus_areas=focus_areas,
            )

            # Calculate duration BEFORE formatting strips rest_seconds
            est_minutes = sum(
                (ex["sets"] * ex["rest_seconds"] + ex["sets"] * 45) // 60
                for ex in raw_exercises
            )

            # Now format for Flutter
            exercises = [_format_exercise(ex) for ex in raw_exercises]

            days.append({
                "dayPlanId": str(uuid.uuid4()),
                "dayNumber": day_number,
                "dayName": day_name,
                "dayType": "workout",
                "workoutName": split_name,
                "focusDescription": ", ".join(target_muscles).title(),
                "durationMinutes": est_minutes,
                "exercises": exercises,
            })
        else:
            # This is a rest day
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

    # Step 7: Build the final plan document
    plan = {
        "planId": str(uuid.uuid4()),
        "uid": uid,
        "planName": f"Week 1 — {goal.replace('muscleGain', 'Muscle Gain').replace('weightLoss', 'Weight Loss').replace('endurance', 'Endurance').replace('flexibility', 'Flexibility')}",
        "status": "active",
        "generatedAt": datetime.utcnow().isoformat(),
        "weekNumber": 1,
        "days": days,
    }

    return plan


def _select_raw_exercises(
    available: list[dict],
    target_muscles: list[str],
    muscle_priority: list[str],
    count: int,
    focus_areas: list[str],
) -> list[dict]:
    """
    Selects `count` exercises for a given day.

    Priority order:
    1. Compound exercises targeting the day's muscle groups
    2. User's focus areas (from onboarding Step 7)
    3. Isolation exercises to fill remaining slots
    4. Random shuffle within each tier to add variety
    """
    selected = []
    used_names = set()

    # Filter available exercises to those targeting today's muscles
    day_pool = [
        ex for ex in available
        if ex["muscle_group"] in target_muscles
    ]

    # Tier 1: Compound exercises (most important — do these first)
    compounds = [ex for ex in day_pool if ex["is_compound"]]
    random.shuffle(compounds)
    for ex in compounds:
        if len(selected) >= count:
            break
        if ex["name"] not in used_names:
            selected.append(ex)                      # ← raw dict
            used_names.add(ex["name"])

    # Tier 2: Focus area exercises (user's preferred muscles)
    focus_pool = [
        ex for ex in available
        if ex["muscle_group"] in focus_areas
        and ex["name"] not in used_names
    ]
    random.shuffle(focus_pool)
    for ex in focus_pool:
        if len(selected) >= count:
            break
        selected.append(ex)                          # ← raw dict
        used_names.add(ex["name"])

    # Tier 3: Fill remaining slots with isolation exercises
    isolations = [
        ex for ex in day_pool
        if not ex["is_compound"]
        and ex["name"] not in used_names
    ]
    random.shuffle(isolations)
    for ex in isolations:
        if len(selected) >= count:
            break
        selected.append(ex)                          # ← raw dict
        used_names.add(ex["name"])

    return selected


def _format_exercise(ex: dict) -> dict:
    """
    Strips internal fields and returns only what Flutter needs to display.
    We don't send is_compound or difficulty to Flutter —
    those are internal plan-generation fields only.
    """
    return {
        "exerciseId": str(uuid.uuid4()),
        "exerciseName": ex["name"],
        "muscleGroup": ex["muscle_group"],
        "secondaryMuscles": ex["secondary_muscles"],
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