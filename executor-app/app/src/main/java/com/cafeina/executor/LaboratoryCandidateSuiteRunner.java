package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Deterministic sequential suite for one isolated candidate artifact.
 *
 * All cases reuse one immutable verified candidate snapshot. Every case still
 * produces its own create-only LaboratoryReportStore record through
 * LaboratoryCandidateRunner. No model judges pass/fail.
 */
public final class LaboratoryCandidateSuiteRunner {
    public static final int MAX_CASES = 16;
    public static final int MAX_TOTAL_INPUT_BYTES = 256 * 1024;

    public interface Completion {
        void onFinished(Result result, IOException failure);
    }

    public static final class TestCase {
        public final String name;
        public final String toolInput;
        public final String expectedFirstReturn;
        public final int timeoutMs;

        public TestCase(
                String name,
                String toolInput,
                String expectedFirstReturn,
                int timeoutMs) {
            if (name == null
                    || !name.matches("[a-zA-Z0-9_-]{1,64}")) {
                throw new IllegalArgumentException(
                    "invalid candidate suite case name");
            }
            if (toolInput == null
                    || toolInput.length()
                        > LaboratorySandboxService.MAX_INPUT_CHARS) {
                throw new IllegalArgumentException(
                    "invalid candidate suite input");
            }
            if (expectedFirstReturn == null
                    || expectedFirstReturn.length() > 256) {
                throw new IllegalArgumentException(
                    "invalid candidate suite expected return");
            }
            if (timeoutMs < 1
                    || timeoutMs
                        > LaboratorySandboxService.MAX_TIMEOUT_MS) {
                throw new IllegalArgumentException(
                    "invalid candidate suite timeout");
            }
            this.name = name;
            this.toolInput = toolInput;
            this.expectedFirstReturn = expectedFirstReturn;
            this.timeoutMs = timeoutMs;
        }
    }

    public static final class CaseResult {
        public final String name;
        public final String runId;
        public final String workerStatus;
        public final boolean passed;
        public final long durationMs;

        private CaseResult(
                TestCase testCase,
                LaboratorySandboxClient.Result execution,
                boolean passed) {
            this.name = testCase.name;
            this.runId = execution == null ? "" : execution.runId;
            this.workerStatus =
                execution == null ? "NO_RESULT" : execution.status;
            this.passed = passed;
            this.durationMs =
                execution == null ? 0L : execution.durationMs;
        }
    }

    public static final class Result {
        public final String status;
        public final long seed;
        public final boolean stopOnFailure;
        public final String candidateSha256;
        public final String snapshotId;
        public final int plannedCases;
        public final int executedCases;
        public final int passed;
        public final int failed;
        public final List<CaseResult> cases;

        private Result(
                String status,
                long seed,
                boolean stopOnFailure,
                String candidateSha256,
                String snapshotId,
                int plannedCases,
                List<CaseResult> cases,
                int passed,
                int failed) {
            this.status = status;
            this.seed = seed;
            this.stopOnFailure = stopOnFailure;
            this.candidateSha256 = candidateSha256;
            this.snapshotId = snapshotId;
            this.plannedCases = plannedCases;
            this.executedCases = cases.size();
            this.passed = passed;
            this.failed = failed;
            this.cases = Collections.unmodifiableList(
                new ArrayList<>(cases));
        }
    }

    public static final class Control {
        private final AtomicBoolean cancelRequested =
            new AtomicBoolean(false);
        private final AtomicReference<LaboratorySandboxClient.Session> active =
            new AtomicReference<>();

        public void cancel() {
            cancelRequested.set(true);
            LaboratorySandboxClient.Session session = active.get();
            if (session != null) {
                session.cancel();
            }
        }

        public boolean isCancellationRequested() {
            return cancelRequested.get();
        }

        private void attach(
                LaboratorySandboxClient.Session session) {
            active.set(session);
            if (cancelRequested.get() && session != null) {
                session.cancel();
            }
        }

        private void detach(
                LaboratorySandboxClient.Session session) {
            active.compareAndSet(session, null);
        }
    }

    private static final ExecutorService SUITE_IO =
        Executors.newSingleThreadExecutor();
    private static final Handler MAIN =
        new Handler(Looper.getMainLooper());

    private LaboratoryCandidateSuiteRunner() {}

    public static Control runInternal(
            Context context,
            String projectId,
            String candidate,
            List<TestCase> cases,
            long seed,
            boolean stopOnFailure,
            Completion completion) throws IOException {
        if (context == null || completion == null) {
            throw new IllegalArgumentException(
                "candidate suite context or completion missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "candidate suite must start off the UI thread");
        }
        validateSuite(candidate, cases);

        Context app = context.getApplicationContext();
        String safeProjectId = projectId == null ? "" : projectId;

        LaboratoryReportStore reports =
            new LaboratoryReportStore(
                app.getFilesDir(), safeProjectId);
        int existingReports = reports.list().size();
        if (existingReports + cases.size()
                > LaboratoryReportStore.MAX_REPORTS) {
            throw new IOException(
                "candidate suite would exceed laboratory report capacity");
        }
        reports.ensureWritable();

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(
                app.getFilesDir(), safeProjectId);
        LaboratorySnapshotStore.Snapshot baseline =
            snapshots.create(
                "candidate-suite-luau",
                candidate.getBytes(StandardCharsets.UTF_8));

        Control control = new Control();
        State state = new State(
            app,
            safeProjectId,
            candidate,
            new ArrayList<>(cases),
            seed,
            stopOnFailure,
            baseline,
            control,
            completion);

        SUITE_IO.execute(() -> runNext(state));
        return control;
    }

    private static void runNext(State state) {
        if (state.finished.get()) return;

        if (state.control.isCancellationRequested()) {
            finish(state, "CANCELLED", null);
            return;
        }
        if (state.index >= state.cases.size()) {
            finish(
                state,
                state.failed > 0 ? "FAIL" : "PASS",
                null);
            return;
        }

        final TestCase testCase =
            state.cases.get(state.index);

        try {
            LaboratorySandboxClient.Session session =
                LaboratoryCandidateRunner.runPreparedInternal(
                    state.app,
                    state.projectId,
                    state.candidate,
                    testCase.toolInput,
                    testCase.name,
                    testCase.expectedFirstReturn,
                    state.seed,
                    testCase.timeoutMs,
                    state.baseline,
                    (execution, passed, recordingError) ->
                        SUITE_IO.execute(() ->
                            handleCaseFinished(
                                state,
                                testCase,
                                execution,
                                passed,
                                recordingError)));
            state.control.attach(session);
        } catch (IOException | RuntimeException failure) {
            finish(
                state,
                "ERROR",
                asIOException(
                    "candidate suite could not start case "
                        + testCase.name,
                    failure));
        }
    }

    private static void handleCaseFinished(
            State state,
            TestCase testCase,
            LaboratorySandboxClient.Result execution,
            boolean passed,
            IOException recordingError) {
        LaboratorySandboxClient.Session active =
            state.control.active.get();
        if (active != null) {
            state.control.detach(active);
        }

        if (state.finished.get()) return;

        state.results.add(
            new CaseResult(testCase, execution, passed));
        state.index++;
        if (passed) {
            state.passed++;
        } else {
            state.failed++;
        }

        if (recordingError != null) {
            finish(
                state,
                "ERROR",
                new IOException(
                    "candidate suite evidence persistence failed for case "
                        + testCase.name,
                    recordingError));
            return;
        }

        if (state.control.isCancellationRequested()
                || (execution != null
                    && "CANCELLED".equals(execution.status))) {
            finish(state, "CANCELLED", null);
            return;
        }

        if (!passed && state.stopOnFailure) {
            finish(state, "FAIL", null);
            return;
        }

        runNext(state);
    }

    private static void finish(
            State state,
            String status,
            IOException failure) {
        if (!state.finished.compareAndSet(false, true)) {
            return;
        }

        Result result = new Result(
            status,
            state.seed,
            state.stopOnFailure,
            state.baseline.sha256,
            state.baseline.id,
            state.cases.size(),
            state.results,
            state.passed,
            state.failed);

        MAIN.post(() ->
            state.completion.onFinished(result, failure));
    }

    private static void validateSuite(
            String candidate,
            List<TestCase> cases) {
        if (candidate == null
                || candidate.isEmpty()
                || candidate.length()
                    > LaboratorySandboxService.MAX_SOURCE_CHARS) {
            throw new IllegalArgumentException(
                "invalid candidate suite source");
        }
        if (cases == null
                || cases.isEmpty()
                || cases.size() > MAX_CASES) {
            throw new IllegalArgumentException(
                "invalid candidate suite case count");
        }

        Set<String> names = new HashSet<>();
        long totalInputBytes = 0L;
        for (TestCase testCase : cases) {
            if (testCase == null || !names.add(testCase.name)) {
                throw new IllegalArgumentException(
                    "candidate suite case names must be unique");
            }
            totalInputBytes +=
                testCase.toolInput
                    .getBytes(StandardCharsets.UTF_8)
                    .length;
            if (totalInputBytes > MAX_TOTAL_INPUT_BYTES) {
                throw new IllegalArgumentException(
                    "candidate suite input budget exceeded");
            }
        }
    }

    private static IOException asIOException(
            String message,
            Throwable failure) {
        if (failure instanceof IOException) {
            return new IOException(message, failure);
        }
        return new IOException(message, failure);
    }

    private static final class State {
        final Context app;
        final String projectId;
        final String candidate;
        final List<TestCase> cases;
        final long seed;
        final boolean stopOnFailure;
        final LaboratorySnapshotStore.Snapshot baseline;
        final Control control;
        final Completion completion;
        final AtomicBoolean finished = new AtomicBoolean(false);
        final List<CaseResult> results = new ArrayList<>();

        int index;
        int passed;
        int failed;

        State(
                Context app,
                String projectId,
                String candidate,
                List<TestCase> cases,
                long seed,
                boolean stopOnFailure,
                LaboratorySnapshotStore.Snapshot baseline,
                Control control,
                Completion completion) {
            this.app = app;
            this.projectId = projectId;
            this.candidate = candidate;
            this.cases = cases;
            this.seed = seed;
            this.stopOnFailure = stopOnFailure;
            this.baseline = baseline;
            this.control = control;
            this.completion = completion;
        }
    }
}
