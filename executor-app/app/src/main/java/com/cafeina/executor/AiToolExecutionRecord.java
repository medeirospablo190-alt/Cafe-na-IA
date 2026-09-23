package com.cafeina.executor;
public final class AiToolExecutionRecord {
 public final String missionId,projectId,toolName; public final boolean success; public final String output; public final long createdAt;
 public AiToolExecutionRecord(String missionId,String projectId,String toolName,boolean success,String output,long createdAt){
  if(missionId==null||missionId.trim().isEmpty()||projectId==null||projectId.trim().isEmpty()||toolName==null||toolName.trim().isEmpty())throw new IllegalArgumentException("execution identity required");
  this.missionId=missionId;this.projectId=projectId;this.toolName=toolName;this.success=success;this.output=output==null?"":output;this.createdAt=createdAt;
 }
}
