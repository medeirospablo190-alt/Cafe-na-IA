package com.cafeina.executor;

import java.io.IOException;

/**
 * Adapter from the planner's model-facing Request to any local model backend.
 *
 * The backend only sees the deterministic JSON prompt protocol. Its output is
 * still merely an untrusted draft; LaboratoryAiLlmTestPlanner always routes it
 * through LaboratoryAiTestPlanContract before a Plan can exist.
 */
public final class LaboratoryAiLocalModelTestPlannerGateway
        implements LaboratoryAiLlmTestPlanner.ModelGateway {
    public static final float DEFAULT_TEMPERATURE = 0.0f;
    public static final long DEFAULT_SEED = 20261001L;

    private final LaboratoryAiLocalModelBackend backend;
    private final float temperature;
    private final long seed;

    public LaboratoryAiLocalModelTestPlannerGateway(
            LaboratoryAiLocalModelBackend backend) {
        this(backend, DEFAULT_TEMPERATURE, DEFAULT_SEED);
    }

    public LaboratoryAiLocalModelTestPlannerGateway(
            LaboratoryAiLocalModelBackend backend,
            float temperature,
            long seed) {
        if (backend == null) {
            throw new IllegalArgumentException(
                "local model backend missing");
        }
        if (Float.isNaN(temperature)
                || temperature < 0.0f
                || temperature > 2.0f) {
            throw new IllegalArgumentException(
                "invalid local model temperature");
        }
        this.backend = backend;
        this.temperature = temperature;
        this.seed = seed;
    }

    @Override
    public String propose(LaboratoryAiLlmTestPlanner.Request request)
            throws IOException {
        String prompt = LaboratoryAiLlmTestPromptCodec.encode(request);
        LaboratoryAiLocalModelBackend.GenerationRequest generation =
            new LaboratoryAiLocalModelBackend.GenerationRequest(
                prompt,
                LaboratoryAiTestPlanContract.MAX_DRAFT_CHARS,
                temperature,
                seed);

        String output = backend.generate(generation);
        if (output == null) {
            throw new IOException("local model returned no planner output");
        }
        if (output.length()
                > LaboratoryAiTestPlanContract.MAX_DRAFT_CHARS) {
            throw new IOException(
                "local model exceeded planner output limit");
        }
        return output;
    }
}
