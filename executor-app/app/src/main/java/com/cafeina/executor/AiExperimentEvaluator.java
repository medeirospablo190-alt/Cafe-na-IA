package com.cafeina.executor;
import java.util.*;
public final class AiExperimentEvaluator {
 public AiExperiment evaluate(AiExperiment running,AiExperimentPlan plan,Map<String,Boolean> criteria,String evidence){
  if(running==null||plan==null||criteria==null)throw new IllegalArgumentException("evaluation fields required");if(running.state!=AiExperiment.State.RUNNING)throw new IllegalStateException("experiment must be running");if(!running.projectId.equals(plan.projectId))throw new SecurityException("cross-project plan denied");
  String ev=evidence==null||evidence.trim().isEmpty()?"evaluation evidence unavailable":evidence;
  for(String c:plan.acceptanceCriteria)if(!Boolean.TRUE.equals(criteria.get(c)))return running.fail(ev);
  return running.pass(ev);
 }
}
