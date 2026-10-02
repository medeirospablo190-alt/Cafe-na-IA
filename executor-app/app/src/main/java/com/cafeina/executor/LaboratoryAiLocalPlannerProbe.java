package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import com.cafeina.runtime.LlamaBridge;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Real on-device planning probe.
 *
 * This is deliberately planning-only. It opens an already imported/admitted
 * local model, routes generation through the planner gateway and returns only
 * the validated planner result. It never claims the Goal Lock and never
 * executes a tool or TestAgent plan.
 */
public final class LaboratoryAiLocalPlannerProbe {
    public static final class Cancellation {
        private final AtomicBoolean cancelled = new AtomicBoolean(false);
        private final AtomicReference<LaboratoryAiLlamaCppBackend> active =
            new AtomicReference<>();

        public void cancel() {
            cancelled.set(true);
            LaboratoryAiLlamaCppBackend backend = active.get();
            if (backend != null) {
                backend.cancelGeneration();
            }
        }

        public boolean isCancelled() {
            return cancelled.get();
        }

        void throwIfCancelled() throws IOException {
            if (cancelled.get()) {
                throw new IOException("local planner cancelled");
            }
        }

        void attach(LaboratoryAiLlamaCppBackend backend)
                throws IOException {
            if (backend == null) {
                throw new IllegalArgumentException(
                    "local planner cancellation backend missing");
            }
            active.set(backend);
            if (cancelled.get()) {
                backend.cancelGeneration();
                throw new IOException("local planner cancelled");
            }
        }

        void detach(LaboratoryAiLlamaCppBackend backend) {
            active.compareAndSet(backend, null);
        }
    }

    public static final class Result {
        public final String modelFileName;
        public final LaboratoryAiLocalModelPreflight.Report preflight;
        public final String runtimeVersion;
        public final String modelDescription;
        public final LaboratoryAiLlmTestPlanner.Result planner;

        private Result(
                String modelFileName,
                LaboratoryAiLocalModelPreflight.Report preflight,
                String runtimeVersion,
                String modelDescription,
                LaboratoryAiLlmTestPlanner.Result planner) {
            this.modelFileName = modelFileName;
            this.preflight = preflight;
            this.runtimeVersion = runtimeVersion;
            this.modelDescription = modelDescription;
            this.planner = planner;
        }
    }

    private LaboratoryAiLocalPlannerProbe() {}

    public static Result plan(
            Context context,
            String projectId,
            String contractId,
            File modelFile) throws IOException {
        return plan(
            context,
            projectId,
            contractId,
            modelFile,
            new Cancellation());
    }

    public static Result plan(
            Context context,
            String projectId,
            String contractId,
            File modelFile,
            Cancellation cancellation) throws IOException {
        return plan(
            context,
            projectId,
            contractId,
            modelFile,
            cancellation,
            null);
    }

    public static Result plan(
            Context context,
            String projectId,
            String contractId,
            File modelFile,
            Cancellation cancellation,
            LaboratoryAiExecutionStatus.Tracker status) throws IOException {
        if (context == null
                || contractId == null
                || contractId.isEmpty()
                || modelFile == null
                || cancellation == null) {
            throw new IllegalArgumentException(
                "local planner probe input missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "local planner probe must run off the UI thread");
        }

        final AtomicInteger activeAttempt = new AtomicInteger(0);

        try {
            cancellation.throwIfCancelled();
            update(
                status,
                LaboratoryAiExecutionStatus.Phase.MODEL_ADMISSION,
                "Validando modelo local admitido");

            Context app = context.getApplicationContext();
            String safeProjectId = projectId == null ? "" : projectId;

            LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
                LaboratoryAiLocalModelAdmission.admit(
                    app.getFilesDir(), modelFile);
            LaboratoryAiLlamaCppBackend.RuntimeConfig runtimeConfig =
                LaboratoryAiLlamaCppBackend.RuntimeConfig
                    .plannerDefaults();

            update(
                status,
                LaboratoryAiExecutionStatus.Phase.PREFLIGHT,
                "Verificando runtime, memória e modelo");
            LaboratoryAiLocalModelPreflight.Report preflight =
                LaboratoryAiLocalModelPreflight.inspect(app, admitted);
            try {
                new LaboratoryAiPlannerEnvironmentStore(
                    app.getFilesDir(), safeProjectId)
                    .writePreflight(
                        contractId,
                        admitted,
                        preflight,
                        runtimeConfig);
            } catch (Exception ignored) {
                // Environment diagnostics never control planning.
            }
            if (!preflight.canAttemptLoad) {
                throw new IOException(
                    "local planner preflight blocked load: "
                        + preflight.signalCodes);
            }

            update(
                status,
                LaboratoryAiExecutionStatus.Phase.MODEL_OPEN,
                "Abrindo modelo local");
            try (LaboratoryAiLlamaCppBackend backend =
                    LaboratoryAiLocalModelPreflight.open(
                        app,
                        modelFile,
                        runtimeConfig,
                        new LaboratoryAiLlamaCppBackend.GenerationObserver() {
                            @Override
                            public void onNativePhase(int phase) {
                                if (status != null) {
                                    status.updateNativePhase(
                                        phase,
                                        activeAttempt.get(),
                                        LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS);
                                }
                            }

                            @Override
                            public void onNativeMetrics(
                                    LlamaBridge.GenerationMetrics metrics) {
                                if (status == null || metrics == null) return;
                                status.updateNativeTelemetry(
                                    metrics.phase,
                                    metrics.promptTokens,
                                    metrics.promptTokensProcessed,
                                    metrics.generatedTokens,
                                    metrics.maxGeneratedTokens,
                                    metrics.contextSetupMs,
                                    metrics.promptEvalMs,
                                    metrics.tokenGenerationMs,
                                    metrics.generationTimeLimitMs,
                                    activeAttempt.get(),
                                    LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS);
                            }
                        })) {
                cancellation.attach(backend);
                try {
                    cancellation.throwIfCancelled();

                    update(
                        status,
                        LaboratoryAiExecutionStatus.Phase.RUNTIME_METADATA,
                        "Lendo versão do runtime e descrição do modelo");
                    String runtimeVersion = backend.runtimeVersion();
                    String modelDescription = backend.modelDescription();
                    try {
                        new LaboratoryAiPlannerEnvironmentStore(
                            app.getFilesDir(), safeProjectId)
                            .updateRuntimeMetadata(
                                contractId,
                                runtimeVersion,
                                modelDescription);
                    } catch (Exception ignored) {
                        // Environment diagnostics never control planning.
                    }
                    LaboratoryAiLocalModelTestPlannerGateway gateway =
                        new LaboratoryAiLocalModelTestPlannerGateway(backend);

                    LaboratoryAiLlmTestPlanner.Result planner =
                        LaboratoryAiLlmTestPlanner.plan(
                            app,
                            safeProjectId,
                            contractId,
                            request -> {
                                cancellation.throwIfCancelled();
                                activeAttempt.set(request.attempt);
                                if (status != null) {
                                    status.update(
                                        LaboratoryAiExecutionStatus.Phase.PLANNING,
                                        "Gerando proposta de plano JSON",
                                        request.attempt,
                                        LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS);
                                }
                                String draft = gateway.propose(request);
                                if (status != null) {
                                    status.update(
                                        LaboratoryAiExecutionStatus.Phase.VALIDATING,
                                        "Validando proposta determinística",
                                        request.attempt,
                                        LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS);
                                }
                                return draft;
                            });

                    cancellation.throwIfCancelled();
                    if (status != null) {
                        int attempt = Math.max(
                            activeAttempt.get(), planner.attempts);
                        status.complete(
                            planner.accepted
                                ? "Plano produzido e validado"
                                : "Planejamento concluído com plano rejeitado",
                            attempt,
                            LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS);
                    }
                    return new Result(
                        admitted.fileName,
                        preflight,
                        runtimeVersion,
                        modelDescription,
                        planner);
                } finally {
                    cancellation.detach(backend);
                }
            }
        } catch (IOException | RuntimeException error) {
            if (status != null) {
                if (cancellation.isCancelled()) {
                    status.cancel("Planejamento cancelado pelo usuário");
                } else {
                    status.fail(String.valueOf(error.getMessage()));
                }
            }
            throw error;
        }
    }

    private static void update(
            LaboratoryAiExecutionStatus.Tracker status,
            LaboratoryAiExecutionStatus.Phase phase,
            String detail) {
        if (status != null) status.update(phase, detail);
    }
}
