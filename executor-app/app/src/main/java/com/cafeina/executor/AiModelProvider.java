package com.cafeina.executor;
public interface AiModelProvider { CafeinaAiCore.Response complete(CafeinaAiCore.Request request, AiProjectContext context, AiCapabilitySet capabilities); }
