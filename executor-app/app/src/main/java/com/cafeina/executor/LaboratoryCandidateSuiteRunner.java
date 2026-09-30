package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Bounded multi-case test runner for ONE registered Luau tool version.
 *
 * The same snapshotted source is executed in the Android isolated worker for
 * each case; only tool_input changes. No source is executed in the app process.
 * Cases keep input/output text out of persistent reports; hashes are persisted.
 */
public final class LaboratoryCandidateSuiteRunner {
    public static final int MAX_CASES = LaboratoryCandidateSuiteStore.MAX_CASES;
    public static final int MAX_COMBINED_NATIVE_BUDGET_MS = 12_000;
    private static final int HOST_GRACE_MS = 12_000;

    public static final class Case {
        public final String name;
        public final String input;
        public final String expectedFirstReturn;

        public Case(String name, String input, String expectedFirstReturn) {
            if (name == null || !name.matches("[a-zA-Z0-9_-]{1,64}")
                    || input == null
                    || input.length() > LaboratorySandboxService.MAX_INPUT_CHARS
                    || expectedFirstReturn == null
                    || expectedFirstReturn.length() > 256) {
                throw new IllegalArgumentException("invalid candidate-suite case");
            }
            this.name = name;
            this.input = input;
            this.expectedFirstReturn = expectedFirstReturn;
        }
    }

    public static final class Plan {
        public final String toolId;
        public final String toolVersion;
        public final long seed;
        public final List<Case> cases;
        public final String planSha256;

        public Plan(String toolId, String toolVersion, long seed, List<Case> cases) {
            if (toolId == null || !toolId.matches("[a-z][a-z0-9-]{2,47}")
                    || toolVersion == null
                    || !toolVersion.matches(
                        "(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})")
                    || cases == null || cases.isEmpty() || cases.size() > MAX_CASES) {
                throw new IllegalArgumentException("invalid candidate-suite plan");
            }
            for (Case item : cases) Objects.requireNonNull(item, "candidate-suite case");
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.seed = seed;
            this.cases = Collections.unmodifiableList(new ArrayList<>(cases));
            this.planSha256 = digestPlan(this);
        }
    }

    private LaboratoryCandidateSuiteRunner() {}

    /**
     * Synchronous orchestration for an internal background worker. Android IPC
     * remains asynchronous; this method waits off the UI thread so cases run
     * sequentially and a fresh native VM is used for each request.
     */
    public static LaboratoryCandidateSuiteStore.Summary runInternal(
            Context context, String projectId, Plan plan,
            LaboratoryEngine.Cancellation cancellation) throws IOException {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(plan, "plan");
        Objects.requireNonNull(cancellation, "cancellation");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("candidate suite must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId);
        LaboratoryToolRegistry.Tool tool = registry.read(plan.toolId, plan.toolVersion);
        if (!(tool.state == LaboratoryToolRegistry.State.EXPERIMENTAL
                || tool.state == LaboratoryToolRegistry.State.CANDIDATE)
                || !"LUAU_ISOLATED_NO_FILES".equals(tool.capability)) {
            throw new IOException("tool is not eligible for isolated candidate suite");
        }
        if ((long) tool.timeoutMs * plan.cases.size() > MAX_COMBINED_NATIVE_BUDGET_MS) {
            throw new IllegalArgumentException("candidate suite exceeds native time budget");
        }

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), projectId);
        LaboratorySnapshotStore.Snapshot baseline = snapshots.readCopy(tool.snapshotId);
        if (!"candidate-luau".equals(baseline.label)
                || !baseline.sha256.equals(tool.sourceSha256)) {
            throw new IOException("registered tool snapshot failed integrity check");
        }
        byte[] sourceBytes = baseline.contentCopy();
        String source = new String(sourceBytes, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(sourceBytes, source.getBytes(StandardCharsets.UTF_8))
                || source.isEmpty()
                || source.length() > LaboratorySandboxService.MAX_SOURCE_CHARS) {
            throw new IOException("registered tool source is not valid bounded UTF-8 text");
        }

        LaboratoryReportStore reports =
            new LaboratoryReportStore(app.getFilesDir(), projectId);
        if (reports.list().size() + plan.cases.size() > LaboratoryReportStore.MAX_REPORTS) {
            throw new IOException("not enough report capacity for candidate suite");
        }
        LaboratoryCandidateSuiteStore suites =
            new LaboratoryCandidateSuiteStore(app.getFilesDir(), projectId);
        suites.ensureWritable();
        reports.ensureWritable();

        LaboratoryCandidateSuiteStore.Summary start =
            suites.begin(tool, plan.planSha256, plan.cases.size());
        List<String> reportIds = new ArrayList<>();
        int passed = 0;
        int failed = 0;
        LaboratoryCandidateSuiteStore.Status finalStatus =
            LaboratoryCandidateSuiteStore.Status.PASS;
        String reason = "ALL_CASES_MATCHED";
        IOException executionFailure = null;

        try {
            for (Case testCase : plan.cases) {
                if (cancellation.isCancelled()) {
                    finalStatus = LaboratoryCandidateSuiteStore.Status.CANCELLED;
                    reason = "USER_CANCELLED";
                    break;
                }

                LaboratorySnapshotStore.Snapshot current =
                    snapshots.readCopy(tool.snapshotId);
                if (!tool.sourceSha256.equals(current.sha256)) {
                    throw new IOException("candidate source changed during suite");
                }

                LaboratorySandboxClient.Result result =
                    executeCase(app, source, testCase.input, tool.timeoutMs, cancellation);
                if (!tool.sourceSha256.equals(result.sourceSha256)
                        || !hashText(testCase.input).equals(result.inputSha256)) {
                    throw new IOException("isolated worker evidence does not match suite case");
                }

                reports.saveSandboxResult(result, testCase.name,
                    testCase.expectedFirstReturn, plan.seed,
                    tool.snapshotId, true);
                reportIds.add(result.runId);

                boolean matched = "EXECUTED".equals(result.status)
                    && testCase.expectedFirstReturn.equals(result.firstReturn);
                if (matched) {
                    passed++;
                    continue;
                }
                if ("CANCELLED".equals(result.status)) {
                    finalStatus = LaboratoryCandidateSuiteStore.Status.CANCELLED;
                    reason = "USER_CANCELLED";
                    break;
                }
                if ("TIMEOUT".equals(result.status)) {
                    finalStatus = LaboratoryCandidateSuiteStore.Status.TIMEOUT;
                    reason = "CASE_TIME_BUDGET";
                    break;
                }
                failed++;
                finalStatus = LaboratoryCandidateSuiteStore.Status.FAIL;
                reason = "CASE_MISMATCH";
            }
        } catch (IOException failure) {
            executionFailure = failure;
            finalStatus = LaboratoryCandidateSuiteStore.Status.INCOMPLETE;
            reason = "EVIDENCE_STORAGE_FAILURE";
        } catch (RuntimeException failure) {
            executionFailure = new IOException(
                "candidate suite failed unexpectedly", failure);
            finalStatus = LaboratoryCandidateSuiteStore.Status.INCOMPLETE;
            reason = "INTERNAL_RUNNER_FAILURE";
        }

        try {
            LaboratoryCandidateSuiteStore.Summary end = suites.complete(
                start.suiteId, finalStatus, reportIds, passed, failed, reason);
            if (executionFailure != null) throw executionFailure;
            return end;
        } catch (IOException completion) {
            if (executionFailure != null && completion != executionFailure) {
                executionFailure.addSuppressed(completion);
                throw executionFailure;
            }
            throw completion;
        }
    }

    private static LaboratorySandboxClient.Result executeCase(
            Context app, String source, String input, int timeoutMs,
            LaboratoryEngine.Cancellation cancellation) throws IOException {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratorySandboxClient.Result> outcome = new AtomicReference<>();
        LaboratorySandboxClient.Session session = LaboratorySandboxClient.execute(
            app, source, input, timeoutMs, result -> {
                outcome.set(result);
                done.countDown();
            });

        long deadline = System.nanoTime()
            + TimeUnit.MILLISECONDS.toNanos(timeoutMs + HOST_GRACE_MS);
        boolean cancelledSent = false;
        try {
            while (!done.await(50, TimeUnit.MILLISECONDS)) {
                if (cancellation.isCancelled() && !cancelledSent) {
                    session.cancel();
                    cancelledSent = true;
                }
                if (System.nanoTime() >= deadline) {
                    session.cancel();
                    if (!done.await(2, TimeUnit.SECONDS)) {
                        throw new IOException("isolated candidate case exceeded host watchdog");
                    }
                    break;
                }
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            session.cancel();
            throw new IOException("candidate-suite worker interrupted", interrupted);
        }
        LaboratorySandboxClient.Result result = outcome.get();
        if (result == null) throw new IOException("isolated worker returned no result");
        return result;
    }

    private static String digestPlan(Plan plan) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            add(digest, "CANDIDATE_BATCH");
            add(digest, plan.toolId);
            add(digest, plan.toolVersion);
            add(digest, Long.toString(plan.seed));
            for (Case item : plan.cases) {
                add(digest, item.name);
                add(digest, item.input);
                add(digest, item.expectedFirstReturn);
            }
            return hex(digest.digest());
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static String hashText(String value) {
        try {
            return hex(MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static void add(MessageDigest digest, String value) {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        digest.update((byte) (bytes.length >>> 24));
        digest.update((byte) (bytes.length >>> 16));
        digest.update((byte) (bytes.length >>> 8));
        digest.update((byte) bytes.length);
        digest.update(bytes);
    }

    private static String hex(byte[] digest) {
        StringBuilder out = new StringBuilder(64);
        for (byte b : digest) {
            out.append(String.format(Locale.ROOT, "%02x", b & 255));
        }
        return out.toString();
    }
}
