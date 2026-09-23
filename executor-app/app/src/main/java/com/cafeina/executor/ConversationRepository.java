package com.cafeina.executor;

import android.content.ContentValues;
import android.database.Cursor;
import java.util.ArrayList;
import java.util.List;

public final class ConversationRepository {
    private final CafeinaKnowledgeDatabase database;
    public ConversationRepository(CafeinaKnowledgeDatabase database){this.database=database;}

    public long append(String projectId,String role,String content,long createdAt){
        if(projectId==null||projectId.trim().isEmpty()) throw new IllegalArgumentException("projectId is required");
        if(role==null||role.trim().isEmpty()) throw new IllegalArgumentException("role is required");
        if(content==null||content.trim().isEmpty()) throw new IllegalArgumentException("content is required");
        ContentValues v=new ContentValues();v.put("project_id",projectId);v.put("role",role);v.put("content",content);v.put("created_at",createdAt);
        return database.getWritableDatabase().insertOrThrow("conversations",null,v);
    }

    public List<Message> history(String projectId,int limit){
        if(projectId==null||projectId.trim().isEmpty()) throw new IllegalArgumentException("projectId is required");
        if(limit<1||limit>1000) throw new IllegalArgumentException("limit must be 1..1000");
        ArrayList<Message> out=new ArrayList<>();
        try(Cursor c=database.getReadableDatabase().query("conversations",new String[]{"id","role","content","created_at"},
            "project_id=?",new String[]{projectId},null,null,"created_at DESC, id DESC",Integer.toString(limit))){
            while(c.moveToNext()) out.add(new Message(c.getLong(0),c.getString(1),c.getString(2),c.getLong(3)));
        }
        java.util.Collections.reverse(out);
        return out;
    }

    public static final class Message{
        public final long id;public final String role;public final String content;public final long createdAt;
        Message(long id,String role,String content,long createdAt){this.id=id;this.role=role;this.content=content;this.createdAt=createdAt;}
    }
}
