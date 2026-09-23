package com.cafeina.executor;
import java.util.Collections;
public final class AiConversationCoordinator {
 private final CafeinaAiCore core; private final ConversationRepository conversations;
 public AiConversationCoordinator(CafeinaAiCore core,ConversationRepository conversations){
  if(core==null||conversations==null)throw new IllegalArgumentException("dependencies required");this.core=core;this.conversations=conversations;
 }
 public CafeinaAiCore.Response send(String projectId,String message,long userAt,long assistantAt){
  conversations.append(projectId,"user",message,userAt);
  CafeinaAiCore.Response response=core.handle(new CafeinaAiCore.Request(projectId,message,Collections.emptyList()));
  conversations.append(projectId,"assistant",response.message,assistantAt);
  return response;
 }
}
