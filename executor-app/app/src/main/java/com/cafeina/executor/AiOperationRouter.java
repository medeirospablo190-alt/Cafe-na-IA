package com.cafeina.executor;

import java.io.IOException;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/** Explicit, host-owned operations. No model output can grant a capability. */
public final class AiOperationRouter {
    public static final String PREFIX = "operation:";
    public static final String PROJECT_INFO = "project.info";
    public static final String PROJECT_READ = "project.read";

    public interface Operation {
        CafeinaAiCore.Response execute(CafeinaAiCore.Request request) throws IOException;
    }

    private final Map<String, RegisteredOperation> operations = new LinkedHashMap<>();

    public AiOperationRouter register(String name, String requiredCapability, Operation operation) {
        if (name == null || !name.matches("[a-z][a-z0-9.]*")
                || requiredCapability == null || requiredCapability.trim().isEmpty() || operation == null) {
            throw new IllegalArgumentException("valid operation and capability are required");
        }
        if (operations.containsKey(name)) throw new IllegalArgumentException("duplicate operation: " + name);
        operations.put(name, new RegisteredOperation(requiredCapability, operation));
        return this;
    }

    public static AiOperationRouter forProjects(ProjectStore projects) {
        if (projects == null) throw new IllegalArgumentException("projects are required");
        return new AiOperationRouter().register(PROJECT_INFO, PROJECT_READ, request -> {
            ProjectStore.Project project = projects.open(request.projectId);
            return new CafeinaAiCore.Response(
                "Project " + project.id() + " is available with its validated storage layout.",
                Collections.singletonList(PROJECT_READ));
        });
    }

    public boolean isOperationRequest(String message) {
        return message != null && message.startsWith(PREFIX);
    }

    public CafeinaAiCore.Response dispatch(CafeinaAiCore.Request request, AiCapabilitySet granted) {
        if (request == null || granted == null) throw new IllegalArgumentException("request and capabilities are required");
        if (!isOperationRequest(request.message)) throw new IllegalArgumentException("not an operation request");
        String name = request.message.substring(PREFIX.length());
        RegisteredOperation registered = operations.get(name);
        if (registered == null) throw new IllegalArgumentException("unknown operation: " + name);
        if (!request.requestedCapabilities.contains(registered.capability)) {
            throw new SecurityException("operation capability was not requested: " + registered.capability);
        }
        granted.require(registered.capability);
        try {
            return registered.operation.execute(request);
        } catch (IOException failure) {
            throw new IllegalStateException("operation failed: " + name, failure);
        }
    }

    private static final class RegisteredOperation {
        final String capability;
        final Operation operation;
        RegisteredOperation(String capability, Operation operation) {
            this.capability = capability;
            this.operation = operation;
        }
    }
}
