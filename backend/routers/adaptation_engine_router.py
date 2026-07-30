from fastapi import APIRouter
from pydantic import BaseModel

from services.adaptation_engine import compute_trend, resolve_adjustment

router = APIRouter()


class ProposalInput(BaseModel):
    proposal_id: str
    fatigue_score: float
    muscle_recovery_score: float


class CommitAdaptationsRequest(BaseModel):
    current_volume: float
    past_volumes: list[float]
    proposals: list[ProposalInput]


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