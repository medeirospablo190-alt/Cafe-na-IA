package com.cafeina.executor;
public final class AiMissionController {
 private final AiMissionStore store;
 public AiMissionController(AiMissionStore store){if(store==null)throw new IllegalArgumentException("store required");this.store=store;}
 public AiMissionRecord get(String id){return require(id);}
 public AiMissionRecord create(String id,String projectId,String goal,long now){if(store.get(id)!=null)throw new IllegalArgumentException("mission exists");AiMissionRecord m=new AiMissionRecord(id,projectId,goal,AiMissionState.CREATED,now);store.save(m);return m;}
 public AiMissionRecord start(String id,long now){return move(id,AiMissionState.CREATED,AiMissionState.RUNNING,now);}
 public AiMissionRecord waitForUser(String id,long now){return move(id,AiMissionState.RUNNING,AiMissionState.WAITING_USER,now);}
 public AiMissionRecord resume(String id,long now){return move(id,AiMissionState.WAITING_USER,AiMissionState.RUNNING,now);}
 public AiMissionRecord complete(String id,long now){return move(id,AiMissionState.RUNNING,AiMissionState.COMPLETED,now);}
 public AiMissionRecord fail(String id,long now){AiMissionRecord m=require(id);if(m.state!=AiMissionState.RUNNING&&m.state!=AiMissionState.WAITING_USER)throw new IllegalStateException("mission cannot fail from "+m.state);return replace(m,AiMissionState.FAILED,now);}
 public AiMissionRecord cancel(String id,long now){AiMissionRecord m=require(id);if(isTerminal(m.state))throw new IllegalStateException("mission already terminal");return replace(m,AiMissionState.CANCELLED,now);}
 private AiMissionRecord move(String id,AiMissionState from,AiMissionState to,long now){AiMissionRecord m=require(id);if(m.state!=from)throw new IllegalStateException("expected "+from+" but was "+m.state);return replace(m,to,now);}
 private AiMissionRecord require(String id){AiMissionRecord m=store.get(id);if(m==null)throw new IllegalArgumentException("mission not found");return m;}
 private AiMissionRecord replace(AiMissionRecord m,AiMissionState state,long now){AiMissionRecord n=new AiMissionRecord(m.id,m.projectId,m.goal,state,now);store.save(n);return n;}
 private boolean isTerminal(AiMissionState s){return s==AiMissionState.COMPLETED||s==AiMissionState.FAILED||s==AiMissionState.CANCELLED;}
}
