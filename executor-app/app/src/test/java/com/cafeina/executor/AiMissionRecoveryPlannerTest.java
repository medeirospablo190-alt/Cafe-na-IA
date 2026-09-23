package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiMissionRecoveryPlannerTest {
 @Test public void separatesAutonomousResumeFromUserDependency(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();s.save(new AiMissionRecord("run","p","g",AiMissionState.RUNNING,4));s.save(new AiMissionRecord("wait","p","g",AiMissionState.WAITING_USER,3));s.save(new AiMissionRecord("done","p","g",AiMissionState.COMPLETED,2));s.save(new AiMissionRecord("foreign","other","g",AiMissionState.RUNNING,5));AiMissionRecoveryPlanner p=new AiMissionRecoveryPlanner(s,new AiMissionResumePolicy());assertEquals(1,p.resumable("p",10).size());assertEquals("run",p.resumable("p",10).get(0).id);assertEquals("wait",p.waitingForUser("p",10).get(0).id);}
 @Test public void terminalStatesDoNotResume(){AiMissionResumePolicy p=new AiMissionResumePolicy();assertEquals(AiMissionResumeDecision.Action.DO_NOT_RESUME,p.decide(new AiMissionRecord("m","p","g",AiMissionState.FAILED,1)).action);assertEquals(AiMissionResumeDecision.Action.DO_NOT_RESUME,p.decide(new AiMissionRecord("m","p","g",AiMissionState.CANCELLED,1)).action);}
}
