package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.core.app.ApplicationProvider;
import org.junit.Test;

public final class CafeinaKnowledgeDatabaseMigrationTest {
    @Test public void migratesVersionOneToTwoWithoutDroppingKnowledge() {
        Context context = ApplicationProvider.getApplicationContext();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        SQLiteDatabase legacy = context.openOrCreateDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME, Context.MODE_PRIVATE, null);
        legacy.execSQL("CREATE TABLE knowledge (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, subject TEXT NOT NULL, content TEXT NOT NULL, state TEXT NOT NULL, source_id INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
        legacy.execSQL("CREATE TABLE sources (id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT, title TEXT, provenance TEXT NOT NULL, retrieved_at INTEGER NOT NULL)");
        legacy.execSQL("INSERT INTO knowledge(project_id,subject,content,state,created_at,updated_at) VALUES('p','s','c','VALIDATED',1,1)");
        legacy.setVersion(1);
        legacy.close();

        CafeinaKnowledgeDatabase helper = new CafeinaKnowledgeDatabase(context);
        SQLiteDatabase upgraded = helper.getWritableDatabase();
        try (Cursor c = upgraded.rawQuery("SELECT content FROM knowledge WHERE project_id='p'", null)) {
            assertTrue(c.moveToFirst());
            assertEquals("c", c.getString(0));
        }
        try (Cursor c = upgraded.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='knowledge_links'", null)) {
            assertTrue(c.moveToFirst());
        }
        helper.close();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
    }
}
