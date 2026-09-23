package com.cafeina.executor;

public final class AiMissionController {
 private final AiMissionStore store;
 public AiMissionController(AiMissionStore store){if(store==null)throw new IllegalArgumentException("store required");this.store=store;}
 public AiMissionRecord create(String id,String projectId,String goal,long now){AiMissionRecord m=new AiMissionRecord(id,projectId,goal,AiMissionState.CREATED,now);store.save(m);return m;}
 public AiMissionRecord start(String id,long now){return move(id,AiMissionState.CREATED,AiMissionState.RUNNING,now);}
 public AiMissionRecord waitForUser(String id,long now){return move(id,AiMissionState.RUNNING,AiMissionState.WAITING_USER,now);}
 public AiMissionRecord resume(String id,long now){return move(id,AiMissionState.WAITING_USER,AiMissionState.RUNNING,now);}
 public AiMissionRecord complete(String id,long now){return move(id,AiMissionState.RUNNING,AiMissionState.COMPLETED,now);}
 private AiMissionRecord move(String id,AiMissionState from,AiMissionState to,long now){AiMissionRecord old=store.get(id);if(old==null)throw new IllegalArgumentException("mission not found");if(old.state!=from)throw new IllegalStateException("expected "+from+" but was "+old.state);AiMissionRecord next=new AiMissionRecord(old.id,old.projectId,old.goal,to,now);store.save(next);return next;}
}
