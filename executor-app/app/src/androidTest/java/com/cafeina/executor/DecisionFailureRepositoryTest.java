package com.cafeina.executor;
import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
public final class DecisionFailureRepositoryTest{
 private Context c;private CafeinaKnowledgeDatabase db;
 @Before public void setUp(){c=ApplicationProvider.getApplicationContext();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(c);}
 @After public void tearDown(){db.close();c.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void persistsDecisionAndFailure(){assertTrue(new DecisionRepository(db).record("p","keep world source of truth","invariant",1)>0);assertTrue(new FailureRepository(db).record("p","import-invalid","bad json","rollback",2)>0);}
 @Test public void rejectsMissingRequiredFields(){assertThrows(IllegalArgumentException.class,()->new DecisionRepository(db).record("p"," ",null,1));assertThrows(IllegalArgumentException.class,()->new FailureRepository(db).record("p"," ",null,null,1));}
}
