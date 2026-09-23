package com.cafeina.executor;
import java.util.*;
public final class AiLearningCandidateStore {
 private final List<AiLearningCandidate> candidates=new ArrayList<>();
 public synchronized void add(AiLearningCandidate c){if(c==null)throw new IllegalArgumentException("candidate required");candidates.add(c);}
 public synchronized List<AiLearningCandidate> forProject(String projectId){List<AiLearningCandidate> out=new ArrayList<>();for(AiLearningCandidate c:candidates)if(c.projectId.equals(projectId))out.add(c);return Collections.unmodifiableList(out);}
}
