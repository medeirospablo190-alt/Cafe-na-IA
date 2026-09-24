package com.cafeina.executor;

import android.content.Context;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

public final class CafeinaKnowledgeDatabase extends SQLiteOpenHelper {
    public static final String DATABASE_NAME = "cafeina-knowledge.db";
    public static final int DATABASE_VERSION = 3;

    @Override
    public void onConfigure(SQLiteDatabase db) {
        super.onConfigure(db);
        db.setForeignKeyConstraintsEnabled(true);
    }

    public CafeinaKnowledgeDatabase(Context context) {
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE conversations (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE knowledge (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, subject TEXT NOT NULL, content TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('EXPERIMENTAL','VALIDATED','CONSOLIDATED','OBSOLETE')), source_id INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE sources (id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT, title TEXT, provenance TEXT NOT NULL, retrieved_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE experiments (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, goal TEXT NOT NULL, status TEXT NOT NULL, evidence TEXT, created_at INTEGER NOT NULL, completed_at INTEGER)");
        db.execSQL("CREATE TABLE diagnostics (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, kind TEXT NOT NULL, message TEXT NOT NULL, details TEXT, created_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE test_results (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, test_name TEXT NOT NULL, status TEXT NOT NULL, evidence TEXT, created_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE decisions (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, decision TEXT NOT NULL, rationale TEXT, created_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE failures (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, signature TEXT NOT NULL, details TEXT, resolution TEXT, created_at INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT NOT NULL, snapshot_id TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(project_id, snapshot_id))");
        db.execSQL("CREATE INDEX idx_knowledge_project_state ON knowledge(project_id, state)");
        db.execSQL("CREATE INDEX idx_test_results_project ON test_results(project_id, created_at)");
        db.execSQL("CREATE INDEX idx_failures_signature ON failures(signature)");
        createKnowledgeLinks(db);
        createMissionCheckpoints(db);
    }

    private static void createKnowledgeLinks(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE knowledge_links (knowledge_id INTEGER NOT NULL, source_id INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(knowledge_id, source_id), FOREIGN KEY(knowledge_id) REFERENCES knowledge(id) ON DELETE CASCADE, FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE)");
        db.execSQL("CREATE INDEX idx_knowledge_links_source ON knowledge_links(source_id)");
    }

    private static void createMissionCheckpoints(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE mission_checkpoints (project_id TEXT NOT NULL, mission_id TEXT NOT NULL, goal TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('CREATED','RUNNING','WAITING_USER','COMPLETED','FAILED','CANCELLED')), updated_at INTEGER NOT NULL, PRIMARY KEY(project_id, mission_id))");
        db.execSQL("CREATE INDEX idx_mission_checkpoints_project_state ON mission_checkpoints(project_id, state)");
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        if (oldVersion == 1 && newVersion >= 2) {
            createKnowledgeLinks(db);
            oldVersion = 2;
        }
        if (oldVersion == 2 && newVersion == 3) {
            createMissionCheckpoints(db);
            return;
        }
        if (oldVersion != newVersion) throw new IllegalStateException("unsupported knowledge database migration " + oldVersion + " -> " + newVersion);
    }
}
