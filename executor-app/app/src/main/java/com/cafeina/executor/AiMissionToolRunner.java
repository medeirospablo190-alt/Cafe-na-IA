package com.cafeina.executor;
import java.util.*;
public final class AiMissionToolRunner {
 private final AiMissionStore missions; private final AiToolPlanRunner runner; private final AiToolExecutionPolicy policy;
 public AiMissionToolRunner(AiMissionStore missions,AiToolPlanRunner runner,AiToolExecutionPolicy policy){
  if(missions==null||runner==null||policy==null)throw new IllegalArgumentException("dependencies required");this.missions=missions;this.runner=runner;this.policy=policy;
 }
 public List<AiToolResult> run(String missionId,AiToolPlan plan){
  AiMissionRecord mission=missions.get(missionId);if(mission==null)throw new IllegalArgumentException("mission not found");
  if(mission.state!=AiMissionState.RUNNING)throw new IllegalStateException("mission must be running");
  policy.validate(plan,mission.projectId);
  return runner.run(plan);
 }
}
