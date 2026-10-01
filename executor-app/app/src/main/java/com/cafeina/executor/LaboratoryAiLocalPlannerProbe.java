package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;
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

        cancellation.throwIfCancelled();

        Context app = context.getApplicationContext();
        String safeProjectId = projectId == null ? "" : projectId;

        LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
            LaboratoryAiLocalModelAdmission.admit(
                app.getFilesDir(), modelFile);
        LaboratoryAiLocalModelPreflight.Report preflight =
            LaboratoryAiLocalModelPreflight.inspect(app, admitted);
        if (!preflight.canAttemptLoad) {
            throw new IOException(
                "local planner preflight blocked load: "
                    + preflight.signalCodes);
        }

        try (LaboratoryAiLlamaCppBackend backend =
                LaboratoryAiLocalModelPreflight.open(
                    app,
                    modelFile,
                    LaboratoryAiLlamaCppBackend.RuntimeConfig
                        .plannerDefaults())) {
            cancellation.attach(backend);
            try {
                cancellation.throwIfCancelled();

                String runtimeVersion = backend.runtimeVersion();
                String modelDescription = backend.modelDescription();
                LaboratoryAiLocalModelTestPlannerGateway gateway =
                    new LaboratoryAiLocalModelTestPlannerGateway(backend);

                LaboratoryAiLlmTestPlanner.Result planner =
                    LaboratoryAiLlmTestPlanner.plan(
                        app,
                        safeProjectId,
                        contractId,
                        request -> {
                            cancellation.throwIfCancelled();
                            return gateway.propose(request);
                        });

                cancellation.throwIfCancelled();
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
    }
}
