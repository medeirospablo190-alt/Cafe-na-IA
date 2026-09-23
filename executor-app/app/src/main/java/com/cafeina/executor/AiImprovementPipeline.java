package com.cafeina.executor;
public final class AiImprovementPipeline {
 private final AiImprovementStore store;
 public AiImprovementPipeline(AiImprovementStore store){if(store==null)throw new IllegalArgumentException("store required");this.store=store;}
 public AiImprovementCandidate propose(String projectId,String description){AiImprovementCandidate c=new AiImprovementCandidate(projectId,description,AiImprovementCandidate.State.PROPOSED);store.add(c);return c;}
 public AiImprovementCandidate beginTesting(AiImprovementCandidate c){return transition(c,AiImprovementCandidate.State.TESTING);}
 public AiImprovementCandidate validate(AiImprovementCandidate c){return transition(c,AiImprovementCandidate.State.VALIDATED);}
 public AiImprovementCandidate reject(AiImprovementCandidate c){return transition(c,AiImprovementCandidate.State.REJECTED);}
 private AiImprovementCandidate transition(AiImprovementCandidate c,AiImprovementCandidate.State next){if(c==null)throw new IllegalArgumentException("candidate required");AiImprovementCandidate n=c.transition(next);store.add(n);return n;}
}
