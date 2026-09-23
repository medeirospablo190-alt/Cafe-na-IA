package com.cafeina.executor;
import java.util.ArrayList; import java.util.Collections; import java.util.List;
public final class AiProjectContext {
 public final String projectId; public final List<KnowledgeRepository.Entry> knowledge;
 public AiProjectContext(String p,List<KnowledgeRepository.Entry> k){if(p==null||p.trim().isEmpty())throw new IllegalArgumentException("projectId is required");projectId=p;knowledge=Collections.unmodifiableList(new ArrayList<>(k==null?Collections.emptyList():k));}
}
