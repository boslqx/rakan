from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services.plan_generator import generate_plan, regenerate_days, get_logged_day_numbers_this_week
from firebase_config import db

router = APIRouter()

# This defines the exact shape of data Flutter must send
class RegeneratePlanRequest(BaseModel):
    uid: str
    plan_id: str
    excluded_muscle_groups: list[str]
    goal: str
    experience: str
    equipment: list[str]
    session_duration: str
    focus_areas: list[str]

@router.post("/regenerate-plan")
async def regenerate_plan_endpoint(request: RegeneratePlanRequest):
    try:
        plan_ref = (
            db.collection("users").document(request.uid)
            .collection("workoutPlans").document(request.plan_id)
        )
        days_ref = plan_ref.collection("days")

        # Step 1: find which weekdays are already locked (logged this week)
        logged_days = get_logged_day_numbers_this_week(db, request.uid)

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