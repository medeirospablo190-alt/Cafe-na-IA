package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.File;
import java.io.IOException;

/**
 * Real on-device planning probe.
 *
 * This is deliberately planning-only. It opens an already imported/admitted
 * local model, routes generation through the planner gateway and returns only
 * the validated planner result. It never claims the Goal Lock and never
 * executes a tool or TestAgent plan.
 */
public final class LaboratoryAiLocalPlannerProbe {
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
        if (context == null
                || contractId == null
                || contractId.isEmpty()
                || modelFile == null) {
            throw new IllegalArgumentException(
                "local planner probe input missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "local planner probe must run off the UI thread");
        }

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
            String runtimeVersion = backend.runtimeVersion();
            String modelDescription = backend.modelDescription();

            LaboratoryAiLlmTestPlanner.Result planner =
                LaboratoryAiLlmTestPlanner.plan(
                    app,
                    safeProjectId,
                    contractId,
                    new LaboratoryAiLocalModelTestPlannerGateway(backend));

            return new Result(
                admitted.fileName,
                preflight,
                runtimeVersion,
                modelDescription,
                planner);
        }
    }
}
