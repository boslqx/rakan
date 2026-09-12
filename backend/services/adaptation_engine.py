from dataclasses import dataclass
from typing import Literal, Optional

from routers.adapt_router import _apply_adaptation_rules

Tier = Literal[
    "scheduled_deload",
    "return_from_break",
    "forced_deload",
    "session_priority",
    "weekly_priority",
]
Trend = Literal["increasing", "stable", "decreasing", "insufficient_data"]

# Muscle recovery thresholds — rolling 7-day weighted-set count vs MRV
RECOVERY_FORCED_DELOAD_THRESHOLD = 0.8   # near/over MRV -> recovery overrides everything
RECOVERY_WELL_RECOVERED_THRESHOLD = 0.5  # below this -> weekly trend allowed to drive progress

# A forced deload should never be shallower than the plain session-fatigue
FORCED_DELOAD_FLOOR = -0.175  # matches Bell et al. (2025) reactive deload

# Scheduled (mesocycle) deload ughly 40-50%
SCHEDULED_DELOAD_ADJUSTMENT = -0.425

# Return-from-break reduction, applied when the user explicitly records a
# skipped session (Phase 25 missed-day popup) and later returns to train
# that muscle group again. Gated on elapsed calendar time, not occurrence
# count — see DETRAINING_THRESHOLD_DAYS. Deliberately reuses the Bell et
# al. (2025) reactive-deload magnitude for the long-break case: not a
# precise detraining-loss estimate, but an already-validated conservative
# reduction, repurposed as a re-engagement safety margin.
RETURN_FROM_BREAK_ADJUSTMENT = -0.175  # matches FORCED_DELOAD_FLOOR

# Short-term vs long-term detraining boundary. Below/at this many days
# since a muscle group was last trained, strength and hypertrophy
# adaptations are well retained and no reduction is warranted; past it,
# the conservative RETURN_FROM_BREAK_ADJUSTMENT applies.
#
# Encarnação, I.G.A., Viana, R.B., Soares, S.R.S., Freitas, E.D.S., de
# Lira, C.A.B. and Ferreira-Junior, J.B. (2022) 'Effects of detraining on
# muscle strength and hypertrophy induced by resistance training: a
# systematic review', Muscles, 1(1), pp. 1-15. doi: 10.3390/muscles1010001.
# — establishes/confirms the short-term (<=4 weeks) vs long-term (>4
# weeks) boundary; pooled data shows strength retained even out to 16-24
# weeks in some cases.
# Mujika, I. and Padilla, S. (2000) 'Detraining: loss of training-induced
# physiological and performance adaptations. Part I', Sports Medicine,
# 30(2), pp. 79-87. — original source of the short/long-term boundary,
# cited alongside the 2022 review as the foundational source it builds on.
DETRAINING_THRESHOLD_DAYS = 28


# Weekly trend thresholds 
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
    fatigue_score: Optional[float],
    muscle_recovery_score: float,
    weekly_trend_adjustment: float = 0.0,
    weekly_trend: Optional[Trend] = None,
    is_deload_week: bool = False,
    trigger: str = "session",
    days_since_last_trained: Optional[int] = None,
) -> AdaptationDecision:
    # Tier 0: scheduled (mesocycle) deload — a programmed block boundary,
    if is_deload_week:
        fatigue_label = f"{fatigue_score:.2f}" if fatigue_score is not None else "n/a"
        return AdaptationDecision(
            final_adjustment=SCHEDULED_DELOAD_ADJUSTMENT,
            tier="scheduled_deload",
            reason=(
                "This is a scheduled mesocycle deload week. Session fatigue "
                f"({fatigue_label}), muscle recovery "
                f"({muscle_recovery_score:.2f}), and weekly trend "
                f"({weekly_trend or 'n/a'}) are all overridden — a programmed "
                "deload is not up for negotiation by any reactive signal."
            ),
        )

    # Tier 0.5: return from break. Triggered by an explicit user choice
    # (Phase 25 missed-day popup "Skip entirely"), not an occurrence
    # streak. Whether a reduction applies at all is gated on elapsed
    # calendar time since this muscle group was actually last trained.
    if trigger == "skip":
        short_term = (
            days_since_last_trained is not None
            and days_since_last_trained <= DETRAINING_THRESHOLD_DAYS
        )
        gap_label = (
            f"{days_since_last_trained} days"
            if days_since_last_trained is not None
            else "an unknown number of days"
        )
        if short_term:
            return AdaptationDecision(
                final_adjustment=0.0,
                tier="return_from_break",
                reason=(
                    f"User explicitly recorded a skipped session for this "
                    f"muscle group. {gap_label} since it was last trained "
                    "falls within the short-term detraining window (<=4 "
                    "weeks), where strength and hypertrophy adaptations are "
                    "well retained (Encarnação et al., 2022; Mujika & "
                    "Padilla, 2000) — no volume reduction is applied. The "
                    "skip was still worth recording (Gjestvang et al., "
                    "2023: unaddressed missed sessions predict dropout), it "
                    "just doesn't carry a physiological adjustment at this gap length."
                ),
            )
        return AdaptationDecision(
            final_adjustment=RETURN_FROM_BREAK_ADJUSTMENT,
            tier="return_from_break",
            reason=(
                f"User explicitly recorded a skipped session for this "
                f"muscle group. {gap_label} since it was last trained "
                "exceeds the short-term detraining window (Encarnação et "
                "al., 2022; Mujika & Padilla, 2000). A conservative "
                "reduction is applied on return — the same magnitude as a "
                "reactive deload (Bell et al., 2025) rather than a precise "
                "detraining-loss estimate — to lower the barrier to "
                "resuming consistency (Gjestvang et al., 2023) after the "
                "longer layoff."
            ),
        )

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
