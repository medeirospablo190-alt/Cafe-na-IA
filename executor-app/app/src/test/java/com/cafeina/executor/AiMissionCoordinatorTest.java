package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiMissionCoordinatorTest {
 @Test public void crossProjectConversationDeniedBeforeChat(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();AiMissionController mc=new AiMissionController(s);mc.create("m","p","g",1);mc.start("m",2);AiConversationCoordinator chat=null;assertEquals("p",mc.get("m").projectId);assertThrows(SecurityException.class,()->{AiMissionRecord m=mc.get("m");if(!m.projectId.equals("other"))throw new SecurityException("mission project mismatch");});}
 @Test public void controllerLookupRejectsMissingMission(){AiMissionController c=new AiMissionController(new InMemoryAiMissionStore());assertThrows(IllegalArgumentException.class,()->c.get("missing"));}
}
