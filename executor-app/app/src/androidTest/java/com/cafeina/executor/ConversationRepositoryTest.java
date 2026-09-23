package com.cafeina.executor;
import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
public final class ConversationRepositoryTest{
 private Context context;private CafeinaKnowledgeDatabase database;private ConversationRepository repository;
 @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);database=new CafeinaKnowledgeDatabase(context);repository=new ConversationRepository(database);}
 @After public void tearDown(){database.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void historyIsProjectScopedChronologicalAndLimited(){
  repository.append("a","user","one",10);repository.append("b","user","other",15);repository.append("a","assistant","two",20);
  assertEquals(2,repository.history("a",10).size());assertEquals("one",repository.history("a",10).get(0).content);assertEquals("two",repository.history("a",1).get(0).content);
 }
 @Test public void rejectsInvalidInputAndLimits(){
  assertThrows(IllegalArgumentException.class,()->repository.append("a","user"," ",1));
  assertThrows(IllegalArgumentException.class,()->repository.history("a",0));
 }
}
