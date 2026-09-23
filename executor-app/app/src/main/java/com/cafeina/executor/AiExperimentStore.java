package com.cafeina.executor;
import java.util.*;
public final class AiExperimentStore {
 private final Map<String,AiExperiment> items=new LinkedHashMap<>();
 public synchronized void save(AiExperiment e){if(e==null)throw new IllegalArgumentException("experiment required");AiExperiment old=items.get(e.id);if(old!=null&&!old.projectId.equals(e.projectId))throw new SecurityException("experiment project cannot change");items.put(e.id,e);}
 public synchronized AiExperiment get(String id){return items.get(id);}
 public synchronized List<AiExperiment> forProject(String p){List<AiExperiment> out=new ArrayList<>();for(AiExperiment e:items.values())if(e.projectId.equals(p))out.add(e);return Collections.unmodifiableList(out);}
}
