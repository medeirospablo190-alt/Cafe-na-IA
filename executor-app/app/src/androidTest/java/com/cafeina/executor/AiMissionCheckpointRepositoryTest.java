package com.cafeina.executor;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

public final class AiMissionCheckpointRepositoryTest {
    private Context context;
    private CafeinaKnowledgeDatabase database;
    private AiMissionCheckpointRepository repository;

    @Before public void setUp() {
        context = ApplicationProvider.getApplicationContext();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        database = new CafeinaKnowledgeDatabase(context);
        repository = new AiMissionCheckpointRepository(database);
    }

    @After public void tearDown() {
        database.close();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
    }

    @Test public void reopensAndIsolatesProjects() {
        repository.save(new AiMissionSnapshot("m", "project-a", "goal-a", AiMissionState.RUNNING), 10);
        repository.save(new AiMissionSnapshot("m", "project-b", "goal-b", AiMissionState.COMPLETED), 11);
        database.close();
        database = new CafeinaKnowledgeDatabase(context);
        repository = new AiMissionCheckpointRepository(database);
        assertEquals("goal-a", repository.load("project-a", "m").goal);
        assertEquals(AiMissionState.WAITING_USER, repository.restore("project-a", "m").state());
        assertEquals(AiMissionState.COMPLETED, repository.restore("project-b", "m").state());
        assertNull(repository.load("project-a", "missing"));
    }

    @Test public void rejectsUnsafeIdentifiersAndOversizedGoals() {
        assertThrows(IllegalArgumentException.class, () -> repository.save(
            new AiMissionSnapshot("m", "../other", "goal", AiMissionState.CREATED), 1));
        assertThrows(IllegalArgumentException.class, () -> repository.save(
            new AiMissionSnapshot("m", "project-a", new String(new char[16385]).replace('\0', 'x'),
                AiMissionState.CREATED), 1));
    }

    @Test public void upgradesExistingV2WithoutLosingKnowledge() {
        database.close();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        android.database.sqlite.SQLiteDatabase old = context.openOrCreateDatabase(
            CafeinaKnowledgeDatabase.DATABASE_NAME, Context.MODE_PRIVATE, null);
        old.execSQL("CREATE TABLE knowledge (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT, subject TEXT NOT NULL, content TEXT NOT NULL, state TEXT NOT NULL, source_id INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
        old.execSQL("INSERT INTO knowledge(project_id,subject,content,state,created_at,updated_at) VALUES('project-a','fact','preserved','VALIDATED',1,1)");
        old.setVersion(2);
        old.close();
        database = new CafeinaKnowledgeDatabase(context);
        repository = new AiMissionCheckpointRepository(database);
        repository.save(new AiMissionSnapshot("m", "project-a", "goal", AiMissionState.CREATED), 2);
        try (android.database.Cursor cursor = database.getReadableDatabase().rawQuery(
                "SELECT content FROM knowledge WHERE project_id='project-a'", null)) {
            assertTrue(cursor.moveToFirst());
            assertEquals("preserved", cursor.getString(0));
        }
    }
}
