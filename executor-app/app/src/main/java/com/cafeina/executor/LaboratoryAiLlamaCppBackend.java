package com.cafeina.executor;

import com.cafeina.runtime.LlamaBridge;

import java.io.File;
import java.io.IOException;

/**
 * llama.cpp implementation of the planner's runtime-neutral local model backend.
 *
 * This object owns only a local GGUF model session and text generation. It has
 * no Android Context, LaboratoryAiTaskHandle, tool executor, permission store,
 * approval store, or Goal Lock mutation surface.
 */
public final class LaboratoryAiLlamaCppBackend
        implements LaboratoryAiLocalModelBackend, AutoCloseable {

    public static final class RuntimeConfig {
        public final int maxTokens;
        public final int contextTokens;
        public final int threads;

        public RuntimeConfig(
                int maxTokens,
                int contextTokens,
                int threads) {
            if (maxTokens < 1
                    || maxTokens > LlamaBridge.MAX_GENERATED_TOKENS) {
                throw new IllegalArgumentException(
                    "invalid llama backend token limit");
            }
            if (contextTokens < 256
                    || contextTokens > LlamaBridge.MAX_CONTEXT_TOKENS) {
                throw new IllegalArgumentException(
                    "invalid llama backend context limit");
            }
            if (threads < 1 || threads > LlamaBridge.MAX_THREADS) {
                throw new IllegalArgumentException(
                    "invalid llama backend thread count");
            }
            this.maxTokens = maxTokens;
            this.contextTokens = contextTokens;
            this.threads = threads;
        }

        public static RuntimeConfig plannerDefaults() {
            int threads = Math.max(
                1,
                Math.min(4, Runtime.getRuntime().availableProcessors()));
            return new RuntimeConfig(1024, 4096, threads);
        }
    }

    private final LlamaBridge.Session session;
    private final RuntimeConfig config;
    private boolean closed;

    private LaboratoryAiLlamaCppBackend(
            LlamaBridge.Session session,
            RuntimeConfig config) {
        this.session = session;
        this.config = config;
    }

    public static LaboratoryAiLlamaCppBackend open(
            File modelFile,
            RuntimeConfig config) throws IOException {
        if (config == null) {
            throw new IllegalArgumentException(
                "llama backend runtime config missing");
        }
        return new LaboratoryAiLlamaCppBackend(
            LlamaBridge.open(modelFile),
            config);
    }

    public static boolean isRuntimePackaged() {
        return LlamaBridge.isRuntimeAvailable();
    }

    public synchronized String runtimeVersion() throws IOException {
        ensureOpen();
        return LlamaBridge.version();
    }

    public synchronized String modelDescription() throws IOException {
        ensureOpen();
        return session.description();
    }

    public synchronized long modelSizeBytes() throws IOException {
        ensureOpen();
        return session.modelSizeBytes();
    }

    @Override
    public synchronized String generate(GenerationRequest request)
            throws IOException {
        ensureOpen();
        if (request == null) {
            throw new IllegalArgumentException(
                "llama backend generation request missing");
        }

        LlamaBridge.GenerationConfig generation =
            new LlamaBridge.GenerationConfig(
                config.maxTokens,
                request.maxOutputChars,
                config.contextTokens,
                config.threads,
                request.temperature,
                request.seed);

        String output = session.generate(request.prompt, generation);
        if (output.length() > request.maxOutputChars) {
            throw new IOException(
                "llama backend output exceeds planner limit");
        }
        return output;
    }

    @Override
    public synchronized void close() {
        if (closed) return;
        closed = true;
        session.close();
    }

    public synchronized boolean isClosed() {
        return closed;
    }

    private void ensureOpen() throws IOException {
        if (closed || !session.isOpen()) {
            throw new IOException("llama backend is closed");
        }
    }
}
