package com.cafeina.executor;
import android.content.ContentValues;
public final class KnowledgeSnapshotRepository{
 private final CafeinaKnowledgeDatabase database;
 public KnowledgeSnapshotRepository(CafeinaKnowledgeDatabase database){this.database=database;}
 public long record(String projectId,String snapshotId,long createdAt){if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId is required");if(snapshotId==null||snapshotId.trim().isEmpty())throw new IllegalArgumentException("snapshotId is required");ContentValues v=new ContentValues();v.put("project_id",projectId);v.put("snapshot_id",snapshotId);v.put("created_at",createdAt);return database.getWritableDatabase().insertOrThrow("snapshots",null,v);}
}