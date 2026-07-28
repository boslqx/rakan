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


def _apply_adaptation_rules(fatigue_score: float) -> tuple[str, float, str]:
    """
    Maps a fatigue_score (0-1) to (fatigue_level, intensity_adjustment, message).

    This is the single source of truth for the adaptation thresholds — both the
    ML-predicted path and the RPE-only fallback path call this, so the
    adaptation behavior stays consistent regardless of which path is used.
    """
    if fatigue_score > 0.7:
        fatigue_level = "high"
        # Bell et al. (2025) Strength & Conditioning Journal: reactive deload
        intensity_adjustment = -0.175
        message = (
            "Your last session was very demanding. Next workout intensity "
            "reduced by 17.5% to allow recovery."
        )
    elif fatigue_score >= 0.4:
        fatigue_level = "medium"
        # ACSM (2026): RPE 6-7 or completion 70-90% → maintain intensity.
        intensity_adjustment = 0.0
        message = (
            "Good effort! Your recovery looks on track. Keeping the same "
            "intensity."
        )
    else:
        fatigue_level = "low"
        # ACSM (2026) & NASM: progressive overload = 5-10% volume/load increase
        intensity_adjustment = 0.10
        message = (
            "You handled that well! Intensity increased by 10% for "
            "progressive overload."
        )

    return fatigue_level, intensity_adjustment, message


@router.post("/adapt-plan", response_model=AdaptResponse)
def adapt_plan(req: AdaptRequest):
    """
    Predicts fatigue from the last workout session and returns
    how much to adjust the next session's intensity.

    Two paths to fatigue_score:
      - ML path (normal case): trained LinearRegression model + scaler,
        using all 6 features.
      - Fallback path (model/scaler missing): fatigue_score = avg_rpe / 10.
        This uses only the single feature we can compute with zero ML —
        RPE-based training regulation is itself a validated approach
        (Zourdos et al., 2016), so this isn't an arbitrary stand-in.

    Both paths are then run through the same threshold rules
    (_apply_adaptation_rules), so the adjustment behavior a user sees is
    identical either way — only how fatigue_score was computed differs.
    """

    if _model is None or _scaler is None:
        fatigue_score = req.avg_rpe / 10.0
        fatigue_score = max(0.0, min(1.0, fatigue_score))

        fatigue_level, intensity_adjustment, message = _apply_adaptation_rules(
            fatigue_score
        )

        return AdaptResponse(
            fatigue_score=round(fatigue_score, 4),
            fatigue_level=fatigue_level,
            intensity_adjustment=intensity_adjustment,
            message=message,
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

    fatigue_level, intensity_adjustment, message = _apply_adaptation_rules(
        fatigue_score
    )

    return AdaptResponse(
        fatigue_score=round(fatigue_score, 4),
        fatigue_level=fatigue_level,
        intensity_adjustment=intensity_adjustment,
        message=message,
    )