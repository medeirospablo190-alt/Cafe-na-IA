package com.cafeina.executor;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
import java.util.*;

public final class AiCoreIntegrationTest {
 private Context context; private CafeinaKnowledgeDatabase db;
 @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(context);}
 @After public void tearDown(){db.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void deniesCapabilityBeforeProviderInvocation(){
  final boolean[] called={false};
  AiModelProvider provider=(r,c,a)->{called[0]=true;return new CafeinaAiCore.Response("bad",Collections.emptyList());};
  DefaultCafeinaAiCore core=new DefaultCafeinaAiCore(new AiContextAssembler(new KnowledgeRepository(db)),provider,AiCapabilitySet.none());
  assertThrows(SecurityException.class,()->core.handle(new CafeinaAiCore.Request("p","x",Collections.singletonList("world.write"))));
  assertFalse(called[0]);
 }
 @Test public void contextIsProjectScopedAndTrustedOnly(){
  KnowledgeRepository k=new KnowledgeRepository(db);
  k.put("p","experimental","e",KnowledgeState.EXPERIMENTAL,null,1);
  k.put("p","validated","v",KnowledgeState.VALIDATED,null,2);
  k.put("p","consolidated","c",KnowledgeState.CONSOLIDATED,null,3);
  k.put("other","foreign","f",KnowledgeState.VALIDATED,null,4);
  AiModelProvider provider=(r,c,a)->new CafeinaAiCore.Response(c.knowledge.get(0).subject+"|"+c.knowledge.get(1).subject,Collections.emptyList());
  DefaultCafeinaAiCore core=new DefaultCafeinaAiCore(new AiContextAssembler(k),provider,AiCapabilitySet.none());
  String msg=core.handle(new CafeinaAiCore.Request("p","x",Collections.emptyList())).message;
  assertTrue(msg.contains("validated")); assertTrue(msg.contains("consolidated")); assertFalse(msg.contains("experimental")); assertFalse(msg.contains("foreign"));
 }
 @Test public void capabilityInputIsDefensivelyCopied(){
  Set<String> source=new LinkedHashSet<>();source.add("knowledge.read");AiCapabilitySet set=new AiCapabilitySet(source);source.add("world.write");
  assertTrue(set.allows("knowledge.read"));assertFalse(set.allows("world.write"));assertThrows(UnsupportedOperationException.class,()->set.granted().add("x"));
 }
}
