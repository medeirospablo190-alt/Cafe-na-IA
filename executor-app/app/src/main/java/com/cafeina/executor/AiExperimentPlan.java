package com.cafeina.executor;
import java.util.*;
public final class AiExperimentPlan {
 public final String projectId,hypothesis; public final List<String> acceptanceCriteria;
 public AiExperimentPlan(String projectId,String hypothesis,List<String> acceptanceCriteria){if(projectId==null||projectId.trim().isEmpty()||hypothesis==null||hypothesis.trim().isEmpty()||acceptanceCriteria==null||acceptanceCriteria.isEmpty())throw new IllegalArgumentException("experiment plan fields required");this.projectId=projectId;this.hypothesis=hypothesis;this.acceptanceCriteria=Collections.unmodifiableList(new ArrayList<>(acceptanceCriteria));for(String c:this.acceptanceCriteria)if(c==null||c.trim().isEmpty())throw new IllegalArgumentException("acceptance criterion required");}
}
