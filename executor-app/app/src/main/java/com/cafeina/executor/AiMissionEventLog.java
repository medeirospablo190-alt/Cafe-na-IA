package com.cafeina.executor;
import java.util.*;
public final class AiMissionEventLog {
 private final List<AiMissionEvent> events=new ArrayList<>();
 public synchronized void append(AiMissionEvent e){if(e==null)throw new IllegalArgumentException("event required");events.add(e);}
 public synchronized List<AiMissionEvent> forMission(String missionId){List<AiMissionEvent> out=new ArrayList<>();for(AiMissionEvent e:events)if(e.missionId.equals(missionId))out.add(e);return Collections.unmodifiableList(out);}
 public synchronized List<AiMissionEvent> forProject(String projectId){List<AiMissionEvent> out=new ArrayList<>();for(AiMissionEvent e:events)if(e.projectId.equals(projectId))out.add(e);return Collections.unmodifiableList(out);}
}
