package com.cafeina.executor;
public final class AiMissionResumeDecision {
 public enum Action { RESUME, WAIT_FOR_USER, DO_NOT_RESUME }
 public final Action action; public final String reason;
 public AiMissionResumeDecision(Action action,String reason){if(action==null||reason==null)throw new IllegalArgumentException("decision fields required");this.action=action;this.reason=reason;}
}
