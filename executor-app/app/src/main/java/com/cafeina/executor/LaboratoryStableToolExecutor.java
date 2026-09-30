package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Narrow execution path intended for the future AI controller.
 *
 * The caller chooses only a tool ID and bounded tool_input. Version, source,
 * snapshot and runtime budget are resolved from the current verified STABLE
 * selection. Candidate/experimental code cannot be supplied through this API.
 */
public final class LaboratoryStableToolExecutor {
    public static final String REQUIRED_CAPABILITY = "luau-isolated-no-files";

    public interface Completion {
        /**
         * success is non-null only after the worker returned EXECUTED, the same
         * STABLE selection was revalidated after execution, and the audit
         * receipt was durably saved.
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

        private Execution(Selection selection,
                LaboratorySandboxClient.Result result,
                LaboratoryStableUseStore.Use audit) {
            this.toolId = selection.descriptor.toolId;
            this.toolVersion = selection.descriptor.version;
            this.runId = result.runId;
            this.output = result.output;
            this.firstReturn = result.firstReturn;
            this.durationMs = result.durationMs;
            this.audit = audit;
        }
    }

    private static final class Selection {
        final LaboratoryToolRegistry.Descriptor descriptor;
        final LaboratoryToolRegistry.Event lifecycleEvent;
        final LaboratoryToolArtifactStore.Binding binding;

        Selection(LaboratoryToolRegistry.Descriptor descriptor,
                LaboratoryToolRegistry.Event lifecycleEvent,
                LaboratoryToolArtifactStore.Binding binding) {
            this.descriptor = descriptor;
            this.lifecycleEvent = lifecycleEvent;
            this.binding = binding;
        }
    }

    private static final ExecutorService AUDIT_IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private LaboratoryStableToolExecutor() {}

    public static LaboratorySandboxClient.Session executeInternal(
            Context context, String projectId, String toolId, String toolInput,
            Completion completion) throws IOException {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(completion, "completion");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("STABLE tool preflight must run off the UI thread");
        }
        if (toolInput == null
                || toolInput.length() > LaboratorySandboxService.MAX_INPUT_CHARS) {
            throw new IllegalArgumentException("stable tool input exceeds Android limit");
        }

        Context app = context.getApplicationContext();
        Selection before = resolveSelection(app, projectId, toolId);
        if (!before.descriptor.capabilities.contains(REQUIRED_CAPABILITY)) {
            throw new IOException("active STABLE tool lacks isolated execution capability");
        }

        int inputBytes = toolInput.getBytes(StandardCharsets.UTF_8).length;
        if (inputBytes > before.descriptor.maxInputBytes) {
            throw new IOException("stable tool input exceeds registered tool limit");
        }

        int timeoutMs = Math.min(before.descriptor.maxRuntimeMs,
            LaboratorySandboxService.MAX_TIMEOUT_MS);
        if (timeoutMs < 1) throw new IOException("stable tool runtime limit is invalid");

        LaboratoryStableUseStore audit =
            new LaboratoryStableUseStore(app.getFilesDir(), projectId);
        audit.ensureWritable();

        String expectedInputSha =
            LaboratoryEngine.fingerprint(toolInput).substring(7, 71);
        String source = before.binding.luauSource();

        return LaboratorySandboxClient.execute(
            app, source, toolInput, timeoutMs, result ->
                AUDIT_IO.execute(() -> finish(
                    app, projectId, toolId, before, expectedInputSha,
                    result, audit, completion)));
    }

    private static void finish(Context app, String projectId, String toolId,
            Selection before, String expectedInputSha,
            LaboratorySandboxClient.Result result,
            LaboratoryStableUseStore audit, Completion completion) {
        IOException failure = null;
        boolean selectionVerified = false;

        try {
            Selection after = resolveSelection(app, projectId, toolId);
            selectionVerified =
                before.lifecycleEvent.eventId.equals(after.lifecycleEvent.eventId)
                && before.lifecycleEvent.sequence == after.lifecycleEvent.sequence
                && before.descriptor.version.equals(after.descriptor.version)
                && before.binding.snapshotId.equals(after.binding.snapshotId)
                && before.binding.artifactSha256.equals(after.binding.artifactSha256)
                && before.binding.artifactSha256.equals(result.sourceSha256)
                && expectedInputSha.equals(result.inputSha256);
            if (!selectionVerified) {
                failure = new IOException(
                    "STABLE selection or execution hashes changed during tool execution");
            }
        } catch (IOException changed) {
            failure = new IOException(
                "STABLE selection could not be revalidated after execution", changed);
        }

        LaboratoryStableUseStore.Use saved = null;
        try {
            saved = audit.save(
                before.descriptor.toolId,
                before.descriptor.version,
                before.lifecycleEvent.eventId,
                before.lifecycleEvent.sequence,
                before.binding.snapshotId,
                before.binding.artifactSha256,
                expectedInputSha,
                result,
                selectionVerified);
        } catch (IOException auditError) {
            if (failure != null) auditError.addSuppressed(failure);
            failure = auditError;
        }

        if (failure == null && !"EXECUTED".equals(result.status)) {
            failure = new IOException("stable tool worker status: " + result.status);
        }
        if (failure == null && (saved == null || !saved.usable)) {
            failure = new IOException("stable tool result is not auditable or usable");
        }

        final IOException deliveredFailure = failure;
        final LaboratoryStableUseStore.Use deliveredAudit = saved;
        MAIN.post(() -> {
            if (deliveredFailure != null) {
                completion.onFinished(null, deliveredFailure);
            } else {
                completion.onFinished(
                    new Execution(before, result, deliveredAudit), null);
            }
        });
    }

    private static Selection resolveSelection(
            Context app, String projectId, String toolId) throws IOException {
        if (toolId == null || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")) {
            throw new IllegalArgumentException("invalid stable tool id");
        }
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId);
        LaboratoryToolRegistry.Descriptor active = registry.activeStable(toolId);
        if (active == null) throw new IOException("no active STABLE tool version");

        LaboratoryToolRegistry.Event event = null;
        List<LaboratoryToolRegistry.Event> history = registry.history(toolId);
        for (LaboratoryToolRegistry.Event candidate : history) {
            if ("ACTIVATE_STABLE".equals(candidate.action)
                    || "ROLLBACK_STABLE".equals(candidate.action)) {
                event = candidate;
            }
        }
        if (event == null || !active.version.equals(event.toVersion)
                || event.approvalSha256 == null
                || !event.approvalSha256.matches("[0-9a-f]{64}")) {
            throw new IOException("active STABLE lifecycle evidence is incomplete");
        }

        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(app.getFilesDir(), projectId);
        LaboratoryToolArtifactStore.Binding binding =
            artifacts.readActiveStableVerified(toolId);
        if (!active.version.equals(binding.version)
                || !active.artifactSha256.equals(binding.artifactSha256)) {
            throw new IOException("active STABLE artifact binding does not match registry");
        }
        return new Selection(active, event, binding);
    }
}
