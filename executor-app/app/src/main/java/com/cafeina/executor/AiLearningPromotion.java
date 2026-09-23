package com.cafeina.executor;
public final class AiLearningPromotion {
 public final AiLearningCandidate candidate; public final KnowledgeState targetState;
 public AiLearningPromotion(AiLearningCandidate candidate,KnowledgeState targetState){if(candidate==null||targetState==null)throw new IllegalArgumentException("promotion fields required");if(targetState!=KnowledgeState.VALIDATED)throw new IllegalArgumentException("research learning may enter only as VALIDATED");this.candidate=candidate;this.targetState=targetState;}
}
