package com.cafeina.executor;
public final class AiMissionResumePolicy {
 public AiMissionResumeDecision decide(AiMissionRecord mission){
  if(mission==null)throw new IllegalArgumentException("mission required");
  switch(mission.state){
   case RUNNING:return new AiMissionResumeDecision(AiMissionResumeDecision.Action.RESUME,"mission was running");
   case WAITING_USER:return new AiMissionResumeDecision(AiMissionResumeDecision.Action.WAIT_FOR_USER,"mission requires user input");
   case CREATED:return new AiMissionResumeDecision(AiMissionResumeDecision.Action.RESUME,"mission has not started");
   default:return new AiMissionResumeDecision(AiMissionResumeDecision.Action.DO_NOT_RESUME,"mission is terminal");
  }
 }
}
