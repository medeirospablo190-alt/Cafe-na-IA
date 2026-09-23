package com.cafeina.executor;
import java.util.*;
public final class AiToolCall {
 public final String toolName; public final Map<String,String> arguments;
 public AiToolCall(String toolName,Map<String,String> arguments){
  if(toolName==null||toolName.trim().isEmpty())throw new IllegalArgumentException("toolName required");
  this.toolName=toolName;this.arguments=Collections.unmodifiableMap(new LinkedHashMap<>(arguments==null?Collections.emptyMap():arguments));
 }
}
