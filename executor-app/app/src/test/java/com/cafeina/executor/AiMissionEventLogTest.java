package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionEventLogTest {
 @Test public void eventQueriesRemainScoped(){AiMissionEventLog l=new AiMissionEventLog();l.append(new AiMissionEvent("m","p",AiMissionEvent.Type.STARTED,"",1));l.append(new AiMissionEvent("x","other",AiMissionEvent.Type.STARTED,"",2));assertEquals(1,l.forProject("p").size());assertEquals("m",l.forProject("p").get(0).missionId);assertEquals(1,l.forMission("x").size());}
}
