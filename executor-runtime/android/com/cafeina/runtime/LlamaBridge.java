package com.cafeina.runtime;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * Experimental app-private bridge to the pinned llama.cpp runtime.
 *
 * This bridge owns model lifetime and bounded text generation only. It has no
 * access to Laboratory AI execution handles, permissions, Goal Lock state, or
 * tool APIs.
 */
public final class LlamaBridge {
    public static final int MAX_PROMPT_CHARS = 128 * 1024;
    public static final int MAX_PROMPT_UTF8_BYTES = 128 * 1024;
    public static final int MAX_OUTPUT_CHARS = 96 * 1024;
    public static final int MAX_GENERATED_TOKENS = 2048;
    public static final int MAX_CONTEXT_TOKENS = 8192;
    public static final int MAX_THREADS = 8;

    public static final int GENERATION_PHASE_NONE = 0;
    public static final int GENERATION_PHASE_CONTEXT = 1;
    public static final int GENERATION_PHASE_PROMPT = 2;
    public static final int GENERATION_PHASE_TOKENS = 3;

    private static final boolean NATIVE_AVAILABLE;
    private static final String NATIVE_LOAD_ERROR;

    static {
        boolean loaded = false;
        String error = "";
        try {
            System.loadLibrary("cafeina_llama_jni");
            loaded = true;
        } catch (UnsatisfiedLinkError failure) {
            error = failure.getClass().getSimpleName();
        }
        NATIVE_AVAILABLE = loaded;
        NATIVE_LOAD_ERROR = error;
    }

    private LlamaBridge() {}

    public static boolean isRuntimeAvailable() {
        return NATIVE_AVAILABLE;
    }

    public static String version() throws IOException {
        requireNative();
        String version = nativeVersion();
        if (version == null || version.isEmpty()) {
            throw new IOException("local llama runtime version unavailable");
        }
        return version;
    }

    public static Session open(File modelFile) throws IOException {
        requireNative();
        if (modelFile == null
                || !modelFile.isFile()
                || !modelFile.canRead()) {
            throw new IOException("local model file is missing or unreadable");
        }
        long handle = nativeOpen(modelFile.getAbsolutePath());
        if (handle == 0L) {
            throw new IOException("llama.cpp could not load local model");
        }
        return new Session(handle);
    }

    public static final class GenerationConfig {
        public final int maxTokens;
        public final int maxOutputChars;
        public final int contextTokens;
        public final int threads;
        public final int topK;
        public final float topP;
        public final float temperature;
        public final long seed;
        public final long maxGenerationMs;

        public GenerationConfig(
                int maxTokens,
                int maxOutputChars,
                int contextTokens,
                int threads,
                int topK,
                float topP,
                float temperature,
                long seed,
                long maxGenerationMs) {
            if (maxTokens < 1 || maxTokens > MAX_GENERATED_TOKENS) {
                throw new IllegalArgumentException(
                    "invalid local generation token limit");
            }
            if (maxOutputChars < 1
                    || maxOutputChars > MAX_OUTPUT_CHARS) {
                throw new IllegalArgumentException(
                    "invalid local generation output limit");
            }
            if (contextTokens < 256
                    || contextTokens > MAX_CONTEXT_TOKENS) {
                throw new IllegalArgumentException(
                    "invalid local generation context limit");
            }
            if (threads < 1 || threads > MAX_THREADS) {
                throw new IllegalArgumentException(
                    "invalid local generation thread count");
            }
            if (topK < 0 || topK > 200) {
                throw new IllegalArgumentException(
                    "invalid local generation top-k");
            }
            if (Float.isNaN(topP)
                    || topP <= 0.0f
                    || topP > 1.0f) {
                throw new IllegalArgumentException(
                    "invalid local generation top-p");
            }
            if (Float.isNaN(temperature)
                    || temperature < 0.0f
                    || temperature > 2.0f) {
                throw new IllegalArgumentException(
                    "invalid local generation temperature");
            }
            if (maxGenerationMs < 1_000L
                    || maxGenerationMs > 5L * 60L * 1_000L) {
                throw new IllegalArgumentException(
                    "invalid local generation time limit");
            }
            this.maxTokens = maxTokens;
            this.maxOutputChars = maxOutputChars;
            this.contextTokens = contextTokens;
            this.threads = threads;
            this.topK = topK;
            this.topP = topP;
            this.temperature = temperature;
            this.seed = seed;
            this.maxGenerationMs = maxGenerationMs;
        }

        public static GenerationConfig plannerDefaults() {
            int threads = Math.max(
                1,
                Math.min(4, Runtime.getRuntime().availableProcessors()));
            return new GenerationConfig(
                1024,
                MAX_OUTPUT_CHARS,
                4096,
                threads,
                20,
                0.8f,
                0.0f,
                20261001L,
                60_000L);
        }
    }

    public static final class Session implements AutoCloseable {
        private volatile long handle;

        private Session(long handle) {
            this.handle = handle;
        }

        public synchronized String description() throws IOException {
            ensureOpen();
            String value = nativeDescription(handle);
            if (value == null || value.isEmpty()) {
                throw new IOException("local model description unavailable");
            }
            return value;
        }

        public synchronized long modelSizeBytes() throws IOException {
            ensureOpen();
            long value = nativeModelSizeBytes(handle);
            if (value < 0L) {
                throw new IOException("local model size unavailable");
            }
            return value;
        }

        public synchronized String generate(
                String prompt,
                GenerationConfig config) throws IOException {
            ensureOpen();
            if (prompt == null
                    || prompt.isEmpty()
                    || prompt.length() > MAX_PROMPT_CHARS) {
                throw new IllegalArgumentException(
                    "invalid local generation prompt");
            }
            if (config == null) {
                throw new IllegalArgumentException(
                    "local generation config missing");
            }

            byte[] promptUtf8 = prompt.getBytes(StandardCharsets.UTF_8);
            if (promptUtf8.length > MAX_PROMPT_UTF8_BYTES) {
                throw new IllegalArgumentException(
                    "local generation prompt exceeds UTF-8 byte limit");
            }

            byte[] raw = nativeGenerateBytes(
                handle,
                promptUtf8,
                config.maxTokens,
                config.maxOutputChars,
                config.contextTokens,
                config.threads,
                config.topK,
                config.topP,
                config.temperature,
                config.seed,
                config.maxGenerationMs);
            if (raw == null) {
                throw new IOException("local model returned no generation");
            }

            String output = new String(raw, StandardCharsets.UTF_8);
            if (output.length() > config.maxOutputChars) {
                throw new IOException(
                    "local model decoded output exceeds limit");
            }
            return output;
        }

        public int generationPhase() {
            long current = handle;
            if (current == 0L) return GENERATION_PHASE_NONE;
            return nativeGenerationPhase(current);
        }

        public boolean generationTimedOut() {
            long current = handle;
            return current != 0L && nativeGenerationTimedOut(current);
        }

        public void cancelGeneration() {
            long current = handle;
            if (current != 0L) {
                nativeCancelGeneration(current);
            }
        }

        public synchronized boolean isOpen() {
            return handle != 0L;
        }

        @Override
        public synchronized void close() {
            if (handle == 0L) return;
            nativeClose(handle);
            handle = 0L;
        }

        private void ensureOpen() throws IOException {
            if (handle == 0L) {
                throw new IOException("local model session is closed");
            }
        }
    }

    private static void requireNative() throws IOException {
        if (!NATIVE_AVAILABLE) {
            throw new IOException(
                "local llama runtime is not packaged"
                    + (NATIVE_LOAD_ERROR.isEmpty()
                        ? ""
                        : " (" + NATIVE_LOAD_ERROR + ")"));
        }
    }

    private static native String nativeVersion();
    private static native long nativeOpen(String modelPath);
    private static native String nativeDescription(long handle);
    private static native long nativeModelSizeBytes(long handle);
    private static native byte[] nativeGenerateBytes(
        long handle,
        byte[] promptUtf8,
        int maxTokens,
        int maxOutputChars,
        int contextTokens,
        int threads,
        int topK,
        float topP,
        float temperature,
        long seed,
        long maxGenerationMs) throws IOException;
    private static native int nativeGenerationPhase(long handle);
    private static native boolean nativeGenerationTimedOut(long handle);
    private static native void nativeCancelGeneration(long handle);
    private static native void nativeClose(long handle);
}
