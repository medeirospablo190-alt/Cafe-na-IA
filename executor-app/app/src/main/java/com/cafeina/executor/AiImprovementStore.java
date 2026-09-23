package com.cafeina.executor;
import java.util.*;
public final class AiImprovementStore {
 private final List<AiImprovementCandidate> items=new ArrayList<>();
 public synchronized void add(AiImprovementCandidate c){if(c==null)throw new IllegalArgumentException("candidate required");items.add(c);}
 public synchronized List<AiImprovementCandidate> forProject(String projectId){if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId required");List<AiImprovementCandidate> out=new ArrayList<>();for(AiImprovementCandidate c:items)if(projectId.equals(c.projectId))out.add(c);return Collections.unmodifiableList(out);}
}
