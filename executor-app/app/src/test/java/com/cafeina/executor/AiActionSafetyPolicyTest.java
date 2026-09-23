package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiActionSafetyPolicyTest {
 private AiTool tool(String cap){return new AiTool(){public String name(){return "x";}public Set<String> requiredCapabilities(){return Collections.singleton(cap);}public AiToolResult execute(AiToolRequest r){return AiToolResult.success("x");}};}
 @Test public void missingCapabilityDenied(){AiSafetyDecision d=new AiActionSafetyPolicy(Collections.emptySet()).evaluate(tool("world.write"),AiCapabilitySet.none());assertEquals(AiSafetyDecision.Outcome.DENY,d.outcome);}
 @Test public void sensitiveGrantedCapabilityStillRequiresUser(){AiSafetyDecision d=new AiActionSafetyPolicy(Collections.singleton("stable.promote")).evaluate(tool("stable.promote"),new AiCapabilitySet(Collections.singleton("stable.promote")));assertEquals(AiSafetyDecision.Outcome.REQUIRE_USER,d.outcome);}
 @Test public void ordinaryGrantedCapabilityAllowed(){AiSafetyDecision d=new AiActionSafetyPolicy(Collections.singleton("stable.promote")).evaluate(tool("world.read"),new AiCapabilitySet(Collections.singleton("world.read")));assertEquals(AiSafetyDecision.Outcome.ALLOW,d.outcome);}
}
