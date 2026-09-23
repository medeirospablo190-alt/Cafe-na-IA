package com.cafeina.executor;
import java.util.*;
public final class AiResearchBatch {
 public final String projectId,question; public final List<AiResearchValidation> findings;
 public AiResearchBatch(String projectId,String question,List<AiResearchValidation> findings){if(projectId==null||projectId.trim().isEmpty()||question==null||question.trim().isEmpty())throw new IllegalArgumentException("batch identity required");this.projectId=projectId;this.question=question;this.findings=Collections.unmodifiableList(new ArrayList<>(findings==null?Collections.emptyList():findings));}
}
