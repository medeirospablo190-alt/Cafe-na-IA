package com.cafeina.executor;
import java.util.*;
public final class AiToolRegistry {
 private final Map<String,AiTool> tools=new LinkedHashMap<>();
 public synchronized void register(AiTool tool){
  if(tool==null||tool.name()==null||tool.name().trim().isEmpty())throw new IllegalArgumentException("valid tool required");
  if(tools.containsKey(tool.name()))throw new IllegalArgumentException("duplicate tool: "+tool.name());
  tools.put(tool.name(),tool);
 }
 public synchronized AiTool require(String name){
  AiTool tool=tools.get(name); if(tool==null)throw new IllegalArgumentException("unknown tool: "+name); return tool;
 }
 public synchronized Set<String> names(){return Collections.unmodifiableSet(new LinkedHashSet<>(tools.keySet()));}
}
