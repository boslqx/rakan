from dataclasses import dataclass
from typing import Literal, Optional

from routers.adapt_router import _apply_adaptation_rules

Tier = Literal["forced_deload", "session_priority", "weekly_priority"]
Trend = Literal["increasing", "stable", "decreasing", "insufficient_data"]

# Muscle recovery thresholds — rolling 7-day weighted-set count vs MRV
RECOVERY_FORCED_DELOAD_THRESHOLD = 0.8   # near/over MRV -> recovery overrides everything
RECOVERY_WELL_RECOVERED_THRESHOLD = 0.5  # below this -> weekly trend allowed to drive progress

# A forced deload should never be shallower than the plain session-fatigue
FORCED_DELOAD_FLOOR = -0.175  # matches Bell et al. (2025) reactive deload


# Weekly trend thresholds — see design discussion: 3-week rolling volume
TREND_INCREASING_THRESHOLD = 0.05   # ACSM (2026): 5% progressive overload
TREND_DECREASING_THRESHOLD = -0.10


@dataclass
class TrendResult:
    trend: Trend
    trend_adjustment: float


def compute_trend(current_volume: float, past_volumes: list[float]) -> TrendResult:
    if not past_volumes:
        return TrendResult(trend="insufficient_data", trend_adjustment=0.0)

    baseline = sum(past_volumes) / len(past_volumes)

    if baseline == 0:
        return TrendResult(trend="insufficient_data", trend_adjustment=0.0)

    pct_change = (current_volume - baseline) / baseline

    if pct_change > TREND_INCREASING_THRESHOLD:
        return TrendResult(trend="increasing", trend_adjustment=0.05)
    elif pct_change < TREND_DECREASING_THRESHOLD:
        return TrendResult(trend="decreasing", trend_adjustment=-0.10)
    else:
        return TrendResult(trend="stable", trend_adjustment=0.0)


@dataclass
class AdaptationDecision:
    final_adjustment: float
    tier: Tier
    reason: str


def resolve_adjustment(
    fatigue_score: float,
    muscle_recovery_score: float,
    weekly_trend_adjustment: float = 0.0,
    weekly_trend: Optional[Trend] = None,
) -> AdaptationDecision:
    session_level, session_adjustment, _ = _apply_adaptation_rules(fatigue_score)

    # Tier 1: forced deload
    if muscle_recovery_score > RECOVERY_FORCED_DELOAD_THRESHOLD:
        final_adjustment = min(session_adjustment, FORCED_DELOAD_FLOOR)
        return AdaptationDecision(
            final_adjustment=final_adjustment,
            tier="forced_deload",
            reason=(
                f"Muscle recovery score {muscle_recovery_score:.2f} exceeds "
                f"forced-deload threshold ({RECOVERY_FORCED_DELOAD_THRESHOLD}). "
                f"Session fatigue ({session_level}, {session_adjustment:+.3f}) "
                f"and weekly trend are overridden; deload floor applied."
            ),
        )

    # Tier 2: well recovered -> weekly trend allowed to drive progress
    if muscle_recovery_score < RECOVERY_WELL_RECOVERED_THRESHOLD:
        final_adjustment = max(session_adjustment, weekly_trend_adjustment)
        return AdaptationDecision(
            final_adjustment=final_adjustment,
            tier="weekly_priority",
            reason=(
                f"Muscle recovery score {muscle_recovery_score:.2f} is below "
                f"the well-recovered threshold ({RECOVERY_WELL_RECOVERED_THRESHOLD}). "
                f"Weekly trend ({weekly_trend or 'n/a'}, {weekly_trend_adjustment:+.3f}) "
                f"is allowed to drive progression; using the more favorable "
                f"of session ({session_adjustment:+.3f}) vs weekly."
            ),
        )

    # Tier 3: moderate recovery -> session fatigue is the tie-break 
    return AdaptationDecision(
        final_adjustment=session_adjustment,
        tier="session_priority",
        reason=(
            f"Muscle recovery score {muscle_recovery_score:.2f} is in the "
            f"moderate range ({RECOVERY_WELL_RECOVERED_THRESHOLD}-"
            f"{RECOVERY_FORCED_DELOAD_THRESHOLD}). Session fatigue "
            f"({session_level}, {session_adjustment:+.3f}) takes priority "
            f"over weekly trend ({weekly_trend or 'n/a'}, "
            f"{weekly_trend_adjustment:+.3f}) as the acute, safety-relevant signal."
        ),
    )