package com.cafeina.executor;
public final class AiMissionRecovery {
 private final AiMissionStore store;
 public AiMissionRecovery(AiMissionStore store){if(store==null)throw new IllegalArgumentException("store required");this.store=store;}
 public AiMissionCheckpoint checkpoint(String id){AiMissionRecord m=store.get(id);if(m==null)throw new IllegalArgumentException("mission not found");return new AiMissionCheckpoint(m);}
 public AiMissionRecord restore(AiMissionCheckpoint checkpoint){if(checkpoint==null)throw new IllegalArgumentException("checkpoint required");AiMissionRecord current=store.get(checkpoint.missionId);if(current!=null&&!current.projectId.equals(checkpoint.projectId))throw new SecurityException("checkpoint project mismatch");AiMissionRecord restored=checkpoint.restore();store.save(restored);return restored;}
}
