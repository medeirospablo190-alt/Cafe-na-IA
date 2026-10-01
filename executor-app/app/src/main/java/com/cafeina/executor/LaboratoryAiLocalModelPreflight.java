package com.cafeina.executor;

import android.app.ActivityManager;
import android.content.Context;
import android.os.Looper;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Read-only device/model preflight before a local planner model may be opened.
 *
 * It records facts exposed by Android and applies only two hard gates:
 * the native runtime must be packaged and Android must not already report
 * low-memory pressure. Model-size versus currently available RAM is surfaced
 * as an attention signal, not treated as a guarantee of failure or success.
 */
public final class LaboratoryAiLocalModelPreflight {
    public static final String STATUS_READY = "READY";
    public static final String STATUS_ATTENTION = "ATTENTION";
    public static final String STATUS_BLOCKED = "BLOCKED";

    public static final String RUNTIME_NOT_PACKAGED =
        "RUNTIME_NOT_PACKAGED";
    public static final String ANDROID_LOW_MEMORY =
        "ANDROID_LOW_MEMORY";
    public static final String MODEL_LARGER_THAN_AVAILABLE_RAM =
        "MODEL_LARGER_THAN_AVAILABLE_RAM";

    public static final class Report {
        public final String status;
        public final boolean canAttemptLoad;
        public final boolean runtimePackaged;
        public final boolean androidLowMemory;
        public final long modelSizeBytes;
        public final long totalRamBytes;
        public final long availableRamBytes;
        public final long lowMemoryThresholdBytes;
        public final long appUsableStorageBytes;
        public final int cpuCores;
        public final List<String> signalCodes;

        private Report(
                String status,
                boolean canAttemptLoad,
                boolean runtimePackaged,
                boolean androidLowMemory,
                long modelSizeBytes,
                long totalRamBytes,
                long availableRamBytes,
                long lowMemoryThresholdBytes,
                long appUsableStorageBytes,
                int cpuCores,
                List<String> signalCodes) {
            this.status = status;
            this.canAttemptLoad = canAttemptLoad;
            this.runtimePackaged = runtimePackaged;
            this.androidLowMemory = androidLowMemory;
            this.modelSizeBytes = modelSizeBytes;
            this.totalRamBytes = totalRamBytes;
            this.availableRamBytes = availableRamBytes;
            this.lowMemoryThresholdBytes = lowMemoryThresholdBytes;
            this.appUsableStorageBytes = appUsableStorageBytes;
            this.cpuCores = cpuCores;
            this.signalCodes = Collections.unmodifiableList(
                new ArrayList<>(signalCodes));
        }
    }

    private LaboratoryAiLocalModelPreflight() {}

    public static Report inspect(
            Context context,
            LaboratoryAiLocalModelAdmission.AdmittedModel model)
            throws IOException {
        if (context == null || model == null) {
            throw new IllegalArgumentException(
                "local model preflight input missing");
        }

        Context app = context.getApplicationContext();
        ActivityManager manager =
            app.getSystemService(ActivityManager.class);
        if (manager == null) {
            throw new IOException(
                "Android memory service unavailable for local model preflight");
        }

        ActivityManager.MemoryInfo memory =
            new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(memory);

        boolean runtimePackaged =
            LaboratoryAiLlamaCppBackend.isRuntimePackaged();
        int cores = Math.max(
            1, Runtime.getRuntime().availableProcessors());
        long usableStorage = Math.max(
            0L, app.getFilesDir().getUsableSpace());

        List<String> signals = new ArrayList<>();
        if (!runtimePackaged) {
            signals.add(RUNTIME_NOT_PACKAGED);
        }
        if (memory.lowMemory) {
            signals.add(ANDROID_LOW_MEMORY);
        }
        if (memory.availMem > 0L
                && model.sizeBytes > memory.availMem) {
            signals.add(MODEL_LARGER_THAN_AVAILABLE_RAM);
        }

        boolean canAttemptLoad =
            runtimePackaged && !memory.lowMemory;
        String status;
        if (!canAttemptLoad) {
            status = STATUS_BLOCKED;
        } else if (!signals.isEmpty()) {
            status = STATUS_ATTENTION;
        } else {
            status = STATUS_READY;
        }

        return new Report(
            status,
            canAttemptLoad,
            runtimePackaged,
            memory.lowMemory,
            model.sizeBytes,
            Math.max(0L, memory.totalMem),
            Math.max(0L, memory.availMem),
            Math.max(0L, memory.threshold),
            usableStorage,
            cores,
            signals);
    }

    /**
     * Public app-facing load path. Admission and device preflight happen before
     * the native model loader is reached.
     */
    public static LaboratoryAiLlamaCppBackend open(
            Context context,
            File modelFile,
            LaboratoryAiLlamaCppBackend.RuntimeConfig config)
            throws IOException {
        if (context == null) {
            throw new IllegalArgumentException(
                "local model preflight context missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "local model must be opened off the UI thread");
        }

        Context app = context.getApplicationContext();
        LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
            LaboratoryAiLocalModelAdmission.admit(
                app.getFilesDir(), modelFile);
        Report report = inspect(app, admitted);
        if (!report.canAttemptLoad) {
            throw new IOException(
                "local model preflight blocked load: "
                    + report.signalCodes);
        }
        return LaboratoryAiLlamaCppBackend.open(
            admitted, config);
    }
}
