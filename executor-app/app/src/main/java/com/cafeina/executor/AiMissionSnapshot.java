package com.cafeina.executor;
import java.util.*;
public final class AiMissionSnapshot {
 public final AiMissionCheckpoint checkpoint; public final List<AiToolExecutionRecord> executions; public final List<AiMissionEvent> events;
 public AiMissionSnapshot(AiMissionCheckpoint checkpoint,List<AiToolExecutionRecord> executions,List<AiMissionEvent> events){if(checkpoint==null)throw new IllegalArgumentException("checkpoint required");this.checkpoint=checkpoint;this.executions=Collections.unmodifiableList(new ArrayList<>(executions==null?Collections.emptyList():executions));this.events=Collections.unmodifiableList(new ArrayList<>(events==null?Collections.emptyList():events));}
}
