package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiExperimentEvaluatorTest {
 @Test public void allCriteriaRequiredForPass(){AiExperiment e=new AiExperiment("e","p","h",AiExperiment.State.PLANNED,null).start();AiExperimentPlan p=new AiExperimentPlan("p","h",Arrays.asList("tests","no-regression"));Map<String,Boolean> c=new HashMap<>();c.put("tests",true);c.put("no-regression",true);assertEquals(AiExperiment.State.PASSED,new AiExperimentEvaluator().evaluate(e,p,c,"suite green").state);c.put("no-regression",false);assertEquals(AiExperiment.State.FAILED,new AiExperimentEvaluator().evaluate(e,p,c,"regression").state);}
 @Test public void planCriteriaAreImmutable(){List<String> c=new ArrayList<>();c.add("x");AiExperimentPlan p=new AiExperimentPlan("p","h",c);c.clear();assertEquals(1,p.acceptanceCriteria.size());assertThrows(UnsupportedOperationException.class,()->p.acceptanceCriteria.clear());}
}
