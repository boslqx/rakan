"""
Rakan - plan-change factor demo (Account C), for Chapter 4 screenshots
=======================================================================

Account C  demo.factors@rakan-demo.test   (password RakanDemo#2026)

The plan is built by the REAL backend generator (backend/services/plan_generator.py,
same code as /generate-plan): muscle gain, intermediate, full gym, 60 min, three
days a week (Push / Pull / Legs) placed so that, relative to today:
    today-3  Push   -> completed (a workout log exists, so the day is locked)
    today-1  Pull   -> MISSED (no log)  -> the missed-day popup appears on Home
    today+1  Legs   -> upcoming; a hip injury removes Legs + Glutes from it
Run setup on a Thursday, Friday or Saturday.

Usage (from C:\\Users\\User\\rakan):
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_factor_demo.py setup
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_factor_demo.py dump C   (or A / B)
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_factor_demo.py cleanup

Only demo accounts are touched.
"""
import argparse
import datetime as dt
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "backend")))

from firebase_admin import auth, firestore  # noqa: E402
import seed_adaptive_demo as base  # noqa: E402
from services.plan_generator import generate_plan  # noqa: E402

ACC_C = dict(email="demo.factors@rakan-demo.test", username="demo_factors", name="Demo Factors")
EMAILS = {"A": base.ACCOUNTS["A"]["email"], "B": base.ACCOUNTS["B"]["email"], "C": ACC_C["email"]}


def cmd_setup(db):
    now = dt.datetime.now()
    wd = now.isoweekday()
    if wd not in (4, 5, 6):
        sys.exit("Run setup on Thursday, Friday or Saturday (needs today-3 .. today+1 in the same week).")
    uid = base.get_or_create_user(ACC_C)
    base.wipe_user_data(db, uid, ACC_C["username"])
    users = db.collection("users").document(uid)
    today = now.date()
    days = [wd - 3, wd - 1, wd + 1]           # Push, Pull, Legs

    users.set({"displayName": ACC_C["name"], "username": ACC_C["username"],
               "usernameLower": ACC_C["username"], "isPrivate": False, "totalSessionsLogged": 1,
               "updatedAt": firestore.SERVER_TIMESTAMP})
    db.collection("usernames").document(ACC_C["username"]).set({"uid": uid})
    users.collection("profile").document("data").set({
        "name": ACC_C["name"], "gender": "male", "age": 22, "heightCm": 175.0, "weightKg": 70.0,
        "isMetric": True, "activityLevel": "moderatelyActive", "fitnessGoal": "muscleGain",
        "experienceLevel": "intermediate", "workoutDays": days, "sessionDuration": "sixtyMin",
        "equipment": ["fullGym"], "motivation": "buildStrength", "focusAreas": [], "injuries": [],
        "onboardingCompleted": True, "lastWeeklySummaryAt": base.iso_local(now),
        "demoSetupDate": today.isoformat(),
    })

    plan = generate_plan(uid=uid, goal="muscleGain", experience="intermediate", equipment=["fullGym"],
                         workout_days=days, session_duration="sixtyMin", focus_areas=[])
    # The plan "started" on the Sunday before this week, so the missed-day scan
    # covers this week only.
    start = (now - dt.timedelta(days=wd)).replace(hour=9, minute=0, second=0, microsecond=0)
    plan_ref = users.collection("workoutPlans").document(plan["planId"])
    for day in plan["days"]:
        d = dict(day); exs = d.pop("exercises")
        dref = plan_ref.collection("days").document(day["dayPlanId"])
        dref.set(d)
        for ex in exs:
            dref.collection("exercises").document(ex["exerciseId"]).set(ex)
    plan_ref.set({"planId": plan["planId"], "uid": uid, "planName": plan["planName"], "status": "active",
                  "generatedAt": start.astimezone(dt.timezone.utc).isoformat(), "weekNumber": 1})

    # Completed Push session on today-3
    push = next(d for d in plan["days"] if d["dayNumber"] == days[0])
    done = (now - dt.timedelta(days=3)).replace(hour=18, minute=30, second=0, microsecond=0)
    log_ref = users.collection("workoutLogs").document()
    total = sum(e["sets"] for e in push["exercises"])
    log_ref.set({"logId": log_ref.id, "planId": plan["planId"], "dayPlanId": push["dayPlanId"],
                 "workoutName": push["workoutName"], "startedAt": base.iso_local(done - dt.timedelta(minutes=55)),
                 "completedAt": base.iso_local(done), "totalDurationMins": 55, "totalVolume": 4200,
                 "totalSetsCompleted": total, "totalSetsPlanned": total, "completionRate": 1.0,
                 "prReached": False, "prExerciseNames": [], "isCompleted": True})
    groups = set()
    for e in push["exercises"]:
        groups.add(e["muscleGroup"])
        log_ref.collection("exerciseLogs").document().set({
            "exerciseName": e["exerciseName"], "muscleGroup": e["muscleGroup"], "setsCompleted": e["sets"],
            "repsCompleted": e["sets"] * e["reps"], "weightKg": 20, "rpeScale": 7, "rpeRated": True,
            "setDetails": [{"setNumber": s + 1, "reps": e["reps"], "weightKg": 20, "completed": True}
                           for s in range(e["sets"])]})
    users.collection("activityFeed").document(log_ref.id).set({
        "workoutName": push["workoutName"], "completedAt": base.iso_local(done), "totalDurationMins": 55,
        "totalSetsCompleted": total, "prReached": False})
    for g in groups:
        mrv = base.MRV.get(g, 16)
        users.collection("muscleRecovery").document(g).set({
            "muscleGroup": g, "lastTrained": base.iso_local(done), "fatigueScore": 0.35,
            "volumeLast7Days": round(0.35 * mrv * 300, 1), "weightedSetsLast7Days": round(0.35 * mrv, 1),
            "weeklyMrv": mrv, "recommendedRestDays": 2, "updatedAt": base.iso_local(now)})
    print(f"Account C ready: {ACC_C['email']} (uid {uid})")
    print("  Push  " + base.DAY_NAMES[days[0] - 1] + " (completed), Pull " + base.DAY_NAMES[days[1] - 1]
          + " (missed), Legs " + base.DAY_NAMES[days[2] - 1] + " (upcoming)")


def cmd_dump(db, key):
    uid = auth.get_user_by_email(EMAILS[key]).uid
    users = db.collection("users").document(uid)
    out = {"account": key, "at": dt.datetime.now().isoformat(timespec="seconds")}
    prof = users.collection("profile").document("data").get().to_dict() or {}
    out["profile"] = {k: prof.get(k) for k in ("fitnessGoal", "experienceLevel", "equipment", "workoutDays",
                                                 "sessionDuration", "focusAreas")}
    plans = []
    for p in users.collection("workoutPlans").stream():
        pd = p.to_dict()
        entry = {k: pd.get(k) for k in ("planName", "status", "weekNumber", "generatedAt")}
        if pd.get("status") == "active":
            entry["days"] = []
            for d in sorted(p.reference.collection("days").stream(), key=lambda d: d.to_dict()["dayNumber"]):
                dd = d.to_dict()
                exs = sorted((e.to_dict() for e in d.reference.collection("exercises").stream()),
                             key=lambda e: e.get("order", 0))
                entry["days"].append({
                    "day": dd["dayName"], "type": dd["dayType"], "name": dd["workoutName"],
                    "focus": dd.get("focusDescription"), "min": dd.get("durationMinutes"),
                    "orig": dd.get("originalWorkoutName"),
                    "ex": [f"{e['exerciseName']} [{e['muscleGroup']}; {','.join(e.get('equipment') or [])}] "
                           f"{e['sets']}x{e['reps']}" for e in exs],
                    "sets": sum(e["sets"] for e in exs)})
        plans.append(entry)
    out["plans"] = plans
    out["injuries"] = [{k: i.to_dict().get(k) for k in ("region", "label", "status", "estimatedRecoveryDays")}
                       for i in users.collection("injuries").stream()]
    out["overrides"] = [{k: o.to_dict().get(k) for k in ("date", "workoutName", "muscleGroup", "sourceMissedDate")}
                        | {"ex": [e.get("exerciseName") for e in o.to_dict().get("exercises", [])]}
                        for o in users.collection("scheduleOverrides").stream()]
    out["missed"] = [m.to_dict() | {"resolvedAt": None} for m in users.collection("missedDayResolutions").stream()]
    out["proposals"] = [{k: p.to_dict().get(k) for k in ("muscleGroup", "trigger", "status", "sourceLogId")}
                        for p in users.collection("adaptationProposals").stream()]
    print(json.dumps(out, indent=1, default=str))


def cmd_cleanup(db):
    try:
        uid = auth.get_user_by_email(ACC_C["email"]).uid
    except auth.UserNotFoundError:
        print("Account C: not found"); return
    base.wipe_user_data(db, uid, ACC_C["username"])
    auth.delete_user(uid)
    print("Account C: deleted")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["setup", "dump", "cleanup"])
    ap.add_argument("account", nargs="?", default="C", choices=["A", "B", "C"])
    a = ap.parse_args()
    db = base.init()
    {"setup": lambda: cmd_setup(db), "dump": lambda: cmd_dump(db, a.account),
     "cleanup": lambda: cmd_cleanup(db)}[a.command]()
