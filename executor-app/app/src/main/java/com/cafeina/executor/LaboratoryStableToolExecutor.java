package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Narrow internal execution gate intended for the future AI controller.
 *
 * The caller chooses only a tool ID and bounded input. It cannot provide source,
 * version, snapshot or capabilities. Those are resolved from the current
 * verified STABLE activation. Luau still executes only in the isolated worker.
 */
public final class LaboratoryStableToolExecutor {
    public interface Completion {
        /**
         * success is non-null only when the selection stayed valid throughout
         * execution, the worker returned EXECUTED, and the audit receipt saved.
         */
        void onFinished(Execution success, IOException failure);
    }

    public static final class Execution {
        public final String toolId;
        public final String toolVersion;
        public final String runId;
        public final String output;
        public final String firstReturn;
        public final long durationMs;
        public final LaboratoryStableUseStore.Use audit;

        private Execution(LaboratoryStableActivationStore.Active active,
                LaboratorySandboxClient.Result result,
                LaboratoryStableUseStore.Use audit) {
            this.toolId = active.toolId;
            this.toolVersion = active.version;
            this.runId = result.runId;
            this.output = result.output;
            this.firstReturn = result.firstReturn;
            this.durationMs = result.durationMs;
            this.audit = audit;
        }
    }

    private static final ExecutorService AUDIT_IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private LaboratoryStableToolExecutor() {}

    /**
     * Must begin off the UI thread because it verifies disk-backed control
     * records before binding the isolated process. No public Activity calls it.
     */
    public static LaboratorySandboxClient.Session executeInternal(
            Context context, String projectId, String toolId, String toolInput,
            Completion completion) throws IOException {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(completion, "completion");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("STABLE tool execution must start off UI thread");
        }
        if (toolInput == null
                || toolInput.length() > LaboratorySandboxService.MAX_INPUT_CHARS) {
            throw new IllegalArgumentException("stable tool input exceeds limit");
        }

        Context app = context.getApplicationContext();
        LaboratoryStableActivationStore stable =
            new LaboratoryStableActivationStore(app.getFilesDir(), projectId);
        LaboratoryStableActivationStore.Active authorization = stable.current(toolId);
        if (authorization == null) {
            throw new IOException("tool has no active STABLE version");
        }

        LaboratoryToolRegistry.Tool tool =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId)
                .read(toolId, authorization.version);
        if (!"LUAU_ISOLATED_NO_FILES".equals(tool.capability)
                || !tool.manifestSha256.equals(authorization.manifestSha256)
                || !tool.sourceSha256.equals(authorization.sourceSha256)
                || !tool.snapshotId.equals(authorization.snapshotId)
                || !tool.evidenceRunId.equals(authorization.evidenceRunId)) {
            throw new IOException("active STABLE selection no longer matches tool registry");
        }

        LaboratorySnapshotStore.Snapshot snapshot =
            new LaboratorySnapshotStore(app.getFilesDir(), projectId)
                .readCopy(authorization.snapshotId);
        if (!"candidate-luau".equals(snapshot.label)
                || !snapshot.sha256.equals(authorization.sourceSha256)) {
            throw new IOException("active STABLE source snapshot failed integrity check");
        }
        byte[] bytes = snapshot.contentCopy();
        String source = new String(bytes, StandardCharsets.UTF_8);
        if (source.isEmpty()
                || source.length() > LaboratorySandboxService.MAX_SOURCE_CHARS
                || !Arrays.equals(bytes, source.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("active STABLE source is not bounded UTF-8");
        }

        LaboratoryStableUseStore uses =
            new LaboratoryStableUseStore(app.getFilesDir(), projectId);
        uses.ensureWritable();

        return LaboratorySandboxClient.execute(
            app, source, toolInput, tool.timeoutMs, result ->
                AUDIT_IO.execute(() -> {
                    IOException failure = null;
                    boolean selectionVerified = false;
                    LaboratoryStableUseStore.Use audit = null;
                    try {
                        LaboratoryStableActivationStore.Active after =
                            stable.current(toolId);
                        selectionVerified = after != null
                            && after.activationEventSha256.equals(
                                authorization.activationEventSha256)
                            && after.version.equals(authorization.version);
                    } catch (IOException changedOrBroken) {
                        failure = changedOrBroken;
                    }

                    try {
                        audit = uses.save(authorization, result, selectionVerified);
                    } catch (IOException recording) {
                        if (failure != null) recording.addSuppressed(failure);
                        failure = recording;
                    }

                    final LaboratoryStableUseStore.Use saved = audit;
                    final IOException infrastructureFailure = failure;
                    if (infrastructureFailure == null && saved != null && saved.usable) {
                        Execution execution =
                            new Execution(authorization, result, saved);
                        MAIN.post(() -> completion.onFinished(execution, null));
                    } else {
                        String reason = infrastructureFailure != null
                            ? infrastructureFailure.getMessage()
                            : !selectionVerified
                                ? "STABLE selection changed during execution"
                                : "isolated worker status: " + result.status;
                        IOException rejected = infrastructureFailure != null
                            ? infrastructureFailure : new IOException(reason);
                        MAIN.post(() -> completion.onFinished(null, rejected));
                    }
                }));
    }
}
