package com.cafeina.executor;
import java.util.Set;
public interface AiTool {
 String name();
 Set<String> requiredCapabilities();
 AiToolResult execute(AiToolRequest request);
}
