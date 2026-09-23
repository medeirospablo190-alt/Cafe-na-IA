package com.cafeina.executor;

/** Provider-neutral boundary. Provider implementations may be local or remote. */
public interface AiModelProvider {
    CafeinaAiCore.Response complete(CafeinaAiCore.Request request, AiProjectContext context, AiCapabilitySet capabilities);
}
