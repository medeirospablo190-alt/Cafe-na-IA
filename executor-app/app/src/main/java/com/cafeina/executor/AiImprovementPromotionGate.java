package com.cafeina.executor;
public final class AiImprovementPromotionGate {
 public void requirePromotable(AiImprovementCandidate candidate){if(candidate==null)throw new IllegalArgumentException("candidate required");if(candidate.state!=AiImprovementCandidate.State.VALIDATED)throw new IllegalStateException("only validated improvement can be promoted");}
}
