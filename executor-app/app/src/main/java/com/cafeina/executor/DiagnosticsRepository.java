package com.cafeina.executor;
import android.content.ContentValues;
import android.database.Cursor;
import java.util.ArrayList;
import java.util.List;
public final class DiagnosticsRepository{
 private final CafeinaKnowledgeDatabase database;
 public DiagnosticsRepository(CafeinaKnowledgeDatabase database){this.database=database;}
 public long record(String projectId,String kind,String message,String details,long createdAt){
  if(kind==null||kind.trim().isEmpty())throw new IllegalArgumentException("kind is required");
  if(message==null||message.trim().isEmpty())throw new IllegalArgumentException("message is required");
  ContentValues v=new ContentValues();if(projectId==null)v.putNull("project_id");else v.put("project_id",projectId);
  v.put("kind",kind);v.put("message",message);if(details==null)v.putNull("details");else v.put("details",details);v.put("created_at",createdAt);
  return database.getWritableDatabase().insertOrThrow("diagnostics",null,v);
 }
 public List<Entry> recent(String projectId,int limit){
  if(limit<1||limit>500)throw new IllegalArgumentException("limit must be 1..500");
  String where=projectId==null?"project_id IS NULL":"project_id=?";String[] args=projectId==null?null:new String[]{projectId};
  ArrayList<Entry> out=new ArrayList<>();
  try(Cursor c=database.getReadableDatabase().query("diagnostics",new String[]{"id","kind","message","details","created_at"},where,args,null,null,"created_at DESC, id DESC",Integer.toString(limit))){
   while(c.moveToNext())out.add(new Entry(c.getLong(0),c.getString(1),c.getString(2),c.isNull(3)?null:c.getString(3),c.getLong(4)));
  }return out;
 }
 public static final class Entry{public final long id;public final String kind,message,details;public final long createdAt;Entry(long id,String k,String m,String d,long t){this.id=id;kind=k;message=m;details=d;createdAt=t;}}
}
