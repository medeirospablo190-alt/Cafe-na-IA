package com.cafeina.executor;

import android.content.ContentValues;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

import java.util.ArrayList;
import java.util.List;

public final class KnowledgeRepository {
    private final CafeinaKnowledgeDatabase database;

    public KnowledgeRepository(CafeinaKnowledgeDatabase database) {
        this.database = database;
    }

    public long put(String projectId, String subject, String content, KnowledgeState state, Long sourceId, long now) {
        requireText(subject, "subject");
        requireText(content, "content");
        if (state == null) throw new IllegalArgumentException("state is required");
        SQLiteDatabase db = database.getWritableDatabase();
        db.beginTransaction();
        try {
            ContentValues values = new ContentValues();
            if (projectId == null) values.putNull("project_id"); else values.put("project_id", projectId);
            values.put("subject", subject);
            values.put("content", content);
            values.put("state", state.name());
            if (sourceId == null) values.putNull("source_id"); else values.put("source_id", sourceId);
            values.put("created_at", now);
            values.put("updated_at", now);
            long id = db.insertOrThrow("knowledge", null, values);
            db.setTransactionSuccessful();
            return id;
        } finally {
            db.endTransaction();
        }
    }

    public List<Entry> list(String projectId, KnowledgeState state) {
        if (state == null) throw new IllegalArgumentException("state is required");
        SQLiteDatabase db = database.getReadableDatabase();
        String selection = projectId == null ? "project_id IS NULL AND state=?" : "project_id=? AND state=?";
        String[] args = projectId == null ? new String[]{state.name()} : new String[]{projectId, state.name()};
        ArrayList<Entry> result = new ArrayList<>();
        try (Cursor cursor = db.query("knowledge",
            new String[]{"id","project_id","subject","content","state","source_id","created_at","updated_at"},
            selection, args, null, null, "updated_at DESC, id DESC")) {
            while (cursor.moveToNext()) {
                result.add(new Entry(
                    cursor.getLong(0), cursor.isNull(1) ? null : cursor.getString(1),
                    cursor.getString(2), cursor.getString(3), KnowledgeState.valueOf(cursor.getString(4)),
                    cursor.isNull(5) ? null : cursor.getLong(5), cursor.getLong(6), cursor.getLong(7)));
            }
        }
        return result;
    }

    public boolean transition(long id, KnowledgeState expected, KnowledgeState next, long now) {
        if (expected == null || next == null) throw new IllegalArgumentException("states are required");
        if (!isAllowedTransition(expected, next)) throw new IllegalArgumentException("invalid knowledge state transition " + expected + " -> " + next);
        ContentValues values = new ContentValues();
        values.put("state", next.name());
        values.put("updated_at", now);
        return database.getWritableDatabase().update("knowledge", values, "id=? AND state=?",
            new String[]{Long.toString(id), expected.name()}) == 1;
    }

    private static boolean isAllowedTransition(KnowledgeState from, KnowledgeState to) {
        if (from == to) return false;
        switch (from) {
            case EXPERIMENTAL: return to == KnowledgeState.VALIDATED || to == KnowledgeState.OBSOLETE;
            case VALIDATED: return to == KnowledgeState.CONSOLIDATED || to == KnowledgeState.OBSOLETE;
            case CONSOLIDATED: return to == KnowledgeState.OBSOLETE;
            case OBSOLETE: return to == KnowledgeState.EXPERIMENTAL;
            default: return false;
        }
    }

    private static void requireText(String value, String field) {
        if (value == null || value.trim().isEmpty()) throw new IllegalArgumentException(field + " is required");
    }

    public static final class Entry {
        public final long id; public final String projectId; public final String subject; public final String content;
        public final KnowledgeState state; public final Long sourceId; public final long createdAt; public final long updatedAt;
        Entry(long id, String projectId, String subject, String content, KnowledgeState state, Long sourceId, long createdAt, long updatedAt) {
            this.id=id; this.projectId=projectId; this.subject=subject; this.content=content; this.state=state;
            this.sourceId=sourceId; this.createdAt=createdAt; this.updatedAt=updatedAt;
        }
    }
}
