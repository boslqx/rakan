import pytest

from services.adaptation_engine import (
    resolve_adjustment,
    compute_trend,
    RECOVERY_FORCED_DELOAD_THRESHOLD,
    RECOVERY_WELL_RECOVERED_THRESHOLD,
    FORCED_DELOAD_FLOOR,
    TREND_INCREASING_THRESHOLD,
    TREND_DECREASING_THRESHOLD,
)



# resolve_adjustment — Tier 1: forced deload
class TestForcedDeload:
    def test_high_recovery_score_forces_deload_even_with_low_fatigue(self):
        """
        Session says "low fatigue, progress +10%", but muscle recovery is
        over the forced-deload threshold. Recovery must win — this is the
        entire reason Tier 1 exists (safety over a single good-feeling session).
        """
        decision = resolve_adjustment(
            fatigue_score=0.1,  # would normally be "low" -> +0.10
            muscle_recovery_score=0.85,  # > 0.8 threshold
            weekly_trend_adjustment=0.05,
        )
        assert decision.tier == "forced_deload"
        assert decision.final_adjustment <= FORCED_DELOAD_FLOOR

    def test_forced_deload_uses_session_adjustment_if_more_severe(self):
        """
        If the session's OWN fatigue-based deload is deeper than the floor,
        the deeper (more conservative) value should be kept — forced deload
        is a floor, not a fixed ceiling that could water down a worse
        session-level signal.
        """
        decision = resolve_adjustment(
            fatigue_score=0.95,  # "high" -> -0.175, same as floor here,
            muscle_recovery_score=0.9,
            weekly_trend_adjustment=0.05,
        )
        assert decision.tier == "forced_deload"
        assert decision.final_adjustment == FORCED_DELOAD_FLOOR

    def test_forced_deload_threshold_boundary_is_exclusive(self):
        """Exactly at the threshold should NOT trigger forced deload (strict >)."""
        decision = resolve_adjustment(
            fatigue_score=0.5,
            muscle_recovery_score=RECOVERY_FORCED_DELOAD_THRESHOLD,
            weekly_trend_adjustment=0.0,
        )
        assert decision.tier != "forced_deload"



# resolve_adjustment — Tier 2: well recovered -> weekly trend can drive progress
class TestWeeklyPriority:
    def test_well_recovered_lets_weekly_trend_override_low_session_signal(self):
        """
        A hard session (high fatigue -> session wants deload) but the
        muscle is well recovered AND the weekly trend is positive: weekly
        trend should be allowed to win since recovery capacity clearly
        supports it.
        """
        decision = resolve_adjustment(
            fatigue_score=0.75,  # "high" -> -0.175
            muscle_recovery_score=0.3,  # well recovered
            weekly_trend_adjustment=0.05,
            weekly_trend="increasing",
        )
        assert decision.tier == "weekly_priority"
        assert decision.final_adjustment == 0.05

    def test_well_recovered_keeps_session_if_session_is_more_favorable(self):
        """
        If session itself already suggests progress and weekly trend is
        flat/negative, the more favorable (higher) of the two should win —
        we take max(), not "always weekly" — a well-recovered muscle
        shouldn't be held back by a stale/negative weekly trend either.
        """
        decision = resolve_adjustment(
            fatigue_score=0.1,  # "low" -> +0.10
            muscle_recovery_score=0.2,
            weekly_trend_adjustment=-0.10,
            weekly_trend="decreasing",
        )
        assert decision.tier == "weekly_priority"
        assert decision.final_adjustment == 0.10

    def test_well_recovered_boundary_is_exclusive(self):
        """Exactly at the well-recovered threshold should NOT count as 'well recovered' (strict <)."""
        decision = resolve_adjustment(
            fatigue_score=0.5,
            muscle_recovery_score=RECOVERY_WELL_RECOVERED_THRESHOLD,
            weekly_trend_adjustment=0.05,
        )
        assert decision.tier != "weekly_priority"


# resolve_adjustment — Tier 3: moderate recovery -> session fatigue wins
class TestSessionPriority:
    def test_moderate_recovery_session_wins_over_conflicting_weekly_trend(self):
        """
        The core disagreement case from the design discussion: session says
        deload, weekly says progress, recovery is moderate. Session should win.
        """
        decision = resolve_adjustment(
            fatigue_score=0.75,  # "high" -> -0.175
            muscle_recovery_score=0.65,  # moderate zone
            weekly_trend_adjustment=0.05,
            weekly_trend="increasing",
        )
        assert decision.tier == "session_priority"
        assert decision.final_adjustment == pytest.approx(-0.175)

    def test_moderate_recovery_ignores_weekly_even_when_weekly_is_better(self):
        """
        Session priority means session ALWAYS wins in this tier, even if
        weekly trend would have suggested something more favorable — the
        acute signal is treated as safety-relevant, not just "whichever is best".
        """
        decision = resolve_adjustment(
            fatigue_score=0.1,  # "low" -> +0.10
            muscle_recovery_score=0.6,
            weekly_trend_adjustment=0.05,
        )
        assert decision.tier == "session_priority"
        assert decision.final_adjustment == pytest.approx(0.10)



# compute_trend
class TestComputeTrend:
    def test_no_history_returns_insufficient_data(self):
        result = compute_trend(current_volume=5000, past_volumes=[])
        assert result.trend == "insufficient_data"
        assert result.trend_adjustment == 0.0

    def test_increasing_trend(self):
        # baseline = 4000, current = 4400 -> +10% > 5% threshold
        result = compute_trend(current_volume=4400, past_volumes=[4000, 4000, 4000])
        assert result.trend == "increasing"
        assert result.trend_adjustment == 0.05

    def test_decreasing_trend(self):
        # baseline = 4000, current = 3400 -> -15% < -10% threshold
        result = compute_trend(current_volume=3400, past_volumes=[4000, 4000, 4000])
        assert result.trend == "decreasing"
        assert result.trend_adjustment == -0.10

    def test_stable_trend_within_band(self):
        # baseline = 4000, current = 4100 -> +2.5%, inside the stable band
        result = compute_trend(current_volume=4100, past_volumes=[4000, 4000])
        assert result.trend == "stable"
        assert result.trend_adjustment == 0.0

    def test_uses_mean_of_uneven_history(self):
        # baseline = mean(3000, 5000) = 4000; current 4600 -> +15% -> increasing
        result = compute_trend(current_volume=4600, past_volumes=[3000, 5000])
        assert result.trend == "increasing"

    def test_zero_baseline_does_not_divide_by_zero(self):
        result = compute_trend(current_volume=1000, past_volumes=[0, 0])
        assert result.trend == "insufficient_data"
        assert result.trend_adjustment == 0.0

    def test_boundary_exactly_at_increasing_threshold_is_not_increasing(self):
        # exactly +5% should NOT count as increasing (strict >)
        baseline = 4000
        current = baseline * (1 + TREND_INCREASING_THRESHOLD)
        result = compute_trend(current_volume=current, past_volumes=[baseline])
        assert result.trend == "stable"

    def test_boundary_exactly_at_decreasing_threshold_is_not_decreasing(self):
        # exactly -10% should NOT count as decreasing (strict <)
        baseline = 4000
        current = baseline * (1 + TREND_DECREASING_THRESHOLD)
        result = compute_trend(current_volume=current, past_volumes=[baseline])
        assert result.trend == "stable"


# Integration-style: full three-signal scenarios (documented in design discussion)
class TestDesignDiscussionScenarios:
    def test_the_original_conflict_example_from_design_discussion(self):
        """
        The exact scenario used to motivate Tier 3 during design:
        shoulders RPE 8 (session wants deload), muscle recovery moderate,
        weekly trend positive. Expect session (deload) to win.
        """
        decision = resolve_adjustment(
            fatigue_score=0.8,
            muscle_recovery_score=0.6,
            weekly_trend_adjustment=0.10,
            weekly_trend="increasing",
        )
        assert decision.tier == "session_priority"
        assert decision.final_adjustment < 0

    def test_reason_string_is_non_empty_and_mentions_tier_context(self):
        decision = resolve_adjustment(
            fatigue_score=0.5,
            muscle_recovery_score=0.9,
            weekly_trend_adjustment=0.0,
        )
        assert len(decision.reason) > 20
        assert "recovery" in decision.reason.lower()