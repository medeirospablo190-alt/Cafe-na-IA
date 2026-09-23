package com.cafeina.executor;
import android.content.ContentValues;
public final class DecisionRepository{
 private final CafeinaKnowledgeDatabase database;
 public DecisionRepository(CafeinaKnowledgeDatabase database){this.database=database;}
 public long record(String projectId,String decision,String rationale,long createdAt){
  if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId is required");
  if(decision==null||decision.trim().isEmpty())throw new IllegalArgumentException("decision is required");
  ContentValues v=new ContentValues();v.put("project_id",projectId);v.put("decision",decision);if(rationale==null)v.putNull("rationale");else v.put("rationale",rationale);v.put("created_at",createdAt);
  return database.getWritableDatabase().insertOrThrow("decisions",null,v);
 }
}
