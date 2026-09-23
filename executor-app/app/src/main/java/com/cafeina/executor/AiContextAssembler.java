package com.cafeina.executor;

import java.util.ArrayList;
import java.util.List;

/**
 * Builds conservative AI context: validated/consolidated project knowledge only.
 * Experimental and obsolete records are excluded from trusted context.
 */
public final class AiContextAssembler {
    private final KnowledgeRepository knowledgeRepository;

    public AiContextAssembler(KnowledgeRepository knowledgeRepository) {
        if (knowledgeRepository == null) throw new IllegalArgumentException("knowledgeRepository is required");
        this.knowledgeRepository = knowledgeRepository;
    }

    public AiProjectContext assemble(String projectId) {
        if (projectId == null || projectId.trim().isEmpty()) throw new IllegalArgumentException("projectId is required");
        List<KnowledgeRepository.Entry> trusted = new ArrayList<>();
        trusted.addAll(knowledgeRepository.list(projectId, KnowledgeState.VALIDATED));
        trusted.addAll(knowledgeRepository.list(projectId, KnowledgeState.CONSOLIDATED));
        return new AiProjectContext(projectId, trusted);
    }
}
