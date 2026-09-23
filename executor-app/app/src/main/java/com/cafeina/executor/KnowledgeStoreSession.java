package com.cafeina.executor;

import android.content.Context;
import java.util.List;

/** Reopens the durable knowledge database without retaining transient query state. */
public final class KnowledgeStoreSession implements AutoCloseable {
 private final CafeinaKnowledgeDatabase database;
 public final KnowledgeRepository knowledge;
 public KnowledgeStoreSession(Context context){
  if(context==null) throw new IllegalArgumentException("context is required");
  database=new CafeinaKnowledgeDatabase(context);
  knowledge=new KnowledgeRepository(database);
 }
 public List<KnowledgeRepository.Entry> list(String projectId, KnowledgeState state){return knowledge.list(projectId,state);}
 @Override public void close(){database.close();}
}
