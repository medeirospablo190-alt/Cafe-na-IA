package com.cafeina.executor;
public final class AiLearningPipeline {
 private final AiLearningGate gate; private final AiLearningCandidateStore store;
 public AiLearningPipeline(AiLearningGate gate,AiLearningCandidateStore store){if(gate==null||store==null)throw new IllegalArgumentException("dependencies required");this.gate=gate;this.store=store;}
 public AiLearningCandidate acceptResearch(String projectId,AiResearchValidation validation){AiLearningCandidate c=gate.fromResearch(projectId,validation);store.add(c);return c;}
}
