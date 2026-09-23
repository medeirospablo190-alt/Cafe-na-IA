package com.cafeina.executor;
public final class AiToolExecutor {
 private final AiToolRegistry registry; private final AiCapabilitySet capabilities;
 public AiToolExecutor(AiToolRegistry registry,AiCapabilitySet capabilities){
  if(registry==null||capabilities==null)throw new IllegalArgumentException("dependencies required");
  this.registry=registry;this.capabilities=capabilities;
 }
 public AiToolResult execute(String toolName,AiToolRequest request){
  AiTool tool=registry.require(toolName);
  if(tool.requiredCapabilities()!=null)for(String capability:tool.requiredCapabilities())capabilities.require(capability);
  return tool.execute(request);
 }
}
