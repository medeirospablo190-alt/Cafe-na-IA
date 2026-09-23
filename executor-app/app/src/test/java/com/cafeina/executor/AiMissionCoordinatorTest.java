package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionCoordinatorTest {
 @Test public void controllerLookupReturnsProjectScopedMission(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();AiMissionController c=new AiMissionController(s);c.create("m","p","g",1);c.start("m",2);assertEquals("p",c.get("m").projectId);assertEquals(AiMissionState.RUNNING,c.get("m").state);}
 @Test public void controllerLookupRejectsMissingMission(){AiMissionController c=new AiMissionController(new InMemoryAiMissionStore());assertThrows(IllegalArgumentException.class,()->c.get("missing"));}
}
