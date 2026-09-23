package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

public final class KnowledgeSourceRepositoryTest {
    private Context context; private CafeinaKnowledgeDatabase database; private KnowledgeSourceRepository repository;
    @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);database=new CafeinaKnowledgeDatabase(context);repository=new KnowledgeSourceRepository(database);}
    @After public void tearDown(){database.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
    @Test public void persistsProvenanceAndOrdersNewestFirst(){
        repository.add("https://example.test/a","A","official",10);
        repository.add(null,null,"local-test",20);
        assertEquals(2,repository.listNewestFirst().size());
        assertEquals("local-test",repository.listNewestFirst().get(0).provenance);
    }
    @Test public void rejectsMissingProvenance(){
        assertThrows(IllegalArgumentException.class,()->repository.add(null,null," ",10));
    }
}
