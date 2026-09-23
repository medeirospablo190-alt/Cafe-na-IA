package com.cafeina.executor;
import java.util.*;
public final class AiMissionRecoveryPlanner {
 private final AiMissionStore store; private final AiMissionResumePolicy policy;
 public AiMissionRecoveryPlanner(AiMissionStore store,AiMissionResumePolicy policy){if(store==null||policy==null)throw new IllegalArgumentException("dependencies required");this.store=store;this.policy=policy;}
 public List<AiMissionRecord> resumable(String projectId,int limit){
  List<AiMissionRecord> out=new ArrayList<>();for(AiMissionRecord m:store.listForProject(projectId,limit))if(policy.decide(m).action==AiMissionResumeDecision.Action.RESUME)out.add(m);return Collections.unmodifiableList(out);
 }
 public List<AiMissionRecord> waitingForUser(String projectId,int limit){
  List<AiMissionRecord> out=new ArrayList<>();for(AiMissionRecord m:store.listForProject(projectId,limit))if(policy.decide(m).action==AiMissionResumeDecision.Action.WAIT_FOR_USER)out.add(m);return Collections.unmodifiableList(out);
 }
}
