package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

public final class KnowledgeStateTest {
    @Test
    public void knowledgeStatesRemainExplicitAndStable() {
        assertEquals("EXPERIMENTAL", KnowledgeState.EXPERIMENTAL.name());
        assertEquals("VALIDATED", KnowledgeState.VALIDATED.name());
        assertEquals("CONSOLIDATED", KnowledgeState.CONSOLIDATED.name());
        assertEquals("OBSOLETE", KnowledgeState.OBSOLETE.name());
        assertThrows(IllegalArgumentException.class, () -> KnowledgeState.valueOf("TRUSTED"));
    }
}
