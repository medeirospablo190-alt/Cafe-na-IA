package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionRecoveryTest {
 @Test public void restoresCheckpointState(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();s.save(new AiMissionRecord("m","p","g",AiMissionState.WAITING_USER,5));AiMissionRecovery r=new AiMissionRecovery(s);AiMissionCheckpoint cp=r.checkpoint("m");s.save(new AiMissionRecord("m","p","g",AiMissionState.RUNNING,6));r.restore(cp);assertEquals(AiMissionState.WAITING_USER,s.get("m").state);assertEquals(5,s.get("m").updatedAt);}
 @Test public void refusesCheckpointAcrossProjectIdentity(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();s.save(new AiMissionRecord("m","p","g",AiMissionState.RUNNING,1));AiMissionRecovery r=new AiMissionRecovery(s);AiMissionCheckpoint cp=new AiMissionCheckpoint(new AiMissionRecord("m","other","g",AiMissionState.RUNNING,1));assertThrows(SecurityException.class,()->r.restore(cp));}
}
