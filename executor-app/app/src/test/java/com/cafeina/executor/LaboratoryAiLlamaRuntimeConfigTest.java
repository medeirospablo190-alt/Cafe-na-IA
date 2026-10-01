package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class LaboratoryAiLlamaRuntimeConfigTest {
    @Test
    public void smokeProfileIsTighterThanPlannerProfile() {
        LaboratoryAiLlamaCppBackend.RuntimeConfig smoke =
            LaboratoryAiLlamaCppBackend.RuntimeConfig.smokeTestDefaults();
        LaboratoryAiLlamaCppBackend.RuntimeConfig planner =
            LaboratoryAiLlamaCppBackend.RuntimeConfig.plannerDefaults();

        assertEquals(32, smoke.maxTokens);
        assertEquals(1024, smoke.contextTokens);
        assertEquals(90_000L, smoke.maxGenerationMs);

        assertTrue(smoke.maxTokens < planner.maxTokens);
        assertTrue(smoke.contextTokens < planner.contextTokens);
        assertEquals(120_000L, planner.maxGenerationMs);
        assertTrue(smoke.maxGenerationMs < planner.maxGenerationMs);
        assertTrue(smoke.threads >= 1);
        assertTrue(smoke.threads <= 4);
    }
}
