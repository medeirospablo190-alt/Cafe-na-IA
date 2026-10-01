package com.cafeina.executor;

import java.io.IOException;

/**
 * Runtime-neutral local-model interface.
 *
 * Concrete backends (for example a future on-device native runtime) receive a
 * plain immutable generation request and return text. They do not receive
 * Android Context or any laboratory execution handle.
 */
public interface LaboratoryAiLocalModelBackend {
    final class GenerationRequest {
        public final String prompt;
        public final int maxOutputChars;
        public final float temperature;
        public final long seed;

        public GenerationRequest(String prompt, int maxOutputChars,
                float temperature, long seed) {
            if (prompt == null || prompt.isEmpty()
                    || prompt.length()
                        > LaboratoryAiLlmTestPromptCodec.MAX_PROMPT_CHARS) {
                throw new IllegalArgumentException(
                    "invalid local model prompt");
            }
            if (maxOutputChars < 1
                    || maxOutputChars
                        > LaboratoryAiTestPlanContract.MAX_DRAFT_CHARS) {
                throw new IllegalArgumentException(
                    "invalid local model output limit");
            }
            if (Float.isNaN(temperature)
                    || temperature < 0.0f
                    || temperature > 2.0f) {
                throw new IllegalArgumentException(
                    "invalid local model temperature");
            }
            this.prompt = prompt;
            this.maxOutputChars = maxOutputChars;
            this.temperature = temperature;
            this.seed = seed;
        }
    }

    String generate(GenerationRequest request) throws IOException;
}
