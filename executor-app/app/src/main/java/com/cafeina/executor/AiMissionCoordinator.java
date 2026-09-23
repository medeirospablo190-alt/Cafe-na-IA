package com.cafeina.executor;
import java.util.*;
public final class AiMissionCoordinator {
 private final AiMissionController missions; private final AiConversationCoordinator chat; private final AiMissionToolRunner tools;
 public AiMissionCoordinator(AiMissionController missions,AiConversationCoordinator chat,AiMissionToolRunner tools){if(missions==null||chat==null||tools==null)throw new IllegalArgumentException("dependencies required");this.missions=missions;this.chat=chat;this.tools=tools;}
 public CafeinaAiCore.Response converse(String missionId,String projectId,String message,List<String> capabilities,long userAt,long assistantAt){
  AiMissionRecord m=missionsRecord(missionId);
  if(!m.projectId.equals(projectId))throw new SecurityException("mission project mismatch");
  if(m.state!=AiMissionState.RUNNING&&m.state!=AiMissionState.WAITING_USER)throw new IllegalStateException("mission cannot converse from "+m.state);
  return chat.send(projectId,message,capabilities,userAt,assistantAt);
 }
 private AiMissionRecord missionsRecord(String id){
  try{java.lang.reflect.Field f=AiMissionController.class.getDeclaredField("store");f.setAccessible(true);AiMissionStore s=(AiMissionStore)f.get(missions);AiMissionRecord m=s.get(id);if(m==null)throw new IllegalArgumentException("mission not found");return m;}catch(ReflectiveOperationException e){throw new IllegalStateException(e);}
 }
 public java.util.List<AiToolResult> execute(String missionId,AiToolPlan plan){return tools.run(missionId,plan);}
}
