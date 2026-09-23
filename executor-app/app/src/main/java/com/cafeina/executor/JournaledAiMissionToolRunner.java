package com.cafeina.executor;
import java.util.*;
public final class JournaledAiMissionToolRunner {
 private final AiMissionStore missions; private final AiToolExecutor executor; private final AiToolExecutionPolicy policy; private final AiToolExecutionJournal journal;
 public JournaledAiMissionToolRunner(AiMissionStore missions,AiToolExecutor executor,AiToolExecutionPolicy policy,AiToolExecutionJournal journal){if(missions==null||executor==null||policy==null||journal==null)throw new IllegalArgumentException("dependencies required");this.missions=missions;this.executor=executor;this.policy=policy;this.journal=journal;}
 public List<AiToolResult> run(String missionId,AiToolPlan plan,long startedAt){
  AiMissionRecord m=missions.get(missionId);if(m==null)throw new IllegalArgumentException("mission not found");if(m.state!=AiMissionState.RUNNING)throw new IllegalStateException("mission must be running");policy.validate(plan,m.projectId);
  List<AiToolResult> out=new ArrayList<>();long t=startedAt;
  for(AiToolPlan.Step step:plan.steps()){AiToolResult r=executor.execute(step.toolName,step.request);out.add(r);journal.append(new AiToolExecutionRecord(m.id,m.projectId,step.toolName,r.success,r.output,t++));if(!r.success)break;}
  return Collections.unmodifiableList(out);
 }
}
