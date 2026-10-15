"""
Rakan - adaptive engine demo data (for Chapter 4 screenshots)
=============================================================

Creates two demo accounts in your Firebase project, each with a plan, recent
workout logs, muscle-recovery scores and pending adaptation proposals, so the
REAL weekly adaptation engine in the app produces every scenario:

  Account A  demo.adaptive@rakan-demo.test   (normal week 5 -> 6)
    Chest      hard session, moderate recovery   -> Tier 3 session priority   -17.5 %
    Back       easy session, well recovered      -> Tier 2 weekly priority    +10 %
    Shoulders  moderate session, well recovered  -> Tier 2 (weekly trend wins) +5 %
    Legs       easy session, recovery 0.92       -> Tier 1 forced deload      -17.5 %
    Arms       skipped, returned after 35 days   -> Tier 0.5 return from break -17.5 %
    Core       skipped, returned after 14 days   -> Tier 0.5 return from break  0 % (no change)

  Account B  demo.deload@rakan-demo.test     (week 3 -> 4 = scheduled deload)
    All six muscle groups                        -> Tier 0 scheduled deload   -42.5 %

Password for both: RakanDemo#2026

Usage (run from the repo root, C:\\Users\\User\\rakan):
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_adaptive_demo.py setup
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_adaptive_demo.py trigger
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_adaptive_demo.py report
    backend\\venv\\Scripts\\python tools\\demo_seed\\seed_adaptive_demo.py cleanup

  setup    Build the "before" state. The weekly run is NOT due yet, so you can
           take the "before" screenshots first.
  trigger  Make the weekly run due (last run = 8 days ago). Reopen the app and
           the engine runs. Run it on the SAME DAY as setup.
  report   Print the before/after sets x reps and the weekly summary that the
           app wrote, for your report table.
  cleanup  Delete both demo accounts and all their data.

Only the two demo accounts are touched. Your own account is never read or written.
"""
import argparse
import datetime as dt
import os
import sys
import uuid

import firebase_admin
from firebase_admin import auth, credentials, firestore

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
KEY = os.environ.get("RAKAN_SA_KEY", os.path.join(REPO, "backend", "serviceAccountKey.json"))

PASSWORD = "RakanDemo#2026"
MRV = {"Chest": 20, "Back": 20, "Legs": 20, "Glutes": 20, "Shoulders": 16, "Arms": 16, "Core": 12}

# (name, group, backend equipment tags, sets, reps, rest seconds)
EXERCISES = [
    ("Barbell Bench Press", "Chest", ["barbell", "bench"], 4, 10, 90),
    ("Lat Pulldown", "Back", ["machines"], 3, 10, 75),
    ("Dumbbell Shoulder Press", "Shoulders", ["dumbbell"], 3, 12, 75),
    ("Barbell Squat", "Legs", ["barbell"], 4, 8, 120),
    ("Dumbbell Hammer Curl", "Arms", ["dumbbell"], 3, 12, 60),
    ("Crunch", "Core", ["noEquipment"], 3, 15, 45),
]
WEIGHT = {"Barbell Bench Press": 60, "Lat Pulldown": 50, "Dumbbell Shoulder Press": 16,
          "Barbell Squat": 80, "Dumbbell Hammer Curl": 12, "Crunch": 0}

# Fatigue scores are the real outputs of the trained model (/adapt-plan) for:
HARD = 0.7215   # avg RPE 9, max 10, 75 min, 70 % completed
EASY = 0.3285   # avg RPE 4, max 5, 40 min, 100 % completed
MOD = 0.4924    # avg RPE 6.5, max 7, 55 min, 95 % completed

ACCOUNTS = {
    "A": dict(
        email="demo.adaptive@rakan-demo.test", username="demo_adaptive", name="Demo Adaptive",
        week=5,
        # group: (recovery score, trigger, session fatigue, days since last trained)
        proposals={
            "Chest": (0.65, "session", HARD, None),
            "Back": (0.35, "session", EASY, None),
            "Shoulders": (0.30, "session", MOD, None),
            "Legs": (0.92, "session", EASY, None),
            "Arms": (0.15, "skip", None, 35),
            "Core": (0.10, "skip", None, 14),
        },
        # (days ago, workout name, groups trained, RPE, volume)
        logs=[(5, "Full Body A", ["Chest", "Back", "Shoulders", "Legs"], 9, 3500),
              (3, "Full Body B", ["Chest", "Back", "Shoulders", "Legs"], 5, 3500),
              (1, "Arms & Core (return)", ["Arms", "Core"], 6, 2000)],
        past_volumes=[(8, 8400, 5, False), (15, 8200, 4, True), (22, 8000, 3, False)],
    ),
    "B": dict(
        email="demo.deload@rakan-demo.test", username="demo_deload", name="Demo Deload",
        week=3,
        proposals={g: (r, "session", EASY, None) for g, r in
                   [("Chest", 0.40), ("Back", 0.35), ("Shoulders", 0.45), ("Legs", 0.55), ("Arms", 0.30), ("Core", 0.20)]},
        logs=[(5, "Full Body A", ["Chest", "Back", "Shoulders", "Legs", "Arms", "Core"], 5, 4500),
              (2, "Full Body B", ["Chest", "Back", "Shoulders", "Legs", "Arms", "Core"], 5, 4500)],
        past_volumes=[(8, 8400, 3, False), (15, 8200, 2, False)],
    ),
}

DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def init():
    if not os.path.exists(KEY):
        sys.exit(f"Service account key not found: {KEY}\nSet RAKAN_SA_KEY to its path.")
    firebase_admin.initialize_app(credentials.Certificate(KEY))
    return firestore.client()


def iso_local(t):
    """Same format as Dart's DateTime.toIso8601String() for a local time."""
    return t.replace(tzinfo=None).isoformat(timespec="milliseconds")


def get_or_create_user(acc):
    try:
        u = auth.get_user_by_email(acc["email"])
        auth.update_user(u.uid, password=PASSWORD, email_verified=True, display_name=acc["name"])
        return u.uid
    except auth.UserNotFoundError:
        return auth.create_user(email=acc["email"], password=PASSWORD, email_verified=True,
                                display_name=acc["name"]).uid


def _delete_doc_tree(doc_ref):
    for sub in doc_ref.collections():
        for d in sub.stream():
            _delete_doc_tree(d.reference)
    doc_ref.delete()


def wipe_user_data(db, uid, username):
    ref = db.collection("users").document(uid)
    if hasattr(db, "recursive_delete"):
        db.recursive_delete(ref)
    else:
        _delete_doc_tree(ref)
    db.collection("usernames").document(username.lower()).delete()


def setup_account(db, key, acc, now):
    uid = get_or_create_user(acc)
    wipe_user_data(db, uid, acc["username"])
    today = now.date()
    wd = now.isoweekday()  # 1 = Monday
    users = db.collection("users").document(uid)

    # Public user doc + username
    users.set({"displayName": acc["name"], "username": acc["username"], "usernameLower": acc["username"].lower(),
               "isPrivate": False, "totalSessionsLogged": len(acc["logs"]), "updatedAt": firestore.SERVER_TIMESTAMP})
    db.collection("usernames").document(acc["username"].lower()).set({"uid": uid})

    future_days = list(range(wd + 1, 8))
    users.collection("profile").document("data").set({
        "name": acc["name"], "gender": "male", "age": 22, "heightCm": 175.0, "weightKg": 70.0, "isMetric": True,
        "activityLevel": "moderatelyActive", "fitnessGoal": "muscleGain", "experienceLevel": "intermediate",
        "workoutDays": future_days, "sessionDuration": "sixtyMin", "equipment": ["fullGym"],
        "motivation": "buildStrength", "focusAreas": [], "injuries": [], "onboardingCompleted": True,
        # Weekly run is NOT due yet -> the "before" state stays on screen.
        "lastWeeklySummaryAt": iso_local(now),
        "demoSetupDate": today.isoformat(),
    })

    # Plan: every day after today is a full-body day containing all six groups,
    # so each future day shows every adjustment. Today and earlier are rest days.
    plan_id = str(uuid.uuid4())
    plan = users.collection("workoutPlans").document(plan_id)
    plan.set({"planId": plan_id, "uid": uid, "planName": "Muscle Gain Plan (demo)",
              "status": "active", "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
              "weekNumber": acc["week"]})
    for n in range(1, 8):
        day_id = str(uuid.uuid4())
        is_workout = n in future_days
        day = plan.collection("days").document(day_id)
        day.set({"dayPlanId": day_id, "dayNumber": n, "dayName": DAY_NAMES[n - 1],
                 "dayType": "workout" if is_workout else "rest",
                 "workoutName": "Full Body" if is_workout else "Rest Day",
                 "focusDescription": "Chest, Back, Shoulders, Legs, Arms, Core" if is_workout else "Recovery",
                 "durationMinutes": 60 if is_workout else 0})
        if is_workout:
            for i, (name, group, eq, sets, reps, rest) in enumerate(EXERCISES):
                ex_id = str(uuid.uuid4())
                day.collection("exercises").document(ex_id).set({
                    "exerciseId": ex_id, "exerciseName": name, "muscleGroup": group, "secondaryMuscles": [],
                    "sets": sets, "reps": reps, "restSeconds": rest, "equipment": eq, "wgerId": None, "order": i,
                    "demoBaseSets": sets, "demoBaseReps": reps,
                })

    # Workout logs (last 7 days) + activity feed copies
    last_trained = {}
    log_ids = []
    for days_ago, wname, groups, rpe, volume in acc["logs"]:
        done = (now - dt.timedelta(days=days_ago)).replace(hour=18, minute=30, second=0, microsecond=0)
        start = done - dt.timedelta(minutes=55)
        log_id = str(uuid.uuid4())
        log_ids.append(log_id)
        exs = [e for e in EXERCISES if e[1] in groups]
        total_sets = sum(e[3] for e in exs)
        log = users.collection("workoutLogs").document(log_id)
        log.set({"logId": log_id, "planId": plan_id, "dayPlanId": "", "workoutName": wname,
                 "startedAt": iso_local(start), "completedAt": iso_local(done), "totalDurationMins": 55,
                 "totalVolume": volume, "totalSetsCompleted": total_sets, "totalSetsPlanned": total_sets,
                 "completionRate": 1.0, "prReached": False, "prExerciseNames": [], "isCompleted": True})
        for name, group, eq, sets, reps, rest in exs:
            w = WEIGHT[name]
            log.collection("exerciseLogs").document(str(uuid.uuid4())).set({
                "exerciseLogId": str(uuid.uuid4()), "exerciseName": name, "muscleGroup": group,
                "setsCompleted": sets, "repsCompleted": sets * reps, "weightKg": w, "rpeScale": rpe, "rpeRated": True,
                "setDetails": [{"setNumber": s + 1, "reps": reps, "weightKg": w, "completed": True} for s in range(sets)],
            })
            last_trained[group] = max(last_trained.get(group, done), done)
        users.collection("activityFeed").document(log_id).set({
            "workoutName": wname, "completedAt": iso_local(done), "totalDurationMins": 55,
            "totalSetsCompleted": total_sets, "prReached": False})

    # Muscle recovery scores (what the Recovery Map and the engine read)
    for group, (score, trig, fat, gap) in acc["proposals"].items():
        mrv = MRV[group]
        users.collection("muscleRecovery").document(group).set({
            "muscleGroup": group, "lastTrained": iso_local(last_trained.get(group, now - dt.timedelta(days=1))),
            "fatigueScore": score, "volumeLast7Days": round(score * mrv * 300.0, 1),
            "weightedSetsLast7Days": round(score * mrv, 1), "weeklyMrv": mrv,
            "recommendedRestDays": 2 if score < 0.5 else 3, "updatedAt": iso_local(now)})

    # Pending proposals (normally written by AdaptService after each session / skip)
    for group, (score, trig, fat, gap) in acc["proposals"].items():
        p = {"createdAt": firestore.SERVER_TIMESTAMP, "muscleGroup": group, "sessionFatigueScore": fat,
             "status": "pending", "sourceLogId": log_ids[0], "trigger": trig}
        if trig == "skip":
            p["priorLastTrainedDate"] = (today - dt.timedelta(days=gap + 1)).isoformat()
            p["daysSinceLastTrained"] = gap
            p["sourceLogId"] = f"{group}|{(today - dt.timedelta(days=gap)).isoformat()}"
        users.collection("adaptationProposals").add(p)

    # Earlier weekly summaries (give the volume trend a baseline)
    for days_ago, vol, week, deload in acc["past_volumes"]:
        gen = now - dt.timedelta(days=days_ago)
        users.collection("weeklySummaries").add({
            "weekStart": iso_local(gen - dt.timedelta(days=7)), "weekEnd": iso_local(gen),
            "sessionsCompleted": 3, "avgRpe": 6.5, "totalVolume": vol, "trend": "stable", "trendAdjustment": 0.0,
            "weekNumber": week, "isDeloadWeek": deload, "generatedAt": iso_local(gen), "changes": [],
            "changesAcknowledged": True})
    print(f"  Account {key}: {acc['email']}  (uid {uid})  plan week {acc['week']}")


def cmd_setup(db):
    now = dt.datetime.now()
    if now.isoweekday() == 7:
        sys.exit("Today is Sunday: the engine only changes days AFTER today, so nothing would change.\n"
                 "Run setup and trigger on Monday to Saturday.")
    print("Setting up demo accounts (before state)...")
    for k, acc in ACCOUNTS.items():
        setup_account(db, k, acc, now)
    print(f"\nDone. Password for both accounts: {PASSWORD}")
    print("Next: log in on your phone and take the BEFORE screenshots, then run 'trigger'.")


def uid_of(acc):
    return auth.get_user_by_email(acc["email"]).uid


def cmd_trigger(db, only=None):
    now = dt.datetime.now()
    for k, acc in ACCOUNTS.items():
        if only and k != only:
            continue
        uid = uid_of(acc)
        prof = db.collection("users").document(uid).collection("profile").document("data")
        data = prof.get().to_dict() or {}
        if data.get("demoSetupDate") != now.date().isoformat():
            sys.exit(f"Account {k} was set up on {data.get('demoSetupDate')}, not today.\n"
                     "Run 'setup' again today and retake the BEFORE screenshots first.")
        prof.update({"lastWeeklySummaryAt": iso_local(now - dt.timedelta(days=8))})
        print(f"  Account {k}: weekly run is now due.")
    print("\nNow: wake the backend (open https://rakan-backend.onrender.com in a browser), then fully close\n"
          "and reopen the app on the demo account. Wait about 30 seconds on Home, close and reopen\n"
          "the app again, and the weekly summary dialog will appear.")


def cmd_report(db):
    for k, acc in ACCOUNTS.items():
        uid = uid_of(acc)
        users = db.collection("users").document(uid)
        print(f"\n=== Account {k}: {acc['email']} ===")
        plan = next(iter(users.collection("workoutPlans").where("status", "==", "active").limit(1).stream()), None)
        if plan is None:
            print("  no active plan"); continue
        print(f"  Plan week: {plan.to_dict().get('weekNumber')}")
        days = sorted(plan.reference.collection("days").stream(), key=lambda d: d.to_dict()["dayNumber"])
        shown = False
        for d in days:
            dd = d.to_dict()
            if dd["dayType"] != "workout" or shown:
                continue
            shown = True
            print(f"  {dd['dayName']} ({dd['workoutName']}):")
            print(f"    {'Exercise':26} {'Group':10} {'Before':>8} {'After':>8}  Tier")
            for e in sorted(d.reference.collection("exercises").stream(), key=lambda e: e.to_dict().get("order", 0)):
                x = e.to_dict()
                before = f"{x.get('demoBaseSets')}x{x.get('demoBaseReps')}"
                after = f"{x['sets']}x{x['reps']}"
                print(f"    {x['exerciseName']:26} {x['muscleGroup']:10} {before:>8} {after:>8}  {x.get('fatigueLevel', '-')}")
        summ = sorted((s.to_dict() for s in users.collection("weeklySummaries").stream()),
                      key=lambda s: s.get("generatedAt", ""), reverse=True)
        if summ:
            s = summ[0]
            print(f"  Latest weekly summary: week {s.get('weekNumber')}, deload={s.get('isDeloadWeek')}, "
                  f"trend={s.get('trend')} ({s.get('trendAdjustment')}), volume={s.get('totalVolume')}")
            for c in s.get("changes", []):
                print(f"    {c['muscleGroup']:10} {c['tier']:18} {c['adjustment']:+.3f}  recovery={c.get('recoveryScore')}")
        props = [p.to_dict() for p in users.collection("adaptationProposals").stream()]
        print("  Proposals: " + ", ".join(f"{p['muscleGroup']}={p['status']}/{p.get('resolvedTier', '-')}" for p in props))


def cmd_rename(db):
    for k, acc in ACCOUNTS.items():
        users = db.collection("users").document(uid_of(acc))
        for p in users.collection("workoutPlans").where("status", "==", "active").stream():
            p.reference.update({"planName": "Muscle Gain Plan (demo)"})
            print(f"  Account {k}: plan renamed")


def cmd_unack(db, only=None):
    """Mark the latest weekly summary as unseen so the summary dialog shows again."""
    for k, acc in ACCOUNTS.items():
        if only and k != only:
            continue
        u = db.collection("users").document(uid_of(acc))
        docs = sorted(u.collection("weeklySummaries").stream(),
                      key=lambda d: d.to_dict().get("generatedAt"), reverse=True)
        if docs:
            docs[0].reference.update({"changesAcknowledged": False})
            print(f"  Account {k}: latest summary marked unacknowledged")


def cmd_cleanup(db):
    for k, acc in ACCOUNTS.items():
        try:
            uid = uid_of(acc)
        except auth.UserNotFoundError:
            print(f"  Account {k}: not found"); continue
        wipe_user_data(db, uid, acc["username"])
        auth.delete_user(uid)
        print(f"  Account {k}: deleted")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["setup", "trigger", "report", "cleanup", "rename", "unack"])
    ap.add_argument("account", nargs="?", choices=["A", "B"], help="trigger only this account")
    args = ap.parse_args()
    db = init()
    if args.command == "trigger":
        cmd_trigger(db, args.account)
    elif args.command == "unack":
        cmd_unack(db, args.account)
    else:
        {"setup": cmd_setup, "report": cmd_report, "cleanup": cmd_cleanup, "rename": cmd_rename}[args.command](db)
