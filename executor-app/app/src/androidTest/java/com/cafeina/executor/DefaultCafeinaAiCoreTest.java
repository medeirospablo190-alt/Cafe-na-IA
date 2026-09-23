package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.After; import org.junit.Before; import org.junit.Test;
import java.util.Collections;

public final class DefaultCafeinaAiCoreTest {
 private Context context; private CafeinaKnowledgeDatabase db;
 @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(context);}
 @After public void tearDown(){db.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void rejectsUngrantableRequestedCapability(){
  KnowledgeRepository kr=new KnowledgeRepository(db); AiContextAssembler ca=new AiContextAssembler(kr);
  AiModelProvider provider=(r,c,a)->new CafeinaAiCore.Response("ok",Collections.emptyList());
  DefaultCafeinaAiCore core=new DefaultCafeinaAiCore(ca,provider,AiCapabilitySet.none());
  CafeinaAiCore.Request req=new CafeinaAiCore.Request("p","hello",Collections.singletonList("world.write"));
  assertThrows(SecurityException.class,()->core.handle(req));
 }
 @Test public void providerReceivesOnlyTrustedProjectKnowledge(){
  KnowledgeRepository kr=new KnowledgeRepository(db);
  kr.put("p","candidate","x",KnowledgeState.EXPERIMENTAL,null,1);
  kr.put("p","verified","y",KnowledgeState.VALIDATED,null,2);
  kr.put("other","foreign","z",KnowledgeState.CONSOLIDATED,null,3);
  AiModelProvider provider=(r,c,a)->new CafeinaAiCore.Response(c.knowledge.get(0).subject,Collections.emptyList());
  DefaultCafeinaAiCore core=new DefaultCafeinaAiCore(new AiContextAssembler(kr),provider,AiCapabilitySet.none());
  CafeinaAiCore.Response response=core.handle(new CafeinaAiCore.Request("p","hello",Collections.emptyList()));
  assertEquals("verified",response.message);
 }
}
