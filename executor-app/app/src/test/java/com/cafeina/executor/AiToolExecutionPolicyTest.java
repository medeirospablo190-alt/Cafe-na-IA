package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiToolExecutionPolicyTest {
 private AiToolPlan.Step step(String p){return new AiToolPlan.Step("x",new AiToolRequest(p,null));}
 @Test public void rejectsCrossProjectStep(){AiToolPlan p=new AiToolPlan(Collections.singletonList(step("other")));assertThrows(SecurityException.class,()->new AiToolExecutionPolicy(5).validate(p,"mission"));}
 @Test public void rejectsOversizedPlan(){AiToolPlan p=new AiToolPlan(Arrays.asList(step("p"),step("p")));assertThrows(IllegalArgumentException.class,()->new AiToolExecutionPolicy(1).validate(p,"p"));}
 @Test public void acceptsBoundedSameProjectPlan(){new AiToolExecutionPolicy(2).validate(new AiToolPlan(Collections.singletonList(step("p"))),"p");}
}
