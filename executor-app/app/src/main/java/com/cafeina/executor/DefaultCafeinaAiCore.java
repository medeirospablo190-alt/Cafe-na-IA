package com.cafeina.executor;

public final class DefaultCafeinaAiCore implements CafeinaAiCore {
    private final AiContextAssembler context;
    private final AiModelProvider provider;
    private final AiCapabilitySet capabilities;
    private final AiOperationRouter operations;

    /** Compatibility path for existing callers without an operation catalog. */
    public DefaultCafeinaAiCore(AiContextAssembler context, AiModelProvider provider, AiCapabilitySet capabilities) {
        this(context, provider, capabilities, null);
    }

    public DefaultCafeinaAiCore(AiContextAssembler context, AiModelProvider provider,
                                AiCapabilitySet capabilities, AiOperationRouter operations) {
        if (context == null || provider == null || capabilities == null) {
            throw new IllegalArgumentException("dependencies are required");
        }
        this.context = context;
        this.provider = provider;
        this.capabilities = capabilities;
        this.operations = operations;
    }

    @Override public Response handle(Request request) {
        if (request == null) throw new IllegalArgumentException("request is required");
        for (String capability : request.requestedCapabilities) capabilities.require(capability);
        if (request.message.startsWith(AiOperationRouter.PREFIX)) {
            if (operations == null) throw new IllegalStateException("operation router is not configured");
            return operations.dispatch(request, capabilities);
        }
        // Preserve existing model behavior for ordinary messages.
        return provider.complete(request, context.assemble(request.projectId), capabilities);
    }
}
