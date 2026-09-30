package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Internal-only candidate test entry point. Must be called from an IO thread.
 * The isolated service executes code; only the main app writes the evidence.
 * A successful runtime return is not reported as a passing test until the
 * expected return matches, the approved-input snapshot verifies, AND the
 * structured report is persisted.
 */
public final class LaboratoryCandidateRunner {
    public interface Completion {
        void onFinished(LaboratorySandboxClient.Result execution,
            boolean testPassed, IOException recordingError);
    }

    private static final ExecutorService REPORT_IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private LaboratoryCandidateRunner() {}

    public static LaboratorySandboxClient.Session runInternal(Context context, String projectId,
            String candidate, String expectedFirstReturn, long seed, int timeoutMs,
            Completion completion) throws IOException {
        return runInternal(context, projectId, candidate, "", expectedFirstReturn,
            seed, timeoutMs, completion);
    }

    public static LaboratorySandboxClient.Session runInternal(Context context, String projectId,
            String candidate, String toolInput, String expectedFirstReturn,
            long seed, int timeoutMs, Completion completion) throws IOException {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(completion, "completion");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("laboratory preflight must run off the UI thread");
        }
        if (expectedFirstReturn == null || expectedFirstReturn.length() > 256) {
            throw new IllegalArgumentException("invalid expected Luau return");
        }
        if (candidate == null || candidate.isEmpty() || toolInput == null
                || candidate.length() > LaboratorySandboxService.MAX_SOURCE_CHARS
                || toolInput.length() > LaboratorySandboxService.MAX_INPUT_CHARS
                || timeoutMs < 1 || timeoutMs > LaboratorySandboxService.MAX_TIMEOUT_MS) {
            throw new IllegalArgumentException(
                "invalid laboratory candidate, tool input or timeout");
        }
        LaboratoryReportStore reports =
            new LaboratoryReportStore(context.getFilesDir(), projectId);
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(context.getFilesDir(), projectId);
        reports.ensureWritable();
        // Only the explicit candidate passed by this internal caller is copied.
        // Never scan or snapshot the user's editor/scripts/project directories.
        LaboratorySnapshotStore.Snapshot baseline = snapshots.create(
            "candidate-luau", candidate.getBytes(StandardCharsets.UTF_8));
        return LaboratorySandboxClient.execute(
            context, candidate, toolInput, timeoutMs, result ->
            REPORT_IO.execute(() -> {
                IOException recordingError = null;
                boolean snapshotVerified = false;
                try {
                    LaboratorySnapshotStore.Snapshot recovered =
                        snapshots.readCopy(baseline.id);
                    snapshotVerified = recovered.sha256.equals(result.sourceSha256);
                    if (!snapshotVerified) {
                        recordingError = new IOException(
                            "candidate snapshot does not match executed source");
                    }
                } catch (IOException error) {
                    recordingError = error;
                }
                try {
                    reports.saveSandboxResult(result, "expected-return",
                        expectedFirstReturn, seed, baseline.id, snapshotVerified);
                } catch (IOException error) {
                    if (recordingError != null) error.addSuppressed(recordingError);
                    recordingError = error;
                }
                final IOException failure = recordingError;
                boolean passed = failure == null && snapshotVerified
                    && "EXECUTED".equals(result.status)
                    && expectedFirstReturn.equals(result.firstReturn);
                MAIN.post(() -> completion.onFinished(result, passed, failure));
            }));
    }
}
