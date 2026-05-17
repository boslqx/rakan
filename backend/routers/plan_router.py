from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services.plan_generator import generate_plan
from firebase_config import db

router = APIRouter()

# This defines the exact shape of data Flutter must send
# Pydantic validates it automatically — if Flutter sends wrong types,
# FastAPI returns a 422 error before our code even runs
class GeneratePlanRequest(BaseModel):
    uid: str
    goal: str
    experience: str
    equipment: list[str]
    workout_days: list[int]
    session_duration: str
    focus_areas: list[str]

@router.post("/generate-plan")
async def generate_plan_endpoint(request: GeneratePlanRequest):
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
        # Structure: users/{uid}/workoutPlans/{planId}
        # We save the plan metadata first, then days as a subcollection
        plan_ref = (
            db.collection("users")
            .document(request.uid)
            .collection("workoutPlans")
            .document(plan_id)
        )

        # Save top-level plan metadata (without days — those go in subcollection)
        plan_ref.set({
            "planId": plan_id,
            "uid": request.uid,
            "planName": plan["planName"],
            "status": plan["status"],
            "generatedAt": plan["generatedAt"],
            "weekNumber": plan["weekNumber"],
        })

        # Step 3: Save each day as a document in the days subcollection
        # We also save exercises as a subcollection under each day
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