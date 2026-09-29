package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Internal-only candidate test entry point. Must be called from an IO thread.
 * The isolated service executes code; only the main app writes the evidence.
 * A successful runtime return is not reported as a passing test until the
 * expected return matches AND the structured report is persisted.
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
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(completion, "completion");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("laboratory preflight must run off the UI thread");
        }
        if (expectedFirstReturn == null || expectedFirstReturn.length() > 256) {
            throw new IllegalArgumentException("invalid expected Luau return");
        }
        LaboratoryReportStore reports =
            new LaboratoryReportStore(context.getFilesDir(), projectId);
        reports.ensureWritable();
        return LaboratorySandboxClient.execute(context, candidate, timeoutMs, result ->
            REPORT_IO.execute(() -> {
                IOException recordingError = null;
                try {
                    reports.saveSandboxResult(result, "expected-return", expectedFirstReturn, seed);
                } catch (IOException error) {
                    recordingError = error;
                }
                final IOException failure = recordingError;
                boolean passed = failure == null && "EXECUTED".equals(result.status)
                    && expectedFirstReturn.equals(result.firstReturn);
                MAIN.post(() -> completion.onFinished(result, passed, failure));
            }));
    }
}
