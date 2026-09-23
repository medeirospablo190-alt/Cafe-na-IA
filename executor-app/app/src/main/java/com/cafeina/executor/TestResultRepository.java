package com.cafeina.executor;
import android.content.ContentValues;
import android.database.Cursor;
import java.util.ArrayList;
import java.util.List;
public final class TestResultRepository{
 private final CafeinaKnowledgeDatabase database;
 public TestResultRepository(CafeinaKnowledgeDatabase database){this.database=database;}
 public long record(String projectId,String testName,String status,String evidence,long createdAt){
  if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId is required");
  if(testName==null||testName.trim().isEmpty())throw new IllegalArgumentException("testName is required");
  if(status==null||status.trim().isEmpty())throw new IllegalArgumentException("status is required");
  ContentValues v=new ContentValues();v.put("project_id",projectId);v.put("test_name",testName);v.put("status",status);
  if(evidence==null)v.putNull("evidence");else v.put("evidence",evidence);v.put("created_at",createdAt);
  return database.getWritableDatabase().insertOrThrow("test_results",null,v);
 }
 public List<Entry> recent(String projectId,int limit){
  if(projectId==null||projectId.trim().isEmpty())throw new IllegalArgumentException("projectId is required");
  if(limit<1||limit>500)throw new IllegalArgumentException("limit must be 1..500");
  ArrayList<Entry> out=new ArrayList<>();
  try(Cursor c=database.getReadableDatabase().query("test_results",new String[]{"id","test_name","status","evidence","created_at"},"project_id=?",new String[]{projectId},null,null,"created_at DESC, id DESC",Integer.toString(limit))){
   while(c.moveToNext())out.add(new Entry(c.getLong(0),c.getString(1),c.getString(2),c.isNull(3)?null:c.getString(3),c.getLong(4)));
  }return out;
 }
 public static final class Entry{public final long id;public final String testName,status,evidence;public final long createdAt;Entry(long i,String n,String s,String e,long t){id=i;testName=n;status=s;evidence=e;createdAt=t;}}
}
