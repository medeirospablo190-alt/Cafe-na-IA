package com.cafeina.executor;
import static org.junit.Assert.*; import android.content.Context; import androidx.test.core.app.ApplicationProvider; import java.util.*; import org.junit.*;
public final class AiConversationCoordinatorTest {
 private Context context; private CafeinaKnowledgeDatabase db;
 @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(context);}
 @After public void tearDown(){db.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void persistsUserAndAssistantTurnInProjectOrder(){
  ConversationRepository conversations=new ConversationRepository(db);
  CafeinaAiCore core=r->new CafeinaAiCore.Response("reply:"+r.message,Collections.emptyList());
  AiConversationCoordinator c=new AiConversationCoordinator(core,conversations);c.send("p","hello",10,11);
  java.util.List<ConversationRepository.Entry> h=conversations.history("p",10);
  assertEquals(2,h.size());assertEquals("user",h.get(0).role);assertEquals("hello",h.get(0).content);assertEquals("assistant",h.get(1).role);assertEquals("reply:hello",h.get(1).content);
 }
 @Test public void historiesRemainProjectScoped(){
  ConversationRepository conversations=new ConversationRepository(db);CafeinaAiCore core=r->new CafeinaAiCore.Response("ok",Collections.emptyList());AiConversationCoordinator c=new AiConversationCoordinator(core,conversations);
  c.send("a","one",1,2);c.send("b","two",3,4);assertEquals(2,conversations.history("a",10).size());assertEquals("one",conversations.history("a",10).get(0).content);
 }
 @Test public void forwardsRequestedCapabilities(){
  ConversationRepository conversations=new ConversationRepository(db);final java.util.List<String>[] seen=new java.util.List[]{null};CafeinaAiCore core=r->{seen[0]=r.requestedCapabilities;return new CafeinaAiCore.Response("ok",r.requestedCapabilities);};AiConversationCoordinator c=new AiConversationCoordinator(core,conversations);c.send("p","write",java.util.Collections.singletonList("world.write"),1,2);assertEquals(java.util.Collections.singletonList("world.write"),seen[0]);
 }
}
