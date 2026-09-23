package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiToolSystemTest {
 static AiTool tool(final int[] calls){return new AiTool(){public String name(){return "world.inspect";}public Set<String> requiredCapabilities(){return Collections.singleton("world.read");}public AiToolResult execute(AiToolRequest r){calls[0]++;return AiToolResult.success(r.projectId);}};}
 @Test public void deniesBeforeToolExecution(){int[] calls={0};AiToolRegistry r=new AiToolRegistry();r.register(tool(calls));AiToolExecutor e=new AiToolExecutor(r,AiCapabilitySet.none());assertThrows(SecurityException.class,()->e.execute("world.inspect",new AiToolRequest("p",null)));assertEquals(0,calls[0]);}
 @Test public void executesWhenCapabilityGranted(){int[] calls={0};AiToolRegistry r=new AiToolRegistry();r.register(tool(calls));AiToolExecutor e=new AiToolExecutor(r,new AiCapabilitySet(Collections.singleton("world.read")));assertTrue(e.execute("world.inspect",new AiToolRequest("p",null)).success);assertEquals(1,calls[0]);}
 @Test public void duplicateAndUnknownToolsFailClosed(){AiToolRegistry r=new AiToolRegistry();int[] c={0};r.register(tool(c));assertThrows(IllegalArgumentException.class,()->r.register(tool(c)));assertThrows(IllegalArgumentException.class,()->r.require("missing"));}
 @Test public void requestDefensivelyCopiesArguments(){Map<String,String> m=new LinkedHashMap<>();m.put("x","1");AiToolRequest r=new AiToolRequest("p",m);m.put("x","2");assertEquals("1",r.arguments.get("x"));assertThrows(UnsupportedOperationException.class,()->r.arguments.put("y","3"));}
}
