from fastapi import APIRouter
from pydantic import BaseModel
from typing import Literal, Optional

from services.adaptation_engine import compute_trend, resolve_adjustment

router = APIRouter()


class ProposalInput(BaseModel):
    proposal_id: str
    fatigue_score: Optional[float] = None
    muscle_recovery_score: float
    trigger: Literal["session", "skip"] = "session"
    days_since_last_trained: Optional[int] = None


class CommitAdaptationsRequest(BaseModel):
    current_volume: float
    past_volumes: list[float]
    proposals: list[ProposalInput]
    # Whole-plan property: true if this weekly run lands
    is_deload_week: bool = False


class ResolvedProposal(BaseModel):
    proposal_id: str
    final_adjustment: float
    tier: str
    reason: str


class CommitAdaptationsResponse(BaseModel):
    trend: str
    trend_adjustment: float
    resolved_proposals: list[ResolvedProposal]


@router.post("/commit-adaptations", response_model=CommitAdaptationsResponse)
def commit_adaptations(req: CommitAdaptationsRequest):
    trend_result = compute_trend(
        current_volume=req.current_volume,
        past_volumes=req.past_volumes,
    )

    resolved = []
    for proposal in req.proposals:
        decision = resolve_adjustment(
            fatigue_score=proposal.fatigue_score,
            muscle_recovery_score=proposal.muscle_recovery_score,
            weekly_trend_adjustment=trend_result.trend_adjustment,
            weekly_trend=trend_result.trend,
            is_deload_week=req.is_deload_week,
            trigger=proposal.trigger,
            days_since_last_trained=proposal.days_since_last_trained,
        )
        resolved.append(
            ResolvedProposal(
                proposal_id=proposal.proposal_id,
                final_adjustment=decision.final_adjustment,
                tier=decision.tier,
                reason=decision.reason,
            )
        )

    return CommitAdaptationsResponse(
        trend=trend_result.trend,
        trend_adjustment=trend_result.trend_adjustment,
        resolved_proposals=resolved,
    )


def test_skip_proposal_accepts_null_fatigue_score():
    # days_since_last_trained omitted entirely — treated conservatively as
    # a long break (same as > 28 days), not as "no reduction".
    req = CommitAdaptationsRequest(
        current_volume=100,
        past_volumes=[100, 100, 100],
        proposals=[
            ProposalInput(
                proposal_id="proposal-1",
                fatigue_score=None,
                muscle_recovery_score=0.4,
                trigger="skip",
            )
        ],
    )

    res = commit_adaptations(req)

    assert res.resolved_proposals[0].tier == "return_from_break"
    assert res.resolved_proposals[0].final_adjustment == -0.175


def _skip_proposal(days_since_last_trained):
    return CommitAdaptationsRequest(
        current_volume=100,
        past_volumes=[100, 100, 100],
        proposals=[
            ProposalInput(
                proposal_id="proposal-1",
                fatigue_score=None,
                muscle_recovery_score=0.4,
                trigger="skip",
                days_since_last_trained=days_since_last_trained,
            )
        ],
    )


def test_skip_proposal_at_exactly_28_days_applies_no_reduction():
    res = commit_adaptations(_skip_proposal(28))

    assert res.resolved_proposals[0].tier == "return_from_break"
    assert res.resolved_proposals[0].final_adjustment == 0.0


def test_skip_proposal_at_29_days_applies_full_reduction():
    res = commit_adaptations(_skip_proposal(29))

    assert res.resolved_proposals[0].tier == "return_from_break"
    assert res.resolved_proposals[0].final_adjustment == -0.175
