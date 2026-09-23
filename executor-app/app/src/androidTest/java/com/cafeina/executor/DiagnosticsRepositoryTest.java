package com.cafeina.executor;
import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
public final class DiagnosticsRepositoryTest{
 private Context c;private CafeinaKnowledgeDatabase db;private DiagnosticsRepository r;
 @Before public void setUp(){c=ApplicationProvider.getApplicationContext();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(c);r=new DiagnosticsRepository(db);}
 @After public void tearDown(){db.close();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void keepsDiagnosticsScopedAndNewestFirst(){r.record("a","runtime","old",null,1);r.record("b","runtime","other",null,2);r.record("a","test","new","d",3);assertEquals(2,r.recent("a",10).size());assertEquals("new",r.recent("a",10).get(0).message);}
 @Test public void supportsGlobalDiagnostics(){r.record(null,"system","global",null,1);assertEquals(1,r.recent(null,10).size());}
}
