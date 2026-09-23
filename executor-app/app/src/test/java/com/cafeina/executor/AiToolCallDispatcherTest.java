package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiToolCallDispatcherTest {
 @Test public void dispatchBuildsProjectScopedRequest(){final String[] seen={null};AiToolRegistry r=new AiToolRegistry();r.register(new AiTool(){public String name(){return "echo";}public Set<String> requiredCapabilities(){return Collections.emptySet();}public AiToolResult execute(AiToolRequest q){seen[0]=q.projectId+":"+q.arguments.get("v");return AiToolResult.success("ok");}});AiToolCallDispatcher d=new AiToolCallDispatcher(r,new AiToolExecutor(r,AiCapabilitySet.none()));d.dispatch("p",new AiToolCall("echo",Collections.singletonMap("v","1")));assertEquals("p:1",seen[0]);}
 @Test public void callDefensivelyCopiesArguments(){Map<String,String> m=new LinkedHashMap<>();m.put("v","1");AiToolCall c=new AiToolCall("x",m);m.put("v","2");assertEquals("1",c.arguments.get("v"));}
}
