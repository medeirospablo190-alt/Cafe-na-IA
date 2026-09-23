package com.cafeina.executor;
import java.util.*;
public final class AiResearchService {
 private final AiResearchProvider provider;
 public AiResearchService(AiResearchProvider provider){if(provider==null)throw new IllegalArgumentException("provider required");this.provider=provider;}
 public List<AiResearchFinding> research(String projectId,String question){
  if(projectId==null||projectId.trim().isEmpty()||question==null||question.trim().isEmpty())throw new IllegalArgumentException("project and question required");
  List<AiResearchFinding> r=provider.research(projectId,question);if(r==null)return Collections.emptyList();return Collections.unmodifiableList(new ArrayList<>(r));
 }
}
