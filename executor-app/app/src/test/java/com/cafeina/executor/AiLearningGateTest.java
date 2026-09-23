package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiLearningGateTest {
 @Test public void corroboratedResearchCanBecomeCandidate(){AiResearchFinding f=new AiResearchFinding("s","c",Arrays.asList("a","b"));AiResearchValidation v=new AiResearchValidator().validate(f);AiLearningCandidate c=new AiLearningGate().fromResearch("p",v);assertEquals("p",c.projectId);assertEquals(AiResearchValidation.State.CORROBORATED,c.evidenceState);}
 @Test public void singleSourceCannotCrossLearningGate(){AiResearchValidation v=new AiResearchValidator().validate(new AiResearchFinding("s","c",Collections.singletonList("a")));assertThrows(IllegalStateException.class,()->new AiLearningGate().fromResearch("p",v));}
}
