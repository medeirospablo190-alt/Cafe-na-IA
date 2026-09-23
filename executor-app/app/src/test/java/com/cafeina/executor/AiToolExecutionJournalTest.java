package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiToolExecutionJournalTest {
 @Test public void filtersWithoutLeakingOtherProjects(){AiToolExecutionJournal j=new AiToolExecutionJournal();j.append(new AiToolExecutionRecord("m1","p","a",true,"ok",1));j.append(new AiToolExecutionRecord("m2","other","b",false,"no",2));assertEquals(1,j.forProject("p").size());assertEquals("m1",j.forProject("p").get(0).missionId);assertEquals(1,j.forMission("m2").size());assertThrows(UnsupportedOperationException.class,()->j.forProject("p").clear());}
}
