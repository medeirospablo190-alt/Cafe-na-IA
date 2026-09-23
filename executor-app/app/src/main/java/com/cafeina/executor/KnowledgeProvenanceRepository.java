package com.cafeina.executor;

import android.content.ContentValues;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import java.util.ArrayList;
import java.util.List;

public final class KnowledgeProvenanceRepository {
    private final CafeinaKnowledgeDatabase database;

    public KnowledgeProvenanceRepository(CafeinaKnowledgeDatabase database) { this.database = database; }

    public void link(long knowledgeId, long sourceId, long createdAt) {
        SQLiteDatabase db = database.getWritableDatabase();
        db.beginTransaction();
        try {
            requireExists(db, "knowledge", knowledgeId);
            requireExists(db, "sources", sourceId);
            ContentValues values = new ContentValues();
            values.put("knowledge_id", knowledgeId);
            values.put("source_id", sourceId);
            values.put("created_at", createdAt);
            db.insertOrThrow("knowledge_links", null, values);
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }

    public List<Long> sourceIds(long knowledgeId) {
        ArrayList<Long> result = new ArrayList<>();
        try (Cursor cursor = database.getReadableDatabase().query("knowledge_links",
            new String[]{"source_id"}, "knowledge_id=?", new String[]{Long.toString(knowledgeId)},
            null, null, "created_at ASC, source_id ASC")) {
            while (cursor.moveToNext()) result.add(cursor.getLong(0));
        }
        return result;
    }

    private static void requireExists(SQLiteDatabase db, String table, long id) {
        try (Cursor cursor = db.query(table, new String[]{"id"}, "id=?",
            new String[]{Long.toString(id)}, null, null, null, "1")) {
            if (!cursor.moveToFirst()) throw new IllegalArgumentException(table + " id does not exist: " + id);
        }
    }
}
