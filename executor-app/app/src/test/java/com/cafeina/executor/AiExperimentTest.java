package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiExperimentTest {
 @Test public void experimentRequiresEvidenceToPass(){AiExperiment e=new AiExperiment("e","p","h",AiExperiment.State.PLANNED,null).start();assertThrows(IllegalArgumentException.class,()->e.pass(""));assertEquals(AiExperiment.State.PASSED,e.pass("test-result-42").state);}
 @Test public void improvementValidationRequiresPassedSameProjectExperiment(){AiImprovementCandidate c=new AiImprovementCandidate("p","x",AiImprovementCandidate.State.PROPOSED).transition(AiImprovementCandidate.State.TESTING);AiExperimentGateChecks(c);}
 private void AiExperimentGateChecks(AiImprovementCandidate c){AiImprovementExperimentGate g=new AiImprovementExperimentGate();AiExperiment running=new AiExperiment("e","p","h",AiExperiment.State.PLANNED,null).start();assertThrows(IllegalStateException.class,()->g.validate(c,running));AiExperiment passed=running.pass("ok");assertEquals(AiImprovementCandidate.State.VALIDATED,g.validate(c,passed).state);AiExperiment foreign=new AiExperiment("x","other","h",AiExperiment.State.PLANNED,null).start().pass("ok");assertThrows(SecurityException.class,()->g.validate(c,foreign));}
 @Test public void storeRejectsProjectIdentityChange(){AiExperimentStore s=new AiExperimentStore();s.save(new AiExperiment("e","p","h",AiExperiment.State.PLANNED,null));assertThrows(SecurityException.class,()->s.save(new AiExperiment("e","other","h",AiExperiment.State.PLANNED,null)));}
}
