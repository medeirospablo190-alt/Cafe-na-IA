package com.cafeina.executor;

import android.os.Looper;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;

/**
 * AI-independent, bounded test orchestration for allowlisted host probes.
 * Batch runs expected-output cases; Replay repeats the same inputs/seed and
 * compares actual outputs; Regression compares against immutable same-project
 * PASS reports with the same source batch and environment fingerprint.
 *
 * Never executes generated Luau, reads real project scripts, accesses the
 * Godot World or promotes tool versions. Candidate Luau tests remain in their
 * own isolated process and are not eligible for this host-side runner.
 */
public final class LaboratorySuiteRunner {
    public static final int MAX_REQUESTS = 4;
    public static final int MAX_COMBINED_TEST_BUDGET_MS = 24_000;

    public enum Mode { BATCH, REPLAY, REGRESSION }

    public static final class Plan {
        public final Mode mode;
        public final List<LaboratoryEngine.Request> requests;
        public final List<String> baselineReportIds;
        public final int plannedRuns;
        public final String planSha256;

        public Plan(Mode mode, List<LaboratoryEngine.Request> requests,
                List<String> baselineReportIds) {
            this.mode = Objects.requireNonNull(mode, "suite mode");
            if (requests == null || requests.isEmpty() || requests.size() > MAX_REQUESTS
                    || baselineReportIds == null || baselineReportIds.size() > MAX_REQUESTS
                    || (mode == Mode.REGRESSION
                        ? baselineReportIds.size() != requests.size()
                        : !baselineReportIds.isEmpty())) {
                throw new IllegalArgumentException("invalid laboratory suite");
            }
            int combinedBudget = 0;
            for (LaboratoryEngine.Request request : requests) {
                Objects.requireNonNull(request, "suite request");
                combinedBudget += request.timeoutMs * (mode == Mode.REPLAY ? 2 : 1);
                if (combinedBudget > MAX_COMBINED_TEST_BUDGET_MS) {
                    throw new IllegalArgumentException("suite exceeds execution budget");
                }
            }
            for (String id : baselineReportIds) {
                if (!LaboratorySnapshotStore.validId(id)) {
                    throw new IllegalArgumentException("invalid regression baseline");
                }
            }
            this.requests = Collections.unmodifiableList(new ArrayList<>(requests));
            this.baselineReportIds =
                Collections.unmodifiableList(new ArrayList<>(baselineReportIds));
            this.plannedRuns = requests.size() * (mode == Mode.REPLAY ? 2 : 1);
            this.planSha256 = digestPlan(this);
        }
    }

    private LaboratorySuiteRunner() {}

    /**
     * Must run off the UI thread. The suite START is durable before any probe
     * executes. On a storage failure, attempt to persist INCOMPLETE and
     * propagate the failure. An abandoned START remains visible after crashes.
     */
    public static LaboratorySuiteStore.Summary runInternal(File appFilesDir,
            String projectId, Plan plan, LaboratoryEngine.Cancellation cancellation)
            throws IOException {
        Objects.requireNonNull(plan, "suite plan");
        Objects.requireNonNull(cancellation, "cancellation");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("suite must run off the Android UI thread");
        }
        LaboratoryReportStore reportStore =
            new LaboratoryReportStore(appFilesDir, projectId);
        LaboratorySuiteStore suiteStore =
            new LaboratorySuiteStore(appFilesDir, projectId);
        suiteStore.ensureWritable();
        reportStore.ensureWritable();

        List<JSONObject> baselines = new ArrayList<>();
        if (plan.mode == Mode.REGRESSION) {
            for (int i = 0; i < plan.requests.size(); i++) {
                JSONObject baseline;
                try {
                    baseline = new JSONObject(
                        reportStore.read(plan.baselineReportIds.get(i)));
                    verifyBaselineRequest(baseline, plan.baselineReportIds.get(i),
                        plan.requests.get(i));
                } catch (JSONException invalid) {
                    throw new IOException("regression baseline is malformed", invalid);
                }
                baselines.add(baseline);
            }
        }

        LaboratorySuiteStore.Summary start = suiteStore.begin(plan.mode.name(),
            plan.planSha256, plan.requests.size(), plan.baselineReportIds);
        List<String> reportIds = new ArrayList<>();
        int passed = 0;
        int failed = 0;
        LaboratorySuiteStore.Status result = LaboratorySuiteStore.Status.PASS;
        String reason = "ALL_CASES_MATCHED";
        IOException executionError = null;
        long startedNanos = System.nanoTime();

        try {
            for (int i = 0; i < plan.requests.size(); i++) {
                if (cancellation.isCancelled()) {
                    result = LaboratorySuiteStore.Status.CANCELLED;
                    reason = "USER_CANCELLED";
                    break;
                }
                if (elapsedMs(startedNanos) >= MAX_COMBINED_TEST_BUDGET_MS) {
                    result = LaboratorySuiteStore.Status.TIMEOUT;
                    reason = "SUITE_TIME_BUDGET";
                    break;
                }
                LaboratoryEngine.Request request = plan.requests.get(i);
                LaboratoryEngine.Report first = LaboratoryRunner.runApprovedBuiltIn(
                    appFilesDir, projectId, request, cancellation);
                reportIds.add(first.runId);
                if (first.status != LaboratoryEngine.Status.PASS) {
                    failed++;
                    if (first.status == LaboratoryEngine.Status.CANCELLED) {
                        result = LaboratorySuiteStore.Status.CANCELLED;
                        reason = "USER_CANCELLED";
                        break;
                    }
                    if (first.status == LaboratoryEngine.Status.TIMEOUT) {
                        result = LaboratorySuiteStore.Status.TIMEOUT;
                        reason = "PROBE_TIME_BUDGET";
                        break;
                    }
                    result = LaboratorySuiteStore.Status.FAIL;
                    reason = "EXPECTED_OUTPUT_MISMATCH";
                    continue;
                }
                boolean matches = true;
                if (plan.mode == Mode.REPLAY) {
                    if (cancellation.isCancelled()) {
                        result = LaboratorySuiteStore.Status.CANCELLED;
                        reason = "USER_CANCELLED";
                        break;
                    }
                    LaboratoryEngine.Report replay = LaboratoryRunner.runApprovedBuiltIn(
                        appFilesDir, projectId, request, cancellation);
                    reportIds.add(replay.runId);
                    if (replay.status == LaboratoryEngine.Status.CANCELLED) {
                        result = LaboratorySuiteStore.Status.CANCELLED;
                        reason = "USER_CANCELLED";
                        break;
                    }
                    if (replay.status == LaboratoryEngine.Status.TIMEOUT) {
                        result = LaboratorySuiteStore.Status.TIMEOUT;
                        reason = "PROBE_TIME_BUDGET";
                        break;
                    }
                    matches = sameOutputs(first, replay);
                    if (!matches) reason = "REPLAY_OUTPUT_MISMATCH";
                } else if (plan.mode == Mode.REGRESSION) {
                    matches = sameOutputs(first, baselines.get(i));
                    if (!matches) reason = "REGRESSION_DIFFERENCE";
                }
                if (matches) passed++;
                else {
                    failed++;
                    result = LaboratorySuiteStore.Status.FAIL;
                }
            }
            if (result == LaboratorySuiteStore.Status.PASS
                    && elapsedMs(startedNanos) >= MAX_COMBINED_TEST_BUDGET_MS) {
                result = LaboratorySuiteStore.Status.TIMEOUT;
                reason = "SUITE_TIME_BUDGET";
            }
        } catch (IOException storage) {
            executionError = storage;
            result = LaboratorySuiteStore.Status.INCOMPLETE;
            reason = "EVIDENCE_STORAGE_FAILURE";
        } catch (RuntimeException internal) {
            executionError = new IOException("laboratory suite failed unexpectedly", internal);
            result = LaboratorySuiteStore.Status.INCOMPLETE;
            reason = "INTERNAL_RUNNER_FAILURE";
        }

        try {
            LaboratorySuiteStore.Summary end = suiteStore.complete(start.suiteId,
                result, reportIds, passed, failed, reason);
            if (executionError != null) throw executionError;
            return end;
        } catch (IOException completion) {
            if (executionError != null && completion != executionError) {
                executionError.addSuppressed(completion);
                throw executionError;
            }
            throw completion;
        }
    }

    private static void verifyBaselineRequest(JSONObject baseline,
            String id, LaboratoryEngine.Request request)
            throws IOException, JSONException {
        JSONArray checks = baseline.getJSONArray("checks");
        if (baseline.getInt("schemaVersion") != 1
                || !id.equals(baseline.getString("runId"))
                || !request.toolId.equals(baseline.getString("toolId"))
                || !request.toolVersion.equals(baseline.getString("toolVersion"))
                || request.seed != baseline.getLong("seed")
                || !"EXPERIMENTAL".equals(baseline.getString("stage"))
                || !"PASS".equals(baseline.getString("status"))
                || baseline.getInt("passed") != request.cases.size()
                || baseline.getInt("failed") != 0
                || checks.length() != request.cases.size()) {
            throw new IOException("regression baseline must be a matching PASS run");
        }
    }

    private static boolean sameOutputs(LaboratoryEngine.Report left,
            LaboratoryEngine.Report right) {
        if (right.status != LaboratoryEngine.Status.PASS
                || !left.toolId.equals(right.toolId)
                || !left.toolVersion.equals(right.toolVersion)
                || left.seed != right.seed
                || !left.candidateBatchSha256.equals(right.candidateBatchSha256)
                || !left.environmentSha256.equals(right.environmentSha256)
                || left.checks.size() != right.checks.size()) {
            return false;
        }
        for (int i = 0; i < left.checks.size(); i++) {
            LaboratoryEngine.Check a = left.checks.get(i);
            LaboratoryEngine.Check b = right.checks.get(i);
            if (a.passed != b.passed || !a.name.equals(b.name)
                    || !a.actualOutput.equals(b.actualOutput)
                    || !a.inputSha256.equals(b.inputSha256)) {
                return false;
            }
        }
        return true;
    }

    private static boolean sameOutputs(LaboratoryEngine.Report actual,
            JSONObject baseline) throws IOException {
        try {
            JSONArray checks = baseline.getJSONArray("checks");
            if (!"PASS".equals(baseline.getString("status"))
                    || !actual.toolId.equals(baseline.getString("toolId"))
                    || !actual.toolVersion.equals(baseline.getString("toolVersion"))
                    || actual.seed != baseline.getLong("seed")
                    || !actual.candidateBatchSha256.equals(
                        baseline.getString("candidateBatchSha256"))
                    || !actual.environmentSha256.equals(
                        baseline.optString("environmentSha256", ""))
                    || actual.checks.size() != checks.length()) {
                return false;
            }
            for (int i = 0; i < checks.length(); i++) {
                JSONObject old = checks.getJSONObject(i);
                LaboratoryEngine.Check now = actual.checks.get(i);
                if (!now.name.equals(old.getString("name"))
                        || now.passed != old.getBoolean("passed")
                        || !now.actualOutput.equals(old.getString("actualOutput"))
                        || !now.inputSha256.equals(old.getString("inputSha256"))) {
                    return false;
                }
            }
            return true;
        } catch (JSONException invalid) {
            throw new IOException("regression evidence is incomplete", invalid);
        }
    }

    private static long elapsedMs(long startedNanos) {
        return (System.nanoTime() - startedNanos) / 1_000_000L;
    }

    private static String digestPlan(Plan plan) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            add(digest, plan.mode.name());
            for (LaboratoryEngine.Request request : plan.requests) {
                add(digest, request.toolId);
                add(digest, request.toolVersion);
                add(digest, Long.toString(request.seed));
                add(digest, Integer.toString(request.timeoutMs));
                for (LaboratoryEngine.TestCase test : request.cases) {
                    add(digest, test.name);
                    add(digest, test.candidateSource);
                    add(digest, test.expectedOutput);
                }
            }
            for (String baselineId : plan.baselineReportIds) add(digest, baselineId);
            StringBuilder result = new StringBuilder(64);
            for (byte item : digest.digest()) {
                result.append(String.format(Locale.ROOT, "%02x", item & 255));
            }
            return result.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static void add(MessageDigest digest, String input) {
        byte[] bytes = input.getBytes(StandardCharsets.UTF_8);
        digest.update((byte) (bytes.length >>> 24));
        digest.update((byte) (bytes.length >>> 16));
        digest.update((byte) (bytes.length >>> 8));
        digest.update((byte) bytes.length);
        digest.update(bytes);
    }
}
