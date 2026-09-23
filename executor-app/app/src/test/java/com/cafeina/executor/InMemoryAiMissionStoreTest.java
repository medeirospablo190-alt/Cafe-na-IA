package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class InMemoryAiMissionStoreTest {
 @Test public void isolatesProjectsAndOrdersNewest(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();s.save(new AiMissionRecord("a","p","one",AiMissionState.CREATED,1));s.save(new AiMissionRecord("b","p","two",AiMissionState.RUNNING,2));s.save(new AiMissionRecord("x","other","x",AiMissionState.CREATED,3));assertEquals("b",s.listForProject("p",10).get(0).id);assertEquals(2,s.listForProject("p",10).size());}
 @Test public void missionCannotMoveAcrossProjects(){InMemoryAiMissionStore s=new InMemoryAiMissionStore();s.save(new AiMissionRecord("a","p","one",AiMissionState.CREATED,1));assertThrows(IllegalArgumentException.class,()->s.save(new AiMissionRecord("a","other","one",AiMissionState.CREATED,2)));}
}
