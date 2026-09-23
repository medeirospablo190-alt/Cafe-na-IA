package com.cafeina.executor;
import java.util.*;
public final class AiToolPlanRunner {
 private final AiToolExecutor executor;
 public AiToolPlanRunner(AiToolExecutor executor){if(executor==null)throw new IllegalArgumentException("executor required");this.executor=executor;}
 public List<AiToolResult> run(AiToolPlan plan){
  if(plan==null)throw new IllegalArgumentException("plan required");
  List<AiToolResult> results=new ArrayList<>();
  for(AiToolPlan.Step step:plan.steps()){AiToolResult result=executor.execute(step.toolName,step.request);results.add(result);if(!result.success)break;}
  return Collections.unmodifiableList(results);
 }
}
