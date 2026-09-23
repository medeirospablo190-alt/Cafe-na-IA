package com.cafeina.executor;
import java.util.*;
public final class AiActionSafetyPolicy {
 private final Set<String> userRequiredCapabilities;
 public AiActionSafetyPolicy(Set<String> userRequiredCapabilities){this.userRequiredCapabilities=Collections.unmodifiableSet(new LinkedHashSet<>(userRequiredCapabilities==null?Collections.emptySet():userRequiredCapabilities));}
 public AiSafetyDecision evaluate(AiTool tool,AiCapabilitySet granted){
  if(tool==null||granted==null)throw new IllegalArgumentException("tool and capabilities required");
  Set<String> required=tool.requiredCapabilities()==null?Collections.emptySet():tool.requiredCapabilities();
  for(String c:required)if(!granted.allows(c))return new AiSafetyDecision(AiSafetyDecision.Outcome.DENY,"capability not granted: "+c);
  for(String c:required)if(userRequiredCapabilities.contains(c))return new AiSafetyDecision(AiSafetyDecision.Outcome.REQUIRE_USER,"capability requires user approval: "+c);
  return new AiSafetyDecision(AiSafetyDecision.Outcome.ALLOW,"capabilities satisfied");
 }
}
