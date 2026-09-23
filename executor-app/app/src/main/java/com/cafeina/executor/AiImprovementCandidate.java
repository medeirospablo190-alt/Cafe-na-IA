package com.cafeina.executor;
public final class AiImprovementCandidate {
 public enum State { PROPOSED, TESTING, VALIDATED, REJECTED }
 public final String projectId,description; public final State state;
 public AiImprovementCandidate(String projectId,String description,State state){if(projectId==null||projectId.trim().isEmpty()||description==null||description.trim().isEmpty()||state==null)throw new IllegalArgumentException("improvement fields required");this.projectId=projectId;this.description=description;this.state=state;}
 public AiImprovementCandidate transition(State next){if(next==null)throw new IllegalArgumentException("state required");boolean ok=(state==State.PROPOSED&&next==State.TESTING)||(state==State.TESTING&&(next==State.VALIDATED||next==State.REJECTED));if(!ok)throw new IllegalStateException("invalid improvement transition");return new AiImprovementCandidate(projectId,description,next);}
}
