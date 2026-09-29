package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Internal orchestration for an EXPERIMENTAL Luau tool version.
 *
 * A failed test keeps the version EXPERIMENTAL, a passing test creates only a
 * CANDIDATE review request. This class cannot approve or activate STABLE, add
 * capabilities, write project scripts, or invoke the user's Godot World.
 */
public final class LaboratoryToolWorkshop {
    public interface Completion {
        /** Called on the UI thread, strictly after the report/registry writes. */
        void onFinished(LaboratorySandboxClient.Result execution,
            LaboratoryToolRegistry.Tool version, boolean awaitingHumanReview,
            IOException failure);
    }

    private static final ExecutorService RECORD_IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private LaboratoryToolWorkshop() {}

    /**
     * Must be called from an internal background worker. No public UI control
     * invokes this method; a future specialist can use it only after the
     * planner's permission layer is implemented.
     */
    public static LaboratorySandboxClient.Session testNewVersion(
            Context context, String projectId, String toolId, String toolVersion,
            String source, String expectedReturn, long seed, int timeoutMs,
            Completion completion) throws IOException {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(completion, "completion");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("tool workshop must start off the UI thread");
        }
        Context app = context.getApplicationContext();
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId);
        registry.assertVersionAvailable(toolId, toolVersion);
        LaboratoryReportStore reports =
            new LaboratoryReportStore(app.getFilesDir(), projectId);

        return LaboratoryCandidateRunner.runInternal(app, projectId,
            source, expectedReturn, seed, timeoutMs,
            (execution, passed, recordingError) ->
                RECORD_IO.execute(() -> {
                    IOException failure = recordingError;
                    LaboratoryToolRegistry.Tool version = null;
                    try {
                        if (failure == null && !"CANCELLED".equals(execution.status)) {
                            JSONObject report = new JSONObject(
                                reports.read(execution.runId));
                            String snapshotId =
                                report.getString("candidateSnapshotId");
                            if (!execution.runId.equals(report.getString("runId"))
                                    || !execution.sourceSha256.equals(
                                        report.getString("candidateBatchSha256"))
                                    || !report.getBoolean("snapshotVerified")) {
                                throw new IOException(
                                    "candidate report failed source/snapshot verification");
                            }
                            version = registry.registerExperimental(
                                toolId, toolVersion, snapshotId, timeoutMs);
                            if (passed) {
                                version = registry.requestCandidateReview(
                                    toolId, toolVersion, execution.runId);
                            }
                        }
                    } catch (JSONException malformed) {
                        failure = new IOException(
                            "candidate report is missing verified evidence", malformed);
                    } catch (IOException error) {
                        failure = error;
                    }
                    final LaboratoryToolRegistry.Tool result = version;
                    final IOException finalError = failure;
                    final boolean awaitingReview = finalError == null
                        && result != null
                        && result.state == LaboratoryToolRegistry.State.CANDIDATE;
                    MAIN.post(() -> completion.onFinished(execution,
                        result, awaitingReview, finalError));
                }));
    }
}
