package com.cafeina.executor;
public final class AiResearchValidation {
 public enum State { CANDIDATE, CORROBORATED, REJECTED }
 public final AiResearchFinding finding; public final State state; public final String reason;
 public AiResearchValidation(AiResearchFinding finding,State state,String reason){if(finding==null||state==null||reason==null)throw new IllegalArgumentException("validation fields required");this.finding=finding;this.state=state;this.reason=reason;}
}
