package com.cafeina.executor;
import java.util.*;
public final class AiToolExecutionJournal {
 private final List<AiToolExecutionRecord> records=new ArrayList<>();
 public synchronized void append(AiToolExecutionRecord r){if(r==null)throw new IllegalArgumentException("record required");records.add(r);}
 public synchronized List<AiToolExecutionRecord> forMission(String missionId){if(missionId==null||missionId.trim().isEmpty())throw new IllegalArgumentException("missionId required");List<AiToolExecutionRecord> out=new ArrayList<>();for(AiToolExecutionRecord r:records)if(missionId.equals(r.missionId))out.add(r);return Collections.unmodifiableList(out);}
 public synchronized List<AiToolExecutionRecord> forProject(String projectId){if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId required");List<AiToolExecutionRecord> out=new ArrayList<>();for(AiToolExecutionRecord r:records)if(projectId.equals(r.projectId))out.add(r);return Collections.unmodifiableList(out);}
}
