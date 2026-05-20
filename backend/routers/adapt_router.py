from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import joblib
import numpy as np
import os

router = APIRouter()

# Load model + scaler once at startup (not on every request)
_MODEL_DIR = os.path.join(os.path.dirname(__file__), "..", "ml")

try:
    _model = joblib.load(os.path.join(_MODEL_DIR, "fatigue_model.pkl"))
    _scaler = joblib.load(os.path.join(_MODEL_DIR, "fatigue_scaler.pkl"))
    print("✅ Fatigue model loaded successfully")
except FileNotFoundError:
    _model = None
    _scaler = None
    print("⚠️  Fatigue model not found — run ml/train_model.py first")


# Request schema
class AdaptRequest(BaseModel):
    avg_rpe: float           
    max_rpe: float           
    session_duration: float  
    exercises_count: int     
    completion_rate: float   
    experience_level: int   


# Response schema
class AdaptResponse(BaseModel):
    fatigue_score: float      
    fatigue_level: str       
    intensity_adjustment: float  
    message: str              


@router.post("/adapt-plan", response_model=AdaptResponse)
def adapt_plan(req: AdaptRequest):
    """
    Predicts fatigue from the last workout session and returns
    how much to adjust the next session's intensity.
    """

    if _model is None:
        raise HTTPException(
            status_code=503,
            detail="ML model not loaded. Run ml/train_model.py first."
        )

    # Build feature vector
    features = np.array([[
        req.avg_rpe,
        req.max_rpe,
        req.session_duration,
        req.exercises_count,
        req.completion_rate,
        req.experience_level,
    ]])

    # Scale using the SAVED scaler
    features_scaled = _scaler.transform(features)

    # Predict 
    fatigue_score = float(_model.predict(features_scaled)[0])

    # Clamp to valid range — linear regression can predict outside 0–1
    fatigue_score = max(0.0, min(1.0, fatigue_score))

    # Apply adaptation rules
    if fatigue_score > 0.7:
        fatigue_level = "high"
        intensity_adjustment = -0.175  # reduce by 17.5% (midpoint of 15–20%)
        message = "Your last session was very demanding. Next workout intensity reduced by 17.5% to allow recovery."
    elif fatigue_score >= 0.4:
        fatigue_level = "medium"
        intensity_adjustment = 0.0
        message = "Good effort! Your recovery looks on track. Keeping the same intensity."
    else:
        fatigue_level = "low"
        intensity_adjustment = 0.10   # increase by 10% 
        message = "You handled that well! Intensity increased by 10% for progressive overload."

    return AdaptResponse(
        fatigue_score=round(fatigue_score, 4),
        fatigue_level=fatigue_level,
        intensity_adjustment=intensity_adjustment,
        message=message,
    )