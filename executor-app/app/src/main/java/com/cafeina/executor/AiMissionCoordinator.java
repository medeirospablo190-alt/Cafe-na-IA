package com.cafeina.executor;
import java.util.*;
public final class AiMissionCoordinator {
 private final AiMissionController missions; private final AiConversationCoordinator chat; private final AiMissionToolRunner tools;
 public AiMissionCoordinator(AiMissionController missions,AiConversationCoordinator chat,AiMissionToolRunner tools){if(missions==null||chat==null||tools==null)throw new IllegalArgumentException("dependencies required");this.missions=missions;this.chat=chat;this.tools=tools;}
 public CafeinaAiCore.Response converse(String missionId,String projectId,String message,List<String> capabilities,long userAt,long assistantAt){
  AiMissionRecord m=missions.get(missionId);
  if(!m.projectId.equals(projectId))throw new SecurityException("mission project mismatch");
  if(m.state!=AiMissionState.RUNNING&&m.state!=AiMissionState.WAITING_USER)throw new IllegalStateException("mission cannot converse from "+m.state);
  return chat.send(projectId,message,capabilities,userAt,assistantAt);
 }
 public List<AiToolResult> execute(String missionId,AiToolPlan plan){return tools.run(missionId,plan);}
}
