package com.cafeina.executor;
public final class AiSafetyDecision {
 public enum Outcome { ALLOW, DENY, REQUIRE_USER }
 public final Outcome outcome; public final String reason;
 public AiSafetyDecision(Outcome outcome,String reason){if(outcome==null||reason==null||reason.trim().isEmpty())throw new IllegalArgumentException("decision fields required");this.outcome=outcome;this.reason=reason;}
}
