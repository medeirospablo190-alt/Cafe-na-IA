package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiImprovementCandidateTest {
 @Test public void improvementRequiresTestingBeforeValidation(){AiImprovementCandidate c=new AiImprovementCandidate("p","improve planner",AiImprovementCandidate.State.PROPOSED);assertThrows(IllegalStateException.class,()->c.transition(AiImprovementCandidate.State.VALIDATED));assertEquals(AiImprovementCandidate.State.VALIDATED,c.transition(AiImprovementCandidate.State.TESTING).transition(AiImprovementCandidate.State.VALIDATED).state);}
 @Test public void validatedCandidateCannotMutateFurther(){AiImprovementCandidate c=new AiImprovementCandidate("p","x",AiImprovementCandidate.State.TESTING).transition(AiImprovementCandidate.State.VALIDATED);assertThrows(IllegalStateException.class,()->c.transition(AiImprovementCandidate.State.TESTING));}
}
