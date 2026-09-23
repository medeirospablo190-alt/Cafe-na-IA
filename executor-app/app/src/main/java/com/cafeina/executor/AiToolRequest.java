package com.cafeina.executor;
import java.util.*;
public final class AiToolRequest {
 public final String projectId; public final Map<String,String> arguments;
 public AiToolRequest(String projectId,Map<String,String> arguments){
  if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId required");
  this.projectId=projectId;
  this.arguments=Collections.unmodifiableMap(new LinkedHashMap<>(arguments==null?Collections.emptyMap():arguments));
 }
}
