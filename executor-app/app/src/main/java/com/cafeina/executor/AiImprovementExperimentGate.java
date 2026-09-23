package com.cafeina.executor;
public final class AiImprovementExperimentGate {
 public AiImprovementCandidate validate(AiImprovementCandidate testing,AiExperiment experiment){
  if(testing==null||experiment==null)throw new IllegalArgumentException("candidate and experiment required");
  if(testing.state!=AiImprovementCandidate.State.TESTING)throw new IllegalStateException("candidate must be testing");
  if(!testing.projectId.equals(experiment.projectId))throw new SecurityException("cross-project experiment denied");
  if(experiment.state!=AiExperiment.State.PASSED)throw new IllegalStateException("experiment has not passed");
  return testing.transition(AiImprovementCandidate.State.VALIDATED);
 }
}
