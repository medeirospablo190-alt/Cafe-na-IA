package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Immutable project-scoped context assembled for one AI turn. */
public final class AiProjectContext {
    public final String projectId;
    public final List<KnowledgeRepository.Entry> knowledge;

    public AiProjectContext(String projectId, List<KnowledgeRepository.Entry> knowledge) {
        if (projectId == null || projectId.trim().isEmpty()) throw new IllegalArgumentException("projectId is required");
        this.projectId = projectId;
        this.knowledge = Collections.unmodifiableList(new ArrayList<>(knowledge == null ? Collections.emptyList() : knowledge));
    }
}
