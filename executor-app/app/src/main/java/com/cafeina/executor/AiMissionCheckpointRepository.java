package com.cafeina.executor;

import android.content.ContentValues;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;

/** Project-scoped, transactional checkpoint storage. Does not execute missions. */
public final class AiMissionCheckpointRepository {
    private final CafeinaKnowledgeDatabase database;

    public AiMissionCheckpointRepository(CafeinaKnowledgeDatabase database) {
        if (database == null) throw new IllegalArgumentException("database is required");
        this.database = database;
    }

    public void save(AiMissionSnapshot snapshot, long now) {
        if (snapshot == null) throw new IllegalArgumentException("snapshot is required");
        if (!ProjectStore.isValidId(snapshot.projectId)) throw new IllegalArgumentException("invalid project id");
        if (snapshot.id.length() > 128) throw new IllegalArgumentException("mission id is too long");
        if (snapshot.goal.length() > 16384) throw new IllegalArgumentException("mission goal is too long");
        SQLiteDatabase db = database.getWritableDatabase();
        db.beginTransaction();
        try {
            try (Cursor previous = db.query("mission_checkpoints", new String[]{"goal", "state"},
                    "project_id=? AND mission_id=?", new String[]{snapshot.projectId, snapshot.id},
                    null, null, null)) {
                if (previous.moveToFirst()) {
                    if (!snapshot.goal.equals(previous.getString(0))) {
                        throw new IllegalStateException("mission identity cannot change its goal");
                    }
                    AiMissionState old = AiMissionState.valueOf(previous.getString(1));
                    if (old == AiMissionState.COMPLETED || old == AiMissionState.FAILED
                            || old == AiMissionState.CANCELLED) {
                        if (old != snapshot.state) throw new IllegalStateException("terminal mission cannot restart");
                    }
                }
            }
            ContentValues values = new ContentValues();
            values.put("project_id", snapshot.projectId);
            values.put("mission_id", snapshot.id);
            values.put("goal", snapshot.goal);
            values.put("state", snapshot.state.name());
            values.put("updated_at", now);
            db.insertWithOnConflict("mission_checkpoints", null, values, SQLiteDatabase.CONFLICT_REPLACE);
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
    }

    /** Returns null for an absent checkpoint; never searches other projects. */
    public AiMissionSnapshot load(String projectId, String missionId) {
        if (!ProjectStore.isValidId(projectId)) throw new IllegalArgumentException("invalid project id");
        if (missionId == null || missionId.trim().isEmpty()) throw new IllegalArgumentException("mission id is required");
        try (Cursor cursor = database.getReadableDatabase().query("mission_checkpoints",
                new String[]{"mission_id", "project_id", "goal", "state"},
                "project_id=? AND mission_id=?", new String[]{projectId, missionId},
                null, null, null)) {
            if (!cursor.moveToFirst()) return null;
            return new AiMissionSnapshot(cursor.getString(0), cursor.getString(1),
                    cursor.getString(2), AiMissionState.valueOf(cursor.getString(3)));
        }
    }

    /** Restores RUNNING as WAITING_USER; never replays effects. */
    public AiMission restore(String projectId, String missionId) {
        AiMissionSnapshot snapshot = load(projectId, missionId);
        return snapshot == null ? null : AiMission.restore(snapshot);
    }
}
