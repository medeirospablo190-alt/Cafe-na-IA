package com.cafeina.executor;
import android.content.ContentValues;
public final class FailureRepository{
 private final CafeinaKnowledgeDatabase database;
 public FailureRepository(CafeinaKnowledgeDatabase database){this.database=database;}
 public long record(String projectId,String signature,String details,String resolution,long createdAt){
  if(signature==null||signature.trim().isEmpty())throw new IllegalArgumentException("signature is required");
  ContentValues v=new ContentValues();if(projectId==null)v.putNull("project_id");else v.put("project_id",projectId);v.put("signature",signature);
  if(details==null)v.putNull("details");else v.put("details",details);if(resolution==null)v.putNull("resolution");else v.put("resolution",resolution);v.put("created_at",createdAt);
  return database.getWritableDatabase().insertOrThrow("failures",null,v);
 }
}
