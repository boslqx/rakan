from fastapi import APIRouter, HTTPException
from typing import Optional
from pydantic import BaseModel, Field
from services.plan_generator import generate_plan, regenerate_days, get_logged_day_numbers_this_week
from firebase_config import db

router = APIRouter()

# This defines the exact shape of data Flutter must send
class GeneratePlanRequest(BaseModel):
    uid: str
    goal: str
    experience: str
    equipment: list[str]
    # Weekday numbers 1 (Mon) .. 7 (Sun)
    workout_days: list[int] = Field(min_length=1, max_length=7)
    session_duration: str
    focus_areas: list[str]

@router.post("/generate-plan")
async def generate_plan_endpoint(request: GeneratePlanRequest):
    if any(d < 1 or d > 7 for d in request.workout_days):
        raise HTTPException(status_code=422, detail="workout_days must be 1-7")
    try:
        # Step 1: Generate the plan using our rule-based engine
        plan = generate_plan(
            uid=request.uid,
            goal=request.goal,
            experience=request.experience,
            equipment=request.equipment,
            workout_days=request.workout_days,
            session_duration=request.session_duration,
            focus_areas=request.focus_areas,
        )

        plan_id = plan["planId"]

        # Step 2: Save to Firestore
        # Structure: users/{uid}/workoutPlans/{planId}/days/{dayId}/exercises
        plan_ref = (
            db.collection("users")
            .document(request.uid)
            .collection("workoutPlans")
            .document(plan_id)
        )

        # Step 3: Save each day (and its exercises) under the new plan
        # first. The plan's own metadata doc is written last, below, so the
        # new plan only becomes visible as "active" once all its days exist.
        for day in plan["days"]:
            day_id = day["dayPlanId"]
            day_ref = plan_ref.collection("days").document(day_id)

            # Save day metadata without exercises list
            day_ref.set({
                "dayPlanId": day_id,
                "dayNumber": day["dayNumber"],
                "dayName": day["dayName"],
                "dayType": day["dayType"],
                "workoutName": day["workoutName"],
                "focusDescription": day["focusDescription"],
                "durationMinutes": day["durationMinutes"],
            })

            # Save each exercise as its own document
            for exercise in day["exercises"]:
                ex_ref = day_ref.collection("exercises").document(
                    exercise["exerciseId"]
                )
                ex_ref.set(exercise)

        # Step 3b: switch plans atomically — publish the new plan as active
        # and retire any previously active plan in ONE batch. Doing the
        # retirement here (only after the new plan is fully written) means a
        # failed or abandoned generation can never leave the user with no
        # active plan, which is what happened when the app deactivated the
        # old plan before calling this endpoint.
        plans_col = db.collection("users").document(request.uid).collection("workoutPlans")
        batch = db.batch()
        batch.set(plan_ref, {
            "planId": plan_id,
            "uid": request.uid,
            "planName": plan["planName"],
            "status": plan["status"],
            "generatedAt": plan["generatedAt"],
            "weekNumber": plan["weekNumber"],
        })
        for old in plans_col.where("status", "==", "active").stream():
            if old.id != plan_id:
                batch.update(old.reference, {"status": "inactive"})
        batch.commit()

        # Step 4: Return the plan ID so Flutter knows what to read
        return {
            "success": True,
            "planId": plan_id,
            "message": "Plan generated and saved to Firestore",
        }

    except Exception as e:
        # Log the error and return a clean HTTP 500
        print(f"Error generating plan: {e}")
        raise HTTPException(status_code=500, detail=str(e))


class RegeneratePlanRequest(BaseModel):
    uid: str
    plan_id: str
    excluded_muscle_groups: list[str]
    goal: str
    experience: str
    equipment: list[str]
    session_duration: str
    focus_areas: list[str]
    # The user's local date ("YYYY-MM-DD"), used to work out which days of
    # the current week are already logged. Optional for older app builds.
    client_date: Optional[str] = None

@router.post("/regenerate-plan")
async def regenerate_plan_endpoint(request: RegeneratePlanRequest):
    try:
        plan_ref = (
            db.collection("users").document(request.uid)
            .collection("workoutPlans").document(request.plan_id)
        )
        days_ref = plan_ref.collection("days")

        # Step 1: find which weekdays are already locked (logged this week)
        logged_days = get_logged_day_numbers_this_week(db, request.uid, request.client_date)

        # Step 2: fetch all day docs, split into locked vs eligible
        all_days_snap = days_ref.get()
        eligible_specs = []
        eligible_doc_ids = {}  # dayNumber -> firestore doc id

        for doc in all_days_snap:
            data = doc.to_dict()
            day_number = data.get("dayNumber")
            if day_number in logged_days:
                continue  # locked — never touched, per your explicit decision
            if data.get("dayType") != "workout":
                continue  # rest days have nothing to filter
            eligible_specs.append({
                "dayPlanId": doc.id,
                "dayNumber": day_number,
                "dayName": data.get("dayName"),
                "workoutName": data.get("workoutName", "Full Body"),
            })
            eligible_doc_ids[day_number] = doc.id

        if not eligible_specs:
            return {"success": True, "message": "No eligible days to update.", "updatedCount": 0}

        # Step 3: regenerate only the eligible days
        updated_days = regenerate_days(
            day_specs=eligible_specs,
            excluded_muscle_groups=request.excluded_muscle_groups,
            goal=request.goal,
            experience=request.experience,
            equipment=request.equipment,
            session_duration=request.session_duration,
            focus_areas=request.focus_areas,
        )

        # Step 4: write back — overwrite day metadata + exercises subcollection only
        batch = db.batch()
        for day in updated_days:
            day_ref = days_ref.document(day["dayPlanId"])
            batch.set(day_ref, {
                "dayPlanId": day["dayPlanId"],
                "dayNumber": day["dayNumber"],
                "dayName": day["dayName"],
                "dayType": day["dayType"],
                "workoutName": day["workoutName"],
                "focusDescription": day["focusDescription"],
                "durationMinutes": day["durationMinutes"],
            })
            # Clear old exercises, write new ones
            old_exercises = day_ref.collection("exercises").get()
            for ex_doc in old_exercises:
                batch.delete(ex_doc.reference)
            for exercise in day["exercises"]:
                ex_ref = day_ref.collection("exercises").document(exercise["exerciseId"])
                batch.set(ex_ref, exercise)

        batch.commit()

        return {
            "success": True,
            "message": f"Regenerated {len(updated_days)} day(s) around active injuries.",
            "updatedCount": len(updated_days),
        }

    except Exception as e:
        print(f"Error regenerating plan: {e}")
        raise HTTPException(status_code=500, detail=str(e))