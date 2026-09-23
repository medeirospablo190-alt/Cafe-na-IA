package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiLearningPipelineTest {
 @Test public void storesOnlyAcceptedCandidateInItsProject(){AiLearningCandidateStore s=new AiLearningCandidateStore();AiLearningPipeline p=new AiLearningPipeline(new AiLearningGate(),s);AiResearchValidation ok=new AiResearchValidator().validate(new AiResearchFinding("s","c",Arrays.asList("a","b")));p.acceptResearch("p",ok);assertEquals(1,s.forProject("p").size());assertTrue(s.forProject("other").isEmpty());}
 @Test public void rejectedGateLeavesStoreUntouched(){AiLearningCandidateStore s=new AiLearningCandidateStore();AiLearningPipeline p=new AiLearningPipeline(new AiLearningGate(),s);AiResearchValidation weak=new AiResearchValidator().validate(new AiResearchFinding("s","c",Collections.singletonList("a")));assertThrows(IllegalStateException.class,()->p.acceptResearch("p",weak));assertTrue(s.forProject("p").isEmpty());}
}
