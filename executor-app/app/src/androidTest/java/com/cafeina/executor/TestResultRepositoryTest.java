package com.cafeina.executor;
import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
public final class TestResultRepositoryTest{
 private Context c;private CafeinaKnowledgeDatabase db;private TestResultRepository r;
 @Before public void setUp(){c=ApplicationProvider.getApplicationContext();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(c);r=new TestResultRepository(db);}
 @After public void tearDown(){db.close();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void persistsEvidenceScopedByProject(){r.record("a","world-restore","PASS","snapshot ok",1);r.record("b","world-restore","FAIL","x",2);assertEquals(1,r.recent("a",10).size());assertEquals("snapshot ok",r.recent("a",10).get(0).evidence);}
}
