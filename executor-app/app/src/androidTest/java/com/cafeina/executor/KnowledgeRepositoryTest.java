package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

public final class KnowledgeRepositoryTest {
    private Context context;
    private CafeinaKnowledgeDatabase database;
    private KnowledgeRepository repository;

    @Before public void setUp() {
        context = ApplicationProvider.getApplicationContext();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        database = new CafeinaKnowledgeDatabase(context);
        repository = new KnowledgeRepository(database);
    }

    @After public void tearDown() {
        database.close();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
    }

    @Test public void persistsAndScopesKnowledgeByProjectAndState() {
        repository.put("project-a", "camera", "orbit", KnowledgeState.EXPERIMENTAL, null, 10);
        repository.put("project-b", "camera", "pan", KnowledgeState.EXPERIMENTAL, null, 11);
        assertEquals(1, repository.list("project-a", KnowledgeState.EXPERIMENTAL).size());
        assertEquals("orbit", repository.list("project-a", KnowledgeState.EXPERIMENTAL).get(0).content);
    }

    @Test public void transitionsOnlyFromExpectedStateAndUpdatesTimestamp() {
        long id = repository.put("project-a", "world", "validated fact", KnowledgeState.EXPERIMENTAL, null, 10);
        assertTrue(repository.transition(id, KnowledgeState.EXPERIMENTAL, KnowledgeState.VALIDATED, 20));
        assertFalse(repository.transition(id, KnowledgeState.EXPERIMENTAL, KnowledgeState.CONSOLIDATED, 30));
        KnowledgeRepository.Entry entry = repository.list("project-a", KnowledgeState.VALIDATED).get(0);
        assertEquals(10, entry.createdAt);
        assertEquals(20, entry.updatedAt);
    }

    @Test public void supportsGlobalKnowledgeWithoutLeakingIntoProjectScope() {
        repository.put(null, "luau", "global", KnowledgeState.CONSOLIDATED, null, 10);
        repository.put("project-a", "luau", "project", KnowledgeState.CONSOLIDATED, null, 11);
        assertEquals(1, repository.list(null, KnowledgeState.CONSOLIDATED).size());
        assertEquals("global", repository.list(null, KnowledgeState.CONSOLIDATED).get(0).content);
    }

    @Test public void rejectsEmptyKnowledge() {
        assertThrows(IllegalArgumentException.class,
            () -> repository.put("project-a", " ", "content", KnowledgeState.EXPERIMENTAL, null, 10));
    }
}
