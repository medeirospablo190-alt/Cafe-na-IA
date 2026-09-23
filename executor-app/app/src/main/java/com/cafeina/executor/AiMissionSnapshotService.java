package com.cafeina.executor;
public final class AiMissionSnapshotService {
 private final AiMissionRecovery recovery; private final AiToolExecutionJournal journal; private final AiMissionEventLog events;
 public AiMissionSnapshotService(AiMissionRecovery recovery,AiToolExecutionJournal journal,AiMissionEventLog events){if(recovery==null||journal==null||events==null)throw new IllegalArgumentException("dependencies required");this.recovery=recovery;this.journal=journal;this.events=events;}
 public AiMissionSnapshot capture(String missionId){AiMissionCheckpoint cp=recovery.checkpoint(missionId);return new AiMissionSnapshot(cp,journal.forMission(missionId),events.forMission(missionId));}
 public AiMissionRecord restore(AiMissionSnapshot snapshot){if(snapshot==null)throw new IllegalArgumentException("snapshot required");return recovery.restore(snapshot.checkpoint);}
}
