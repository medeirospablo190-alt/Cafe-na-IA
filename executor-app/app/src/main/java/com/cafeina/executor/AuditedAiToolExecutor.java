package com.cafeina.executor;
public final class AuditedAiToolExecutor {
 private final AiToolExecutor delegate; private final DiagnosticsRepository diagnostics;
 public AuditedAiToolExecutor(AiToolExecutor delegate,DiagnosticsRepository diagnostics){if(delegate==null||diagnostics==null)throw new IllegalArgumentException("dependencies required");this.delegate=delegate;this.diagnostics=diagnostics;}
 public AiToolResult execute(String toolName,AiToolRequest request,long now){
  try{
   AiToolResult result=delegate.execute(toolName,request);
   diagnostics.record(request.projectId,"ai_tool",toolName,result.success?"success":"failure",now);
   return result;
  }catch(RuntimeException e){
   diagnostics.record(request==null?null:request.projectId,"ai_tool_denied",toolName,e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage()),now);
   throw e;
  }
 }
}
