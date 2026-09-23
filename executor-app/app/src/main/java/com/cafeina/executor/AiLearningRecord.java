package com.cafeina.executor;
public final class AiLearningRecord {
 public final String projectId,subject,content; public final KnowledgeState state; public final long createdAt;
 public AiLearningRecord(String projectId,String subject,String content,KnowledgeState state,long createdAt){if(projectId==null||projectId.trim().isEmpty()||subject==null||subject.trim().isEmpty()||content==null||content.trim().isEmpty()||state==null)throw new IllegalArgumentException("learning record fields required");this.projectId=projectId;this.subject=subject;this.content=content;this.state=state;this.createdAt=createdAt;}
}
