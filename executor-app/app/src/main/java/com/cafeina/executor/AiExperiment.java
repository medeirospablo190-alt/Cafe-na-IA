package com.cafeina.executor;
public final class AiExperiment {
 public enum State { PLANNED, RUNNING, PASSED, FAILED, CANCELLED }
 public final String id,projectId,hypothesis; public final State state; public final String evidence;
 public AiExperiment(String id,String projectId,String hypothesis,State state,String evidence){if(id==null||id.trim().isEmpty()||projectId==null||projectId.trim().isEmpty()||hypothesis==null||hypothesis.trim().isEmpty()||state==null)throw new IllegalArgumentException("experiment fields required");this.id=id;this.projectId=projectId;this.hypothesis=hypothesis;this.state=state;this.evidence=evidence;}
 public AiExperiment start(){if(state!=State.PLANNED)throw new IllegalStateException("experiment not planned");return new AiExperiment(id,projectId,hypothesis,State.RUNNING,evidence);}
 public AiExperiment pass(String evidence){return finish(State.PASSED,evidence);}
 public AiExperiment fail(String evidence){return finish(State.FAILED,evidence);}
 private AiExperiment finish(State next,String ev){if(state!=State.RUNNING)throw new IllegalStateException("experiment not running");if(ev==null||ev.trim().isEmpty())throw new IllegalArgumentException("evidence required");return new AiExperiment(id,projectId,hypothesis,next,ev);}
}
