package com.cafeina.executor;
public final class DefaultCafeinaAiCore implements CafeinaAiCore {
 private final AiContextAssembler context; private final AiModelProvider provider; private final AiCapabilitySet capabilities;
 public DefaultCafeinaAiCore(AiContextAssembler c,AiModelProvider p,AiCapabilitySet a){if(c==null||p==null||a==null)throw new IllegalArgumentException("dependencies are required");context=c;provider=p;capabilities=a;}
 @Override public Response handle(Request r){if(r==null)throw new IllegalArgumentException("request is required");for(String c:r.requestedCapabilities)capabilities.require(c);return provider.complete(r,context.assemble(r.projectId),capabilities);}
}
