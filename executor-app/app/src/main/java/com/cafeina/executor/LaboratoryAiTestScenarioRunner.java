package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;

/**
 * Narrow launcher from immutable scenario catalog to the deterministic test AI.
 */
public final class LaboratoryAiTestScenarioRunner {
    public static final class Result {
        public final String scenarioId;
        public final String scenarioSha256;
        public final String reportId;
        public final String status;
        public final String sessionId;

        private Result(LaboratoryAiTestScenarioStore.Scenario scenario,
                LaboratoryAiTestAgent.Report report) {
            this.scenarioId = scenario.scenarioId;
            this.scenarioSha256 = scenario.scenarioSha256;
            this.reportId = report.reportId;
            this.status = report.status;
            this.sessionId = report.sessionId;
        }
    }

    private LaboratoryAiTestScenarioRunner() {}

    public static Result runBlocking(Context context, String projectId,
            String scenarioId, String contractId) throws IOException {
        return runBlocking(
            context,
            projectId,
            scenarioId,
            contractId,
            null);
    }

    public static Result runBlocking(
            Context context,
            String projectId,
            String scenarioId,
            String contractId,
            LaboratoryAiTestAgent.Observer observer) throws IOException {
        if (context == null) {
            throw new IllegalArgumentException("test-scenario context missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "test scenario must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        LaboratoryAiTestScenarioStore.Scenario scenario =
            new LaboratoryAiTestScenarioStore(
                app.getFilesDir(), projectId).read(scenarioId);

        // Agent performs the authoritative Goal Lock / budget / allowlist
        // validation before claiming the contract.
        LaboratoryAiTestAgent.Report report =
            LaboratoryAiTestAgent.runBlocking(
                app,
                projectId,
                contractId,
                scenario.plan,
                observer);
        return new Result(scenario, report);
    }
}
