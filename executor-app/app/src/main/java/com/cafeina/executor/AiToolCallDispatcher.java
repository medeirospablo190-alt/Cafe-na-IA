package com.cafeina.executor;
public final class AiToolCallDispatcher {
 private final AiToolRegistry registry; private final AiToolExecutor executor;
 public AiToolCallDispatcher(AiToolRegistry registry,AiToolExecutor executor){if(registry==null||executor==null)throw new IllegalArgumentException("dependencies required");this.registry=registry;this.executor=executor;}
 public AiToolResult dispatch(String projectId,AiToolCall call){
  if(call==null)throw new IllegalArgumentException("call required");
  registry.require(call.toolName);
  return executor.execute(call.toolName,new AiToolRequest(projectId,call.arguments));
 }
}
