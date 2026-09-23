package com.cafeina.executor;
public final class AiMissionEvent {
 public enum Type { CREATED, STARTED, WAITING_USER, RESUMED, COMPLETED, FAILED, CANCELLED, TOOL_EXECUTED }
 public final String missionId,projectId; public final Type type; public final String detail; public final long createdAt;
 public AiMissionEvent(String missionId,String projectId,Type type,String detail,long createdAt){if(missionId==null||missionId.trim().isEmpty()||projectId==null||projectId.trim().isEmpty()||type==null)throw new IllegalArgumentException("event identity required");this.missionId=missionId;this.projectId=projectId;this.type=type;this.detail=detail==null?"":detail;this.createdAt=createdAt;}
}
