package com.cafeina.executor;
public final class AiToolExecutionPolicy {
 private final int maxSteps;
 public AiToolExecutionPolicy(int maxSteps){if(maxSteps<1||maxSteps>100)throw new IllegalArgumentException("maxSteps must be 1..100");this.maxSteps=maxSteps;}
 public void validate(AiToolPlan plan,String projectId){
  if(plan==null||projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("plan and project required");
  if(plan.steps().size()>maxSteps)throw new IllegalArgumentException("tool plan exceeds max steps");
  for(AiToolPlan.Step step:plan.steps())if(!projectId.equals(step.request.projectId))throw new SecurityException("cross-project tool step denied");
 }
}
