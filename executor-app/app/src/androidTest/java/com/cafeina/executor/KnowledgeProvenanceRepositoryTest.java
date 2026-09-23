package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.ContentValues;
import android.database.sqlite.SQLiteDatabase;

import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Arrays;

@RunWith(AndroidJUnit4.class)
public final class KnowledgeProvenanceRepositoryTest {
    private CafeinaKnowledgeDatabase database;
    private KnowledgeProvenanceRepository repository;

    @Before public void setUp() {
        ApplicationProvider.getApplicationContext().deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        database = new CafeinaKnowledgeDatabase(ApplicationProvider.getApplicationContext());
        repository = new KnowledgeProvenanceRepository(database);
    }

    @After public void tearDown() {
        database.close();
        ApplicationProvider.getApplicationContext().deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
    }

    @Test public void linksMultipleSourcesDeterministicallyAndCascades() {
        SQLiteDatabase db = database.getWritableDatabase();
        ContentValues k = new ContentValues();
        k.put("subject","s"); k.put("content","c"); k.put("state","EXPERIMENTAL"); k.put("created_at",1); k.put("updated_at",1);
        long knowledgeId = db.insertOrThrow("knowledge", null, k);
        long sourceA = source(db, "a", 1); long sourceB = source(db, "b", 2);
        repository.link(knowledgeId, sourceB, 20);
        repository.link(knowledgeId, sourceA, 10);
        assertEquals(Arrays.asList(sourceA, sourceB), repository.sourceIds(knowledgeId));
        db.delete("sources", "id=?", new String[]{Long.toString(sourceA)});
        assertEquals(Arrays.asList(sourceB), repository.sourceIds(knowledgeId));
    }

    @Test public void rejectsMissingEndpoints() {
        boolean rejected=false;
        try { repository.link(999, 888, 1); } catch (IllegalArgumentException expected) { rejected=true; }
        assertTrue(rejected);
    }

    private static long source(SQLiteDatabase db, String provenance, long at) {
        ContentValues s=new ContentValues(); s.put("provenance",provenance); s.put("retrieved_at",at);
        return db.insertOrThrow("sources",null,s);
    }
}
