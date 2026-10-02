package com.cafeina.executor;

import com.cafeina.runtime.LlamaBridge;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * llama.cpp implementation of the planner's runtime-neutral local model backend.
 *
 * This object owns only an admitted app-private GGUF model session and text
 * generation. It has no Android Context, LaboratoryAiTaskHandle, tool executor,
 * permission store, approval store, or Goal Lock mutation surface.
 */
public final class LaboratoryAiLlamaCppBackend
        implements LaboratoryAiLocalModelBackend, AutoCloseable {

    public interface GenerationObserver {
        void onNativePhase(int phase);

        default void onNativeMetrics(
                LlamaBridge.GenerationMetrics metrics) {
        }
    }

    public static final class RuntimeConfig {
        public final int maxTokens;
        public final int contextTokens;
        public final int threads;
        public final int topK;
        public final float topP;
        public final long maxGenerationMs;

        public RuntimeConfig(
                int maxTokens,
                int contextTokens,
                int threads,
                int topK,
                float topP,
                long maxGenerationMs) {
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
            if (topK < 0 || topK > 200) {
                throw new IllegalArgumentException(
                    "invalid llama backend top-k");
            }
            if (Float.isNaN(topP)
                    || topP <= 0.0f
                    || topP > 1.0f) {
                throw new IllegalArgumentException(
                    "invalid llama backend top-p");
            }
            if (maxGenerationMs < 1_000L
                    || maxGenerationMs > 5L * 60L * 1_000L) {
                throw new IllegalArgumentException(
                    "invalid llama backend generation time limit");
            }
            this.maxTokens = maxTokens;
            this.contextTokens = contextTokens;
            this.threads = threads;
            this.topK = topK;
            this.topP = topP;
            this.maxGenerationMs = maxGenerationMs;
        }

        public static RuntimeConfig smokeTestDefaults() {
            int threads = Math.max(
                1,
                Math.min(4, Runtime.getRuntime().availableProcessors()));
            return new RuntimeConfig(
                32,
                1024,
                threads,
                20,
                0.8f,
                90_000L);
        }

        public static RuntimeConfig plannerDefaults() {
            int threads = Math.max(
                1,
                Math.min(4, Runtime.getRuntime().availableProcessors()));
            return new RuntimeConfig(
                1024,
                4096,
                threads,
                20,
                0.8f,
                120_000L);
        }
    }

    private final LlamaBridge.Session session;
    private final RuntimeConfig config;
    private final GenerationObserver generationObserver;
    private volatile boolean closed;

    private LaboratoryAiLlamaCppBackend(
            LlamaBridge.Session session,
            RuntimeConfig config,
            GenerationObserver generationObserver) {
        this.session = session;
        this.config = config;
        this.generationObserver = generationObserver;
    }

    static LaboratoryAiLlamaCppBackend open(
            LaboratoryAiLocalModelAdmission.AdmittedModel admittedModel,
            RuntimeConfig config) throws IOException {
        return open(admittedModel, config, null);
    }

    static LaboratoryAiLlamaCppBackend open(
            LaboratoryAiLocalModelAdmission.AdmittedModel admittedModel,
            RuntimeConfig config,
            GenerationObserver generationObserver) throws IOException {
        if (admittedModel == null) {
            throw new IllegalArgumentException(
                "admitted local model missing");
        }
        if (config == null) {
            throw new IllegalArgumentException(
                "llama backend runtime config missing");
        }
        return new LaboratoryAiLlamaCppBackend(
            LlamaBridge.open(admittedModel.fileForRuntime()),
            config,
            generationObserver);
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
                config.topK,
                config.topP,
                request.temperature,
                request.seed,
                config.maxGenerationMs);

        final AtomicBoolean monitoring =
            new AtomicBoolean(generationObserver != null);
        Thread phaseMonitor = null;
        if (generationObserver != null) {
            phaseMonitor = new Thread(() -> {
                int lastPhase = Integer.MIN_VALUE;
                while (monitoring.get()) {
                    LlamaBridge.GenerationMetrics metrics =
                        session.generationMetrics();
                    if (metrics.phase != lastPhase) {
                        lastPhase = metrics.phase;
                        try {
                            generationObserver.onNativePhase(
                                metrics.phase);
                        } catch (RuntimeException ignored) {
                            // Observability must never control generation.
                        }
                    }
                    try {
                        generationObserver.onNativeMetrics(metrics);
                    } catch (RuntimeException ignored) {
                        // Telemetry must never control generation.
                    }
                    try {
                        Thread.sleep(250L);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
            }, "cafeina-llm-phase");
            phaseMonitor.setDaemon(true);
            phaseMonitor.start();
        }

        try {
            String output = session.generate(request.prompt, generation);
            publishFinalTelemetry();
            if (output.length() > request.maxOutputChars) {
                throw new IOException(
                    "llama backend output exceeds planner limit");
            }
            return output;
        } catch (IOException failure) {
            publishFinalTelemetry();
            throw failure;
        } finally {
            monitoring.set(false);
            if (phaseMonitor != null) {
                phaseMonitor.interrupt();
                try {
                    phaseMonitor.join(250L);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            }
        }
    }

    private void publishFinalTelemetry() {
        if (generationObserver == null) return;
        try {
            LlamaBridge.GenerationMetrics metrics =
                session.generationMetrics();
            generationObserver.onNativePhase(metrics.phase);
            generationObserver.onNativeMetrics(metrics);
        } catch (RuntimeException ignored) {
            // Preserve generation result/failure as authoritative.
        }
    }

    public void cancelGeneration() {
        if (!closed) {
            session.cancelGeneration();
        }
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
