package com.cafeina.executor;
import java.util.*;
public final class AiMissionCheckpoint {
 public final String missionId,projectId,goal; public final AiMissionState state; public final long updatedAt;
 public AiMissionCheckpoint(AiMissionRecord m){if(m==null)throw new IllegalArgumentException("mission required");missionId=m.id;projectId=m.projectId;goal=m.goal;state=m.state;updatedAt=m.updatedAt;}
 public AiMissionRecord restore(){return new AiMissionRecord(missionId,projectId,goal,state,updatedAt);}
}
