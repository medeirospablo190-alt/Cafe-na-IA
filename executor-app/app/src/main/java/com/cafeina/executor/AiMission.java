package com.cafeina.executor;

public final class AiMission {
 public final String id; public final String projectId; public final String goal; private AiMissionState state;
 public AiMission(String id,String projectId,String goal){
  require(id,"id");require(projectId,"projectId");require(goal,"goal");this.id=id;this.projectId=projectId;this.goal=goal;state=AiMissionState.CREATED;
 }
 /** Restore a checkpoint without re-running an interrupted mission. */
 public static AiMission restore(AiMissionSnapshot checkpoint){
  if(checkpoint==null)throw new IllegalArgumentException("checkpoint is required");
  AiMission mission=new AiMission(checkpoint.id,checkpoint.projectId,checkpoint.goal);
  // An interrupted execution must not silently resume or repeat side effects.
  mission.state=checkpoint.state==AiMissionState.RUNNING?AiMissionState.WAITING_USER:checkpoint.state;
  return mission;
 }
 /** Copy only for a live, state-checked transition; never use for process recovery. */
 AiMission copyForLiveTransition(){AiMission copy=new AiMission(id,projectId,goal);copy.state=state;return copy;}
 public AiMissionSnapshot snapshot(){return new AiMissionSnapshot(id,projectId,goal,state);}
 public AiMissionState state(){return state;}
 public void start(){transition(AiMissionState.CREATED,AiMissionState.RUNNING);}
 public void waitForUser(){transition(AiMissionState.RUNNING,AiMissionState.WAITING_USER);}
 public void resume(){transition(AiMissionState.WAITING_USER,AiMissionState.RUNNING);}
 public void complete(){transition(AiMissionState.RUNNING,AiMissionState.COMPLETED);}
 public void fail(){if(state!=AiMissionState.RUNNING&&state!=AiMissionState.WAITING_USER)throw new IllegalStateException("mission cannot fail from "+state);state=AiMissionState.FAILED;}
 public void cancel(){if(isTerminal())throw new IllegalStateException("terminal mission");state=AiMissionState.CANCELLED;}
 public boolean isTerminal(){return state==AiMissionState.COMPLETED||state==AiMissionState.FAILED||state==AiMissionState.CANCELLED;}
 private void transition(AiMissionState from,AiMissionState to){if(state!=from)throw new IllegalStateException("expected "+from+" but was "+state);state=to;}
 private static void require(String v,String n){if(v==null||v.trim().isEmpty())throw new IllegalArgumentException(n+" is required");}
}
