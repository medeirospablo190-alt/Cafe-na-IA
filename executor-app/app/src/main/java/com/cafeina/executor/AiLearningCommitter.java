package com.cafeina.executor;
public final class AiLearningCommitter {
 private final KnowledgeRepository knowledge;
 public AiLearningCommitter(KnowledgeRepository knowledge){if(knowledge==null)throw new IllegalArgumentException("knowledge required");this.knowledge=knowledge;}
 public long commit(AiLearningPromotion promotion,long now){
  if(promotion==null)throw new IllegalArgumentException("promotion required");
  return knowledge.put(promotion.candidate.projectId,promotion.candidate.subject,promotion.candidate.content,promotion.targetState,null,now);
 }
}
