package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class CafeinaAiCoreImmutabilityTest {
 @Test public void requestAndResponseDefensivelyCopyCapabilities(){
  List<String> requested=new ArrayList<>();requested.add("knowledge.read");
  CafeinaAiCore.Request request=new CafeinaAiCore.Request("p","hello",requested);requested.add("world.write");
  assertEquals(1,request.requestedCapabilities.size());
  List<String> used=new ArrayList<>();used.add("knowledge.read");
  CafeinaAiCore.Response response=new CafeinaAiCore.Response("ok",used);used.add("world.write");
  assertEquals(1,response.usedCapabilities.size());
 }
}
