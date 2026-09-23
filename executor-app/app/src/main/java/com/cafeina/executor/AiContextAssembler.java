package com.cafeina.executor;
import java.util.ArrayList; import java.util.List;
public final class AiContextAssembler {
 private final KnowledgeRepository repository;
 public AiContextAssembler(KnowledgeRepository r){if(r==null)throw new IllegalArgumentException("repository is required");repository=r;}
 public AiProjectContext assemble(String p){if(p==null||p.trim().isEmpty())throw new IllegalArgumentException("projectId is required");List<KnowledgeRepository.Entry> k=new ArrayList<>();k.addAll(repository.list(p,KnowledgeState.VALIDATED));k.addAll(repository.list(p,KnowledgeState.CONSOLIDATED));return new AiProjectContext(p,k);}
}
