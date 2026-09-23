package com.cafeina.executor;
import java.util.*;
public final class InMemoryAiMissionStore implements AiMissionStore {
 private final Map<String,AiMissionRecord> records=new LinkedHashMap<>();
 public synchronized void save(AiMissionRecord m){if(m==null)throw new IllegalArgumentException("mission required");AiMissionRecord old=records.get(m.id);if(old!=null&&!old.projectId.equals(m.projectId))throw new IllegalArgumentException("mission project cannot change");records.put(m.id,m);}
 public synchronized AiMissionRecord get(String id){return records.get(id);}
 public synchronized List<AiMissionRecord> listForProject(String p,int limit){if(p==null||p.trim().isEmpty()||limit<1)throw new IllegalArgumentException();List<AiMissionRecord> out=new ArrayList<>();for(AiMissionRecord r:records.values())if(p.equals(r.projectId))out.add(r);out.sort((a,b)->{int x=Long.compare(b.updatedAt,a.updatedAt);return x!=0?x:b.id.compareTo(a.id);});return new ArrayList<>(out.subList(0,Math.min(limit,out.size())));}
}
