package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionTest {
 @Test public void supportsUserWaitAndResume(){AiMission m=new AiMission("m","p","goal");m.start();m.waitForUser();assertEquals(AiMissionState.WAITING_USER,m.state());m.resume();m.complete();assertTrue(m.isTerminal());}
 @Test public void rejectsInvalidTransition(){AiMission m=new AiMission("m","p","goal");assertThrows(IllegalStateException.class,m::complete);}
 @Test public void runningCheckpointRestoresPausedWithoutReplaying(){AiMission m=new AiMission("m","p","goal");m.start();AiMission restored=AiMission.restore(m.snapshot());assertEquals(AiMissionState.WAITING_USER,restored.state());assertEquals("p",restored.projectId);assertThrows(IllegalStateException.class,restored::start);restored.resume();restored.complete();assertTrue(restored.isTerminal());}
 @Test public void terminalCheckpointRemainsTerminal(){AiMission m=new AiMission("m","p","goal");m.start();m.complete();AiMission restored=AiMission.restore(m.snapshot());assertEquals(AiMissionState.COMPLETED,restored.state());assertThrows(IllegalStateException.class,restored::resume);}
 @Test public void rejectsInvalidCheckpoint(){assertThrows(IllegalArgumentException.class,()->new AiMissionSnapshot("m","p","goal",null));assertThrows(IllegalArgumentException.class,()->AiMission.restore(null));}
}

