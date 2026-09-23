package com.cafeina.executor;

/**
 * Default orchestration core. It assembles trusted project context and delegates to a provider.
 * The provider receives only the explicit capability set supplied for this turn.
 */
public final class DefaultCafeinaAiCore implements CafeinaAiCore {
    private final AiContextAssembler contextAssembler;
    private final AiModelProvider provider;
    private final AiCapabilitySet capabilities;

    public DefaultCafeinaAiCore(AiContextAssembler contextAssembler, AiModelProvider provider, AiCapabilitySet capabilities) {
        if (contextAssembler == null || provider == null || capabilities == null) throw new IllegalArgumentException("dependencies are required");
        this.contextAssembler = contextAssembler;
        this.provider = provider;
        this.capabilities = capabilities;
    }

    @Override public Response handle(Request request) {
        if (request == null) throw new IllegalArgumentException("request is required");
        for (String requested : request.requestedCapabilities) capabilities.require(requested);
        return provider.complete(request, contextAssembler.assemble(request.projectId), capabilities);
    }
}
