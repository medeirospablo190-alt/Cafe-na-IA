package com.cafeina.executor;
public final class AiLearningGate {
 public AiLearningCandidate fromResearch(String projectId,AiResearchValidation validation){
  if(validation==null)throw new IllegalArgumentException("validation required");
  if(validation.state!=AiResearchValidation.State.CORROBORATED)throw new IllegalStateException("research is not corroborated");
  return new AiLearningCandidate(projectId,validation.finding.subject,validation.finding.content,validation.state);
 }
}
