package com.cafeina.executor;
import java.util.*;
public final class AiToolPlan {
 public static final class Step {
  public final String toolName; public final AiToolRequest request;
  public Step(String toolName,AiToolRequest request){if(toolName==null||toolName.trim().isEmpty()||request==null)throw new IllegalArgumentException("step fields required");this.toolName=toolName;this.request=request;}
 }
 private final List<Step> steps;
 public AiToolPlan(List<Step> steps){this.steps=Collections.unmodifiableList(new ArrayList<>(steps==null?Collections.emptyList():steps));}
 public List<Step> steps(){return steps;}
}
