package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
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
 * Internal deterministic suite runner for one EXPERIMENTAL tool artifact.
 *
 * The caller supplies test vectors only. Executable source is resolved from the
 * immutable verified artifact binding. Each case runs through the isolated
 * candidate worker and persists its own evidence report before the suite can
 * count it as passed.
 *
 * Passing a suite does NOT promote the tool. It only produces evidence run IDs
 * that a separate lifecycle transition may later consume.
 */
public final class LaboratoryCandidateTestSuiteRunner {
    public static final int MAX_CASES = 16;

    public enum Status {
        PASS,
        FAIL,
        CANCELLED,
        EVIDENCE_ERROR
    }

    public interface Observer {
        default void onSuiteReady(
                String toolId,
                String version,
                int totalCases) {
        }

        default void onCaseStarted(
                int index,
                int total,
                TestCase testCase) {
        }

        default void onCaseFinished(
                int index,
                int total,
                CaseResult result) {
        }

        default void onFinished(Result result) {
        }
    }

    public interface Completion {
        void onFinished(Result result, IOException failure);
    }

    public static final class TestCase {
        public final String name;
        public final String toolInput;
        public final String expectedFirstReturn;
        public final long seed;
        public final int timeoutMs;

        public TestCase(
                String name,
                String toolInput,
                String expectedFirstReturn,
                long seed,
                int timeoutMs) {
            if (name == null
                    || !name.matches("[a-zA-Z0-9_-]{1,64}")) {
                throw new IllegalArgumentException(
                    "invalid candidate suite test name");
            }
            if (toolInput == null
                    || toolInput.length()
                        > LaboratorySandboxService.MAX_INPUT_CHARS) {
                throw new IllegalArgumentException(
                    "candidate suite input exceeds limit");
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
            this.seed = seed;
            this.timeoutMs = timeoutMs;
        }
    }

    public static final class CaseResult {
        public final String name;
        public final String runId;
        public final boolean passed;
        public final String workerStatus;
        public final long durationMs;

        private CaseResult(
                TestCase testCase,
                LaboratorySandboxClient.Result execution,
                boolean passed) {
            this.name = testCase.name;
            this.runId = execution.runId;
            this.passed = passed;
            this.workerStatus = execution.status;
            this.durationMs = execution.durationMs;
        }
    }

    public static final class Result {
        public final String toolId;
        public final String version;
        public final String artifactSha256;
        public final String snapshotId;
        public final Status status;
        public final int totalCases;
        public final int passed;
        public final int failed;
        public final List<CaseResult> cases;
        public final List<String> runIds;

        private Result(
                String toolId,
                String version,
                String artifactSha256,
                String snapshotId,
                Status status,
                List<CaseResult> cases) {
            this.toolId = toolId;
            this.version = version;
            this.artifactSha256 = artifactSha256;
            this.snapshotId = snapshotId;
            this.status = status;
            this.cases = Collections.unmodifiableList(
                new ArrayList<>(cases));

            int passedCount = 0;
            List<String> ids = new ArrayList<>();
            for (CaseResult result : cases) {
                if (result.passed) passedCount++;
                ids.add(result.runId);
            }
            this.totalCases = cases.size();
            this.passed = passedCount;
            this.failed = cases.size() - passedCount;
            this.runIds = Collections.unmodifiableList(ids);
        }

        public boolean qualifiesRequiredEvidence() {
            return status == Status.PASS
                && totalCases > 0
                && passed == totalCases;
        }
    }

    public static final class Control {
        private final AtomicBoolean cancelled =
            new AtomicBoolean(false);
        private final AtomicReference<LaboratorySandboxClient.Session>
            active = new AtomicReference<>();

        public void cancel() {
            cancelled.set(true);
            LaboratorySandboxClient.Session session = active.get();
            if (session != null) session.cancel();
        }

        public boolean isCancelled() {
            return cancelled.get();
        }

        private void attach(LaboratorySandboxClient.Session session) {
            active.set(session);
            if (cancelled.get() && session != null) {
                session.cancel();
            }
        }

        private void detach(LaboratorySandboxClient.Session session) {
            active.compareAndSet(session, null);
        }
    }

    private static final ExecutorService IO =
        Executors.newSingleThreadExecutor();
    private static final Handler MAIN =
        new Handler(Looper.getMainLooper());

    private static final class RunState {
        final Context app;
        final String projectId;
        final LaboratoryToolRegistry.Descriptor descriptor;
        final LaboratoryToolArtifactStore.Binding binding;
        final List<TestCase> cases;
        final Control control;
        final Observer observer;
        final Completion completion;
        final List<CaseResult> results = new ArrayList<>();
        boolean completed;

        RunState(
                Context app,
                String projectId,
                LaboratoryToolRegistry.Descriptor descriptor,
                LaboratoryToolArtifactStore.Binding binding,
                List<TestCase> cases,
                Control control,
                Observer observer,
                Completion completion) {
            this.app = app;
            this.projectId = projectId;
            this.descriptor = descriptor;
            this.binding = binding;
            this.cases = cases;
            this.control = control;
            this.observer = observer;
            this.completion = completion;
        }
    }

    private LaboratoryCandidateTestSuiteRunner() {}

    public static void run(
            Context context,
            String projectId,
            String toolId,
            String version,
            List<TestCase> cases,
            Control control,
            Observer observer,
            Completion completion) {
        if (context == null
                || projectId == null
                || toolId == null
                || version == null
                || control == null
                || completion == null) {
            throw new IllegalArgumentException(
                "candidate suite input missing");
        }

        final List<TestCase> requested =
            validateRequestedCases(cases);
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try {
                LaboratoryToolRegistry registry =
                    new LaboratoryToolRegistry(
                        app.getFilesDir(), projectId);
                LaboratoryToolRegistry.Descriptor descriptor =
                    registry.readDescriptor(toolId, version);
                if (registry.stage(toolId, version)
                        != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
                    throw new IOException(
                        "candidate suite requires EXPERIMENTAL tool version");
                }

                requireRequiredTests(descriptor, requested);

                LaboratoryToolArtifactStore.Binding binding =
                    new LaboratoryToolArtifactStore(
                        app.getFilesDir(), projectId)
                        .readVerified(toolId, version);
                if (!descriptor.artifactSha256.equals(
                        binding.artifactSha256)) {
                    throw new IOException(
                        "verified candidate artifact does not match descriptor");
                }

                LaboratoryReportStore reports =
                    new LaboratoryReportStore(
                        app.getFilesDir(), projectId);
                int usedReports = reports.list().size();
                if (LaboratoryReportStore.MAX_REPORTS - usedReports
                        < requested.size()) {
                    throw new IOException(
                        "insufficient report capacity for candidate suite");
                }

                RunState state = new RunState(
                    app,
                    projectId,
                    descriptor,
                    binding,
                    requested,
                    control,
                    observer,
                    completion);
                notifySuiteReady(state);
                runCase(state, 0);
            } catch (Exception error) {
                IOException failure = asIo(error);
                MAIN.post(() -> completion.onFinished(null, failure));
            }
        });
    }

    private static void runCase(
            RunState state,
            int index) {
        IO.execute(() -> {
            if (state.completed) return;

            if (state.control.isCancelled()) {
                finish(
                    state,
                    Status.CANCELLED,
                    null);
                return;
            }

            if (index >= state.cases.size()) {
                boolean allPassed = true;
                for (CaseResult result : state.results) {
                    if (!result.passed) {
                        allPassed = false;
                        break;
                    }
                }
                finish(
                    state,
                    allPassed ? Status.PASS : Status.FAIL,
                    null);
                return;
            }

            TestCase testCase = state.cases.get(index);
            notifyCaseStarted(
                state,
                index + 1,
                testCase);

            final LaboratorySandboxClient.Session session;
            try {
                session = LaboratoryCandidateRunner.runInternal(
                    state.app,
                    state.projectId,
                    state.binding.luauSource(),
                    testCase.toolInput,
                    testCase.name,
                    testCase.expectedFirstReturn,
                    testCase.seed,
                    Math.min(
                        testCase.timeoutMs,
                        state.descriptor.maxRuntimeMs),
                    (execution, testPassed, recordingError) -> {
                        state.control.detach(
                            state.control.active.get());

                        if (execution == null) {
                            finish(
                                state,
                                Status.EVIDENCE_ERROR,
                                recordingError == null
                                    ? new IOException(
                                        "candidate suite execution missing")
                                    : recordingError);
                            return;
                        }

                        CaseResult caseResult =
                            new CaseResult(
                                testCase,
                                execution,
                                testPassed);
                        state.results.add(caseResult);
                        notifyCaseFinished(
                            state,
                            index + 1,
                            caseResult);

                        if (recordingError != null) {
                            finish(
                                state,
                                Status.EVIDENCE_ERROR,
                                recordingError);
                            return;
                        }

                        if (state.control.isCancelled()
                                || "CANCELLED".equals(
                                    execution.status)) {
                            finish(
                                state,
                                Status.CANCELLED,
                                null);
                            return;
                        }

                        runCase(state, index + 1);
                    });
            } catch (Exception error) {
                finish(
                    state,
                    Status.EVIDENCE_ERROR,
                    asIo(error));
                return;
            }

            state.control.attach(session);
        });
    }

    private static void finish(
            RunState state,
            Status status,
            IOException failure) {
        if (state.completed) return;
        state.completed = true;
        Result result = new Result(
            state.descriptor.toolId,
            state.descriptor.version,
            state.binding.artifactSha256,
            state.binding.snapshotId,
            status,
            state.results);
        notifyFinished(state, result);
        MAIN.post(() ->
            state.completion.onFinished(result, failure));
    }

    private static List<TestCase> validateRequestedCases(
            List<TestCase> cases) {
        if (cases == null
                || cases.isEmpty()
                || cases.size() > MAX_CASES) {
            throw new IllegalArgumentException(
                "invalid candidate suite case count");
        }

        List<TestCase> copy = new ArrayList<>();
        Set<String> names = new HashSet<>();
        for (TestCase testCase : cases) {
            if (testCase == null
                    || !names.add(testCase.name)) {
                throw new IllegalArgumentException(
                    "duplicate or missing candidate suite test");
            }
            copy.add(testCase);
        }
        return Collections.unmodifiableList(copy);
    }

    private static void requireRequiredTests(
            LaboratoryToolRegistry.Descriptor descriptor,
            List<TestCase> cases) throws IOException {
        Set<String> requested = new HashSet<>();
        for (TestCase testCase : cases) {
            requested.add(testCase.name);
        }
        Set<String> required =
            new HashSet<>(descriptor.requiredTests);
        if (!requested.equals(required)) {
            throw new IOException(
                "candidate suite must match descriptor requiredTests exactly");
        }
    }

    private static void notifySuiteReady(RunState state) {
        if (state.observer == null) return;
        MAIN.post(() -> {
            try {
                state.observer.onSuiteReady(
                    state.descriptor.toolId,
                    state.descriptor.version,
                    state.cases.size());
            } catch (RuntimeException ignored) {
                // Observability never controls candidate testing.
            }
        });
    }

    private static void notifyCaseStarted(
            RunState state,
            int index,
            TestCase testCase) {
        if (state.observer == null) return;
        MAIN.post(() -> {
            try {
                state.observer.onCaseStarted(
                    index,
                    state.cases.size(),
                    testCase);
            } catch (RuntimeException ignored) {
                // Observability never controls candidate testing.
            }
        });
    }

    private static void notifyCaseFinished(
            RunState state,
            int index,
            CaseResult result) {
        if (state.observer == null) return;
        MAIN.post(() -> {
            try {
                state.observer.onCaseFinished(
                    index,
                    state.cases.size(),
                    result);
            } catch (RuntimeException ignored) {
                // Observability never controls candidate testing.
            }
        });
    }

    private static void notifyFinished(
            RunState state,
            Result result) {
        if (state.observer == null) return;
        MAIN.post(() -> {
            try {
                state.observer.onFinished(result);
            } catch (RuntimeException ignored) {
                // Observability never controls candidate testing.
            }
        });
    }

    private static IOException asIo(Throwable error) {
        if (error instanceof IOException) {
            return (IOException) error;
        }
        return new IOException(
            error == null
                ? "candidate suite failed"
                : String.valueOf(error.getMessage()),
            error);
    }
}
