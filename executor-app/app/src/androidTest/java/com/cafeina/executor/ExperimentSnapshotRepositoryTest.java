package com.cafeina.executor;
import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
public final class ExperimentSnapshotRepositoryTest{
 private Context c;private CafeinaKnowledgeDatabase db;
 @Before public void setUp(){c=ApplicationProvider.getApplicationContext();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(c);}
 @After public void tearDown(){db.close();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void experimentCompletesOnce(){ExperimentRepository r=new ExperimentRepository(db);long id=r.start("p","validate import",1);assertTrue(r.complete(id,"ok",2));assertFalse(r.complete(id,"again",3));}
 @Test public void snapshotIdentityIsUniquePerProject(){KnowledgeSnapshotRepository r=new KnowledgeSnapshotRepository(db);assertTrue(r.record("p","s1",1)>0);assertThrows(android.database.sqlite.SQLiteConstraintException.class,()->r.record("p","s1",2));}
}