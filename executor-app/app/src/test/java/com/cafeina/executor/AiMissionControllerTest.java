package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionControllerTest {
 @Test public void persistsFullWaitResumeLifecycle(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();AiMissionController c=new AiMissionController(s);c.create("m","p","goal",1);c.start("m",2);c.waitForUser("m",3);assertEquals(AiMissionState.WAITING_USER,s.get("m").state);c.resume("m",4);c.complete("m",5);assertEquals(AiMissionState.COMPLETED,s.get("m").state);}
 @Test public void failAllowedFromWaiting(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();AiMissionController c=new AiMissionController(s);c.create("m","p","goal",1);c.start("m",2);c.waitForUser("m",3);c.fail("m",4);assertEquals(AiMissionState.FAILED,s.get("m").state);}
 @Test public void terminalMissionCannotCancel(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();AiMissionController c=new AiMissionController(s);c.create("m","p","goal",1);c.start("m",2);c.complete("m",3);assertThrows(IllegalStateException.class,()->c.cancel("m",4));}
 @Test public void duplicateMissionIdRejected(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();AiMissionController c=new AiMissionController(s);c.create("m","p","goal",1);assertThrows(IllegalArgumentException.class,()->c.create("m","p","again",2));}
}
