package com.cafeina.executor;
public final class AiLearningPromotionGate {
 public AiLearningPromotion prepare(AiLearningCandidate candidate){if(candidate==null)throw new IllegalArgumentException("candidate required");if(candidate.evidenceState!=AiResearchValidation.State.CORROBORATED)throw new IllegalStateException("candidate lacks corroborated evidence");return new AiLearningPromotion(candidate,KnowledgeState.VALIDATED);}
}
