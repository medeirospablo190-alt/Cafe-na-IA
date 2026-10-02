package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;

/**
 * Explicit host-side transition from a validated LLM plan to the deterministic
 * TestAgent.
 *
 * Preparing a scenario never claims or executes the Goal Lock. Execution
 * happens only through executePrepared(), which re-reads and revalidates both
 * immutable records before delegating to LaboratoryAiTestScenarioRunner.
 */
public final class LaboratoryAiValidatedPlanExecutionGate {
    public static final class Prepared {
        public final String contractId;
        public final String contractSha256;
        public final String goalSha256;
        public final String scenarioId;
        public final String scenarioSha256;
        public final int stepCount;
        public final boolean stopOnFailure;

        private Prepared(
                LaboratoryAiTaskContractStore.Contract contract,
                LaboratoryAiTestScenarioStore.Scenario scenario) {
            this.contractId = contract.contractId;
            this.contractSha256 = contract.contractSha256;
            this.goalSha256 = contract.goalSha256;
            this.scenarioId = scenario.scenarioId;
            this.scenarioSha256 = scenario.scenarioSha256;
            this.stepCount = scenario.stepCount;
            this.stopOnFailure = scenario.stopOnFailure;
        }
    }

    public static final class Execution {
        public final String contractId;
        public final String scenarioId;
        public final String scenarioSha256;
        public final String reportId;
        public final String status;
        public final String sessionId;
        public final boolean goalLockClaimed;
        public final boolean resultRecorded;
        public final String terminalReason;
        public final int plannedSteps;
        public final int executedSteps;
        public final int passed;
        public final int failed;
        public final long durationMs;

        private Execution(
                Prepared prepared,
                LaboratoryAiTestScenarioRunner.Result result,
                LaboratoryAiTaskContractStore.Contract persistedContract) {
            this.contractId = prepared.contractId;
            this.scenarioId = result.scenarioId;
            this.scenarioSha256 = result.scenarioSha256;
            this.reportId = result.reportId;
            this.status = result.status;
            this.sessionId = result.sessionId;
            this.goalLockClaimed = persistedContract.claimed;
            this.resultRecorded = persistedContract.resultRecorded;
            this.terminalReason = result.terminalReason;
            this.plannedSteps = result.plannedSteps;
            this.executedSteps = result.executedSteps;
            this.passed = result.passed;
            this.failed = result.failed;
            this.durationMs = result.durationMs;
        }
    }

    private LaboratoryAiValidatedPlanExecutionGate() {}

    public static Prepared prepare(
            Context context,
            String projectId,
            String contractId,
            LaboratoryAiTestAgent.Plan plan) throws IOException {
        if (context == null || plan == null
                || contractId == null || contractId.isEmpty()) {
            throw new IllegalArgumentException(
                "validated plan gate input missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "validated plan preparation must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        String safeProjectId = projectId == null ? "" : projectId;
        LaboratoryAiTaskContractStore contracts =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), safeProjectId);

        LaboratoryAiTaskContractStore.Contract contract =
            contracts.read(contractId);
        requireUnused(contract);

        LaboratoryAiTestPlanContract.requireValid(contract, plan);

        LaboratoryAiTestScenarioStore scenarios =
            new LaboratoryAiTestScenarioStore(
                app.getFilesDir(), safeProjectId);
        String name =
            "LLM " + contract.contractId.substring(0, 8)
                + " • " + contract.mode.name();
        LaboratoryAiTestScenarioStore.Scenario scenario =
            scenarios.create(name, plan);

        LaboratoryAiTaskContractStore.Contract after =
            contracts.read(contractId);
        requireUnused(after);
        if (!contract.contractSha256.equals(after.contractSha256)) {
            throw new IOException(
                "Goal Lock changed while preparing validated plan");
        }

        LaboratoryAiTestScenarioStore.Scenario stored =
            scenarios.read(scenario.scenarioId);
        if (!scenario.scenarioSha256.equals(stored.scenarioSha256)) {
            throw new IOException(
                "prepared test scenario integrity changed");
        }

        return new Prepared(after, stored);
    }

    public static Execution executePrepared(
            Context context,
            String projectId,
            Prepared prepared) throws IOException {
        return executePrepared(
            context,
            projectId,
            prepared,
            null);
    }

    public static Execution executePrepared(
            Context context,
            String projectId,
            Prepared prepared,
            LaboratoryAiTestAgent.Observer observer) throws IOException {
        if (context == null || prepared == null) {
            throw new IllegalArgumentException(
                "prepared execution gate input missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "validated plan execution must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        String safeProjectId = projectId == null ? "" : projectId;
        LaboratoryAiTaskContractStore contracts =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), safeProjectId);
        LaboratoryAiTaskContractStore.Contract contract =
            contracts.read(prepared.contractId);
        requireUnused(contract);

        if (!prepared.contractSha256.equals(contract.contractSha256)
                || !prepared.goalSha256.equals(contract.goalSha256)) {
            throw new IOException(
                "prepared execution no longer matches Goal Lock");
        }

        LaboratoryAiTestScenarioStore scenarios =
            new LaboratoryAiTestScenarioStore(
                app.getFilesDir(), safeProjectId);
        LaboratoryAiTestScenarioStore.Scenario scenario =
            scenarios.read(prepared.scenarioId);
        if (!prepared.scenarioSha256.equals(scenario.scenarioSha256)
                || prepared.stepCount != scenario.stepCount
                || prepared.stopOnFailure != scenario.stopOnFailure) {
            throw new IOException(
                "prepared execution no longer matches scenario");
        }

        // Revalidate immediately before the one-use admission path. The
        // TestAgent will perform the authoritative validation again before
        // claiming the Goal Lock.
        LaboratoryAiTestPlanContract.requireValid(
            contract, scenario.plan);

        LaboratoryAiTestScenarioRunner.Result result =
            LaboratoryAiTestScenarioRunner.runBlocking(
                app,
                safeProjectId,
                scenario.scenarioId,
                contract.contractId,
                observer);

        if (!scenario.scenarioId.equals(result.scenarioId)
                || !scenario.scenarioSha256.equals(
                    result.scenarioSha256)) {
            throw new IOException(
                "test execution report does not match prepared scenario");
        }

        LaboratoryAiTaskContractStore.Contract persisted =
            contracts.read(contract.contractId);
        return new Execution(prepared, result, persisted);
    }

    private static void requireUnused(
            LaboratoryAiTaskContractStore.Contract contract) {
        if (contract.claimed || contract.resultRecorded) {
            throw new IllegalStateException(
                "validated plan gate requires an unused Goal Lock");
        }
    }
}
