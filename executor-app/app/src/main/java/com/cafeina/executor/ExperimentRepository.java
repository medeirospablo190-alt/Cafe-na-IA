package com.cafeina.executor;
import android.content.ContentValues;
public final class ExperimentRepository{
 private final CafeinaKnowledgeDatabase database;
 public ExperimentRepository(CafeinaKnowledgeDatabase database){this.database=database;}
 public long start(String projectId,String goal,long createdAt){if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId is required");if(goal==null||goal.trim().isEmpty())throw new IllegalArgumentException("goal is required");ContentValues v=new ContentValues();v.put("project_id",projectId);v.put("goal",goal);v.put("status","RUNNING");v.put("created_at",createdAt);return database.getWritableDatabase().insertOrThrow("experiments",null,v);}
 public boolean complete(long id,String evidence,long completedAt){ContentValues v=new ContentValues();v.put("status","COMPLETED");if(evidence==null)v.putNull("evidence");else v.put("evidence",evidence);v.put("completed_at",completedAt);return database.getWritableDatabase().update("experiments",v,"id=? AND status=?",new String[]{Long.toString(id),"RUNNING"})==1;}
}