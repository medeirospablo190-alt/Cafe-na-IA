package com.cafeina.executor;

import android.content.ContentValues;
import android.database.Cursor;
import java.util.ArrayList;
import java.util.List;

public final class KnowledgeSourceRepository {
    private final CafeinaKnowledgeDatabase database;
    public KnowledgeSourceRepository(CafeinaKnowledgeDatabase database) { this.database = database; }

    public long add(String uri, String title, String provenance, long retrievedAt) {
        if (provenance == null || provenance.trim().isEmpty()) throw new IllegalArgumentException("provenance is required");
        ContentValues v = new ContentValues();
        if (uri == null) v.putNull("uri"); else v.put("uri", uri);
        if (title == null) v.putNull("title"); else v.put("title", title);
        v.put("provenance", provenance);
        v.put("retrieved_at", retrievedAt);
        return database.getWritableDatabase().insertOrThrow("sources", null, v);
    }

    public List<Source> listNewestFirst() {
        ArrayList<Source> out = new ArrayList<>();
        try (Cursor c = database.getReadableDatabase().query("sources",
                new String[]{"id","uri","title","provenance","retrieved_at"},
                null,null,null,null,"retrieved_at DESC, id DESC")) {
            while(c.moveToNext()) out.add(new Source(c.getLong(0), c.isNull(1)?null:c.getString(1),
                c.isNull(2)?null:c.getString(2), c.getString(3), c.getLong(4)));
        }
        return out;
    }

    public static final class Source {
        public final long id; public final String uri; public final String title; public final String provenance; public final long retrievedAt;
        Source(long id,String uri,String title,String provenance,long retrievedAt){this.id=id;this.uri=uri;this.title=title;this.provenance=provenance;this.retrievedAt=retrievedAt;}
    }
}
