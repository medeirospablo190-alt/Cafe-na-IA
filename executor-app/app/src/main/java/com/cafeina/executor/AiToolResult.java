package com.cafeina.executor;
public final class AiToolResult {
 public final boolean success; public final String output;
 private AiToolResult(boolean success,String output){this.success=success;this.output=output==null?"":output;}
 public static AiToolResult success(String output){return new AiToolResult(true,output);}
 public static AiToolResult failure(String output){return new AiToolResult(false,output);}
}
