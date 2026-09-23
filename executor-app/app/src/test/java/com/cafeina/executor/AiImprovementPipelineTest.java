package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiImprovementPipelineTest {
 @Test public void recordsLifecycleWithoutCrossProjectLeak(){AiImprovementStore s=new AiImprovementStore();AiImprovementPipeline p=new AiImprovementPipeline(s);AiImprovementCandidate c=p.propose("p","x");c=p.beginTesting(c);c=p.validate(c);p.propose("other","y");assertEquals(3,s.forProject("p").size());assertEquals(AiImprovementCandidate.State.VALIDATED,s.forProject("p").get(2).state);assertEquals(1,s.forProject("other").size());}
 @Test public void promotionRequiresValidatedState(){AiImprovementPromotionGate g=new AiImprovementPromotionGate();AiImprovementCandidate c=new AiImprovementCandidate("p","x",AiImprovementCandidate.State.PROPOSED);assertThrows(IllegalStateException.class,()->g.requirePromotable(c));g.requirePromotable(c.transition(AiImprovementCandidate.State.TESTING).transition(AiImprovementCandidate.State.VALIDATED));}
}
