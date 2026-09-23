package com.cafeina.executor;
public final class AiMissionRecord {
 public final String id,projectId,goal; public final AiMissionState state; public final long updatedAt;
 public AiMissionRecord(String id,String projectId,String goal,AiMissionState state,long updatedAt){
  if(id==null||id.trim().isEmpty()||projectId==null||projectId.trim().isEmpty()||goal==null||goal.trim().isEmpty()||state==null)throw new IllegalArgumentException("mission fields required");
  this.id=id;this.projectId=projectId;this.goal=goal;this.state=state;this.updatedAt=updatedAt;
 }
}
