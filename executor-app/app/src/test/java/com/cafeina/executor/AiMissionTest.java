package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionTest {
 @Test public void supportsUserWaitAndResume(){AiMission m=new AiMission("m","p","goal");m.start();m.waitForUser();assertEquals(AiMissionState.WAITING_USER,m.state());m.resume();m.complete();assertTrue(m.isTerminal());}
 @Test public void rejectsInvalidTransition(){AiMission m=new AiMission("m","p","goal");assertThrows(IllegalStateException.class,m::complete);}
}
