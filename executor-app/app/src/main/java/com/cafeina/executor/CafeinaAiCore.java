package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Stable local interface between the future CAFEÍNA AI orchestration layer and app/runtime state.
 * Implementations must remain capability-bounded; this contract does not grant network, filesystem,
 * execution or World mutation privileges by itself.
 */
public interface CafeinaAiCore {
    Response handle(Request request);

    final class Request {
        public final String projectId;
        public final String message;
        public final List<String> requestedCapabilities;

        public Request(String projectId, String message, List<String> requestedCapabilities) {
            if (projectId == null || projectId.trim().isEmpty()) throw new IllegalArgumentException("projectId is required");
            if (message == null || message.trim().isEmpty()) throw new IllegalArgumentException("message is required");
            this.projectId = projectId;
            this.message = message;
            this.requestedCapabilities = requestedCapabilities == null
                ? Collections.emptyList() : Collections.unmodifiableList(new ArrayList<>(requestedCapabilities));
        }
    }

    final class Response {
        public final String message;
        public final List<String> usedCapabilities;

        public Response(String message, List<String> usedCapabilities) {
            if (message == null) throw new IllegalArgumentException("message is required");
            this.message = message;
            this.usedCapabilities = usedCapabilities == null
                ? Collections.emptyList() : Collections.unmodifiableList(new ArrayList<>(usedCapabilities));
        }
    }
}
