package com.cafeina.executor;
public final class AiLearningCandidate {
 public final String projectId,subject,content; public final AiResearchValidation.State evidenceState;
 public AiLearningCandidate(String projectId,String subject,String content,AiResearchValidation.State evidenceState){if(projectId==null||projectId.trim().isEmpty()||subject==null||subject.trim().isEmpty()||content==null||content.trim().isEmpty()||evidenceState==null)throw new IllegalArgumentException("candidate fields required");this.projectId=projectId;this.subject=subject;this.content=content;this.evidenceState=evidenceState;}
}
