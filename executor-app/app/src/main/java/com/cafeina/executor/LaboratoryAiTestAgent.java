package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Deterministic "test AI" harness.
 *
 * This is intentionally not an LLM. It exercises the exact future AI path:
 * Goal Lock -> one-use admission -> AiTaskHandle -> granted STABLE tools ->
 * session audit -> deterministic report.
 */
public final class LaboratoryAiTestAgent {
    public static final int MAX_STEPS = 16;
    private static final long STEP_WAIT_MS =
        LaboratorySandboxService.MAX_TIMEOUT_MS + 8_000L;

    public static final class Step {
        public final String name;
        public final String toolId;
        public final String input;
        public final String expectedFirstReturn;

        public Step(String name, String toolId, String input,
                String expectedFirstReturn) {
            if (name == null || !name.matches("[a-zA-Z0-9_-]{1,64}")) {
                throw new IllegalArgumentException("invalid test-agent step name");
            }
            if (toolId == null
                    || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")) {
                throw new IllegalArgumentException("invalid test-agent tool id");
            }
            if (input == null
                    || input.length() > LaboratorySandboxService.MAX_INPUT_CHARS) {
                throw new IllegalArgumentException("test-agent input is too large");
            }
            if (expectedFirstReturn == null
                    || expectedFirstReturn.length()
                        > LaboratorySandboxService.MAX_RESPONSE_CHARS) {
                throw new IllegalArgumentException(
                    "test-agent expected return is too large");
            }
            this.name = name;
            this.toolId = toolId;
            this.input = input;
            this.expectedFirstReturn = expectedFirstReturn;
        }
    }

    public static final class Plan {
        public final List<Step> steps;
        public final boolean stopOnFailure;

        public Plan(List<Step> steps, boolean stopOnFailure) {
            if (steps == null || steps.isEmpty() || steps.size() > MAX_STEPS) {
                throw new IllegalArgumentException("invalid test-agent step count");
            }
            List<Step> copy = new ArrayList<>();
            Set<String> names = new HashSet<>();
            for (Step step : steps) {
                if (step == null || !names.add(step.name)) {
                    throw new IllegalArgumentException(
                        "test-agent step names must be unique");
                }
                copy.add(step);
            }
            this.steps = Collections.unmodifiableList(copy);
            this.stopOnFailure = stopOnFailure;
        }
    }

    public static final class StepEvidence {
        public final String name;
        public final String toolId;
        public final String toolVersion;
        public final String runId;
        public final boolean passed;
        public final String reason;
        public final String inputSha256;
        public final String expectedReturnSha256;
        public final String actualReturnSha256;
        public final String outputSha256;
        public final long durationMs;

        private StepEvidence(String name, String toolId, String toolVersion,
                String runId, boolean passed, String reason,
                String inputSha256, String expectedReturnSha256,
                String actualReturnSha256, String outputSha256,
                long durationMs) {
            this.name = name;
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.runId = runId;
            this.passed = passed;
            this.reason = reason;
            this.inputSha256 = inputSha256;
            this.expectedReturnSha256 = expectedReturnSha256;
            this.actualReturnSha256 = actualReturnSha256;
            this.outputSha256 = outputSha256;
            this.durationMs = durationMs;
        }
    }

    public static final class Report {
        public final String reportId;
        public final String contractId;
        public final String goalSha256;
        public final String mode;
        public final String sessionId;
        public final String status;
        public final String terminalReason;
        public final long startedAtEpochMs;
        public final long durationMs;
        public final int plannedSteps;
        public final int executedSteps;
        public final int passed;
        public final int failed;
        public final boolean stopOnFailure;
        public final List<StepEvidence> steps;

        private Report(String reportId, String contractId,
                String goalSha256, String mode, String sessionId,
                String status, String terminalReason,
                long startedAtEpochMs, long durationMs,
                int plannedSteps, int executedSteps,
                int passed, int failed, boolean stopOnFailure,
                List<StepEvidence> steps) {
            this.reportId = reportId;
            this.contractId = contractId;
            this.goalSha256 = goalSha256;
            this.mode = mode;
            this.sessionId = sessionId;
            this.status = status;
            this.terminalReason = terminalReason;
            this.startedAtEpochMs = startedAtEpochMs;
            this.durationMs = durationMs;
            this.plannedSteps = plannedSteps;
            this.executedSteps = executedSteps;
            this.passed = passed;
            this.failed = failed;
            this.stopOnFailure = stopOnFailure;
            this.steps = Collections.unmodifiableList(new ArrayList<>(steps));
        }
    }

    public static final class Control {
        private final AtomicBoolean cancelRequested =
            new AtomicBoolean(false);
        private final AtomicReference<
            LaboratoryAiSessionController.HostHandle> host =
                new AtomicReference<>();
        private final AtomicReference<
            LaboratorySandboxClient.Session> invocation =
                new AtomicReference<>();

        public void cancel() {
            cancelRequested.set(true);

            LaboratorySandboxClient.Session active =
                invocation.get();
            if (active != null) {
                active.cancel();
            }

            LaboratoryAiSessionController.HostHandle currentHost =
                host.get();
            if (currentHost != null) {
                currentHost.cancel();
            }
        }

        public boolean isCancellationRequested() {
            return cancelRequested.get();
        }

        private void attachHost(
                LaboratoryAiSessionController.HostHandle value) {
            host.set(value);
            if (cancelRequested.get() && value != null) {
                value.cancel();
            }
        }

        private void detachHost(
                LaboratoryAiSessionController.HostHandle value) {
            host.compareAndSet(value, null);
        }

        private void attachInvocation(
                LaboratorySandboxClient.Session value) {
            invocation.set(value);
            if (cancelRequested.get() && value != null) {
                value.cancel();
            }
        }

        private void detachInvocation(
                LaboratorySandboxClient.Session value) {
            invocation.compareAndSet(value, null);
        }
    }

    public interface Observer {
        default void onAdmitted(String sessionId, int plannedSteps) {
        }

        default void onStepStarted(
                int stepIndex,
                int totalSteps,
                String stepName,
                String toolId) {
        }

        default void onStepFinished(
                int stepIndex,
                int totalSteps,
                StepEvidence evidence) {
        }

        default void onFinished(Report report) {
        }
    }

    private static final class StepOutcome {
        final StepEvidence evidence;
        final boolean callbackTimedOut;

        StepOutcome(StepEvidence evidence, boolean callbackTimedOut) {
            this.evidence = evidence;
            this.callbackTimedOut = callbackTimedOut;
        }
    }

    private LaboratoryAiTestAgent() {}

    public static Report runBlocking(Context context, String projectId,
            String contractId, Plan plan) throws IOException {
        return runBlocking(
            context,
            projectId,
            contractId,
            plan,
            new Control(),
            null);
    }

    public static Report runBlocking(
            Context context,
            String projectId,
            String contractId,
            Plan plan,
            Observer observer) throws IOException {
        return runBlocking(
            context,
            projectId,
            contractId,
            plan,
            new Control(),
            observer);
    }

    public static Report runBlocking(
            Context context,
            String projectId,
            String contractId,
            Plan plan,
            Control control,
            Observer observer) throws IOException {
        if (context == null || plan == null || control == null) {
            throw new IllegalArgumentException("test-agent context or plan missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "test agent must run off the UI thread");
        }

        if (control.isCancellationRequested()) {
            throw new IOException(
                "test agent cancelled before Goal Lock admission");
        }

        Context app = context.getApplicationContext();
        LaboratoryAiTestAgentReportStore reportStore =
            new LaboratoryAiTestAgentReportStore(app.getFilesDir(), projectId);
        reportStore.ensureWritable();

        LaboratoryAiTaskContractStore contractStore =
            new LaboratoryAiTaskContractStore(app.getFilesDir(), projectId);
        LaboratoryAiTaskContractStore.Contract contract =
            contractStore.read(contractId);
        LaboratoryAiTestPlanContract.requireValid(contract, plan);

        String reportId = UUID.randomUUID().toString();
        long started = System.currentTimeMillis();

        LaboratoryAiTaskAdmission.TaskHandles admitted;
        try {
            admitted = LaboratoryAiTaskAdmission.admit(
                app, projectId, contractId);
        } catch (IOException | RuntimeException admissionFailure) {
            Report report = new Report(
                reportId,
                contract.contractId,
                contract.goalSha256,
                contract.mode.name(),
                "",
                "ADMISSION_FAILED",
                reasonCode(admissionFailure),
                started,
                Math.max(0L, System.currentTimeMillis() - started),
                plan.steps.size(),
                0,
                0,
                0,
                plan.stopOnFailure,
                Collections.emptyList());
            reportStore.save(report);
            notifyFinished(observer, report);
            return report;
        }

        try {
            LaboratoryAiTeamRegistry team =
                new LaboratoryAiTeamRegistry(app.getFilesDir(), projectId);
            team.registerMember(
                "test-agent",
                "IA de Teste",
                LaboratoryAiTeamRegistry.ROLE_TESTER);
            team.bindSession(
                admitted.ai.sessionId(),
                "test-agent",
                contract.contractId);
        } catch (IOException attributionFailure) {
            admitted.host.cancel();
            throw new IOException(
                "test-agent session could not be attributed to AI team",
                attributionFailure);
        }

        control.attachHost(admitted.host);
        notifyAdmitted(
            observer,
            admitted.ai.sessionId(),
            plan.steps.size());

        List<StepEvidence> evidence = new ArrayList<>();
        int passed = 0;
        int failed = 0;
        boolean forcedInfrastructureCancel = false;
        String terminalReason = "";

        for (int stepIndex = 0;
                stepIndex < plan.steps.size();
                stepIndex++) {
            Step step = plan.steps.get(stepIndex);
            if (control.isCancellationRequested()) {
                terminalReason = "HOST_CANCELLED";
                admitted.host.cancel();
                break;
            }

            LaboratoryAiSessionController.Snapshot before =
                admitted.host.snapshot();
            if (before.state == LaboratoryAiSessionController.State.PAUSED) {
                terminalReason = "HOST_PAUSED";
                break;
            }
            if (before.state == LaboratoryAiSessionController.State.CANCELLED) {
                terminalReason = "HOST_CANCELLED";
                break;
            }
            if (before.state == LaboratoryAiSessionController.State.FINISHED) {
                terminalReason = "SESSION_FINISHED_EARLY";
                break;
            }

            notifyStepStarted(
                observer,
                stepIndex + 1,
                plan.steps.size(),
                step);
            StepOutcome outcome = runStep(
                admitted.ai,
                step,
                control);
            evidence.add(outcome.evidence);
            notifyStepFinished(
                observer,
                stepIndex + 1,
                plan.steps.size(),
                outcome.evidence);
            if (outcome.evidence.passed) {
                passed++;
            } else {
                failed++;
            }

            LaboratoryAiSessionController.Snapshot afterStep =
                admitted.host.snapshot();
            if (control.isCancellationRequested()
                    || afterStep.state
                        == LaboratoryAiSessionController.State.CANCELLED) {
                terminalReason = "HOST_CANCELLED";
                break;
            }
            if (afterStep.state
                    == LaboratoryAiSessionController.State.PAUSED) {
                terminalReason = "HOST_PAUSED";
                break;
            }

            if (outcome.callbackTimedOut) {
                forcedInfrastructureCancel = true;
                terminalReason = "STEP_CALLBACK_TIMEOUT";
                admitted.host.cancel();
                break;
            }
            if (!outcome.evidence.passed && plan.stopOnFailure) {
                terminalReason = "STOP_ON_FAILURE";
                break;
            }
        }

        LaboratoryAiSessionController.Snapshot end =
            admitted.host.snapshot();
        String status;

        if (forcedInfrastructureCancel) {
            status = "FAIL";
        } else if (end.state == LaboratoryAiSessionController.State.PAUSED) {
            status = "PAUSED";
            terminalReason = "HOST_PAUSED";
        } else if (end.state == LaboratoryAiSessionController.State.CANCELLED) {
            status = "CANCELLED";
            terminalReason = "HOST_CANCELLED";
        } else {
            boolean completePlan = evidence.size() == plan.steps.size();
            status = failed == 0 && completePlan ? "PASS" : "FAIL";
            if (terminalReason.isEmpty() && !"PASS".equals(status)) {
                terminalReason = completePlan
                    ? "STEP_FAILURE"
                    : "PLAN_INCOMPLETE";
            }

            if (end.state == LaboratoryAiSessionController.State.ACTIVE) {
                try {
                    admitted.host.complete();
                } catch (IOException completionFailure) {
                    status = "FAIL";
                    terminalReason = "HOST_COMPLETE_FAILED";
                }
            }
        }

        Report report = new Report(
            reportId,
            contract.contractId,
            contract.goalSha256,
            contract.mode.name(),
            admitted.ai.sessionId(),
            status,
            terminalReason,
            started,
            Math.max(0L, System.currentTimeMillis() - started),
            plan.steps.size(),
            evidence.size(),
            passed,
            failed,
            plan.stopOnFailure,
            evidence);

        try {
            reportStore.save(report);
            LaboratoryAiDiagnostics.schedule(
                app, projectId, admitted.ai.sessionId());
            notifyFinished(observer, report);
            control.detachHost(admitted.host);
        } catch (IOException saveFailure) {
            LaboratoryAiSessionController.Snapshot snapshot =
                admitted.host.snapshot();
            if (snapshot.state == LaboratoryAiSessionController.State.ACTIVE
                    || snapshot.state == LaboratoryAiSessionController.State.PAUSED) {
                admitted.host.cancel();
            }
            control.detachHost(admitted.host);
            throw new IOException(
                "test-agent run completed but report could not be persisted",
                saveFailure);
        }
        return report;
    }

    private static void notifyAdmitted(
            Observer observer,
            String sessionId,
            int plannedSteps) {
        if (observer == null) return;
        try {
            observer.onAdmitted(sessionId, plannedSteps);
        } catch (RuntimeException ignored) {
            // Observability must never control deterministic execution.
        }
    }

    private static void notifyStepStarted(
            Observer observer,
            int stepIndex,
            int totalSteps,
            Step step) {
        if (observer == null || step == null) return;
        try {
            observer.onStepStarted(
                stepIndex,
                totalSteps,
                step.name,
                step.toolId);
        } catch (RuntimeException ignored) {
            // Observability must never control deterministic execution.
        }
    }

    private static void notifyStepFinished(
            Observer observer,
            int stepIndex,
            int totalSteps,
            StepEvidence evidence) {
        if (observer == null || evidence == null) return;
        try {
            observer.onStepFinished(
                stepIndex,
                totalSteps,
                evidence);
        } catch (RuntimeException ignored) {
            // Observability must never control deterministic execution.
        }
    }

    private static void notifyFinished(
            Observer observer,
            Report report) {
        if (observer == null || report == null) return;
        try {
            observer.onFinished(report);
        } catch (RuntimeException ignored) {
            // Observability must never control deterministic execution.
        }
    }

    private static StepOutcome runStep(
            LaboratoryAiTaskAdmission.AiTaskHandle ai,
            Step step,
            Control control) {
        String inputSha = hash(step.input);
        String expectedSha = hash(step.expectedFirstReturn);
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryAiToolController.Execution> success =
            new AtomicReference<>();
        AtomicReference<IOException> failure = new AtomicReference<>();

        final LaboratorySandboxClient.Session launched;
        try {
            launched = ai.execute(step.toolId, step.input, (result, error) -> {
                success.set(result);
                failure.set(error);
                done.countDown();
            });
            control.attachInvocation(launched);
        } catch (IOException | RuntimeException launchFailure) {
            return new StepOutcome(
                failedEvidence(
                    step, inputSha, expectedSha,
                    "EXECUTE_" + reasonCode(launchFailure)),
                false);
        }

        try {
            if (!done.await(STEP_WAIT_MS, TimeUnit.MILLISECONDS)) {
                launched.cancel();
                return new StepOutcome(
                    failedEvidence(
                        step, inputSha, expectedSha, "CALLBACK_TIMEOUT"),
                    true);
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            launched.cancel();
            return new StepOutcome(
                failedEvidence(
                    step, inputSha, expectedSha, "THREAD_INTERRUPTED"),
                true);
        } finally {
            control.detachInvocation(launched);
        }

        IOException error = failure.get();
        LaboratoryAiToolController.Execution result = success.get();
        if (error != null || result == null) {
            return new StepOutcome(
                failedEvidence(
                    step, inputSha, expectedSha,
                    error == null ? "EMPTY_RESULT"
                        : "EXECUTE_" + reasonCode(error)),
                false);
        }

        String actual = result.firstReturn == null ? "" : result.firstReturn;
        String output = result.output == null ? "" : result.output;
        boolean matched = step.expectedFirstReturn.equals(actual);
        StepEvidence evidence = new StepEvidence(
            step.name,
            step.toolId,
            result.toolVersion == null ? "" : result.toolVersion,
            result.runId == null ? "" : result.runId,
            matched,
            matched ? "MATCH" : "RETURN_MISMATCH",
            inputSha,
            expectedSha,
            hash(actual),
            hash(output),
            Math.max(0L, result.durationMs));
        return new StepOutcome(evidence, false);
    }

    private static StepEvidence failedEvidence(
            Step step, String inputSha, String expectedSha, String reason) {
        return new StepEvidence(
            step.name,
            step.toolId,
            "",
            "",
            false,
            boundedReason(reason),
            inputSha,
            expectedSha,
            hash(""),
            hash(""),
            0L);
    }

    private static String reasonCode(Throwable error) {
        if (error == null) return "UNKNOWN";
        return boundedReason(error.getClass().getSimpleName());
    }

    private static String boundedReason(String value) {
        if (value == null || value.isEmpty()) return "UNKNOWN";
        String clean = value.replaceAll("[^A-Za-z0-9_-]", "_");
        return clean.length() <= 64 ? clean : clean.substring(0, 64);
    }

    private static String hash(String value) {
        String safe = value == null ? "" : value;
        return LaboratoryEngine.fingerprint(safe).substring(7, 71);
    }
}
