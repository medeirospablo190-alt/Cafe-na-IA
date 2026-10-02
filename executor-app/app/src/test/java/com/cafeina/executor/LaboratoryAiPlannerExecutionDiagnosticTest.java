package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.UUID;

public final class LaboratoryAiPlannerExecutionDiagnosticTest {
    @Test
    public void promptTimeoutReportsMeasuredThroughput() {
        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                UUID.randomUUID().toString(),
                null);

        tracker.update(
            LaboratoryAiExecutionStatus.Phase.PLANNING,
            "planning",
            1,
            2);
        tracker.updateNativeTelemetry(
            2,
            100,
            40,
            0,
            128,
            25L,
            2000L,
            0L,
            300000L,
            1,
            2);
        tracker.fail("timed out while processing prompt");

        LaboratoryAiPlannerExecutionDiagnostic.Result result =
            LaboratoryAiPlannerExecutionDiagnostic.analyze(
                tracker.snapshot());

        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.PROMPT_TIMEOUT,
            result.code);
        assertEquals(
            "PROFILE_PROMPT_EVAL_THROUGHPUT",
            result.nextCheck);
        assertTrue(result.explanation.contains("40/100"));
        assertTrue(result.explanation.contains("20.0 tok/s"));
    }

    @Test
    public void contextTimeoutKeepsContextSpecificDiagnosis() {
        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                UUID.randomUUID().toString(),
                null);

        tracker.updateNativeTelemetry(
            1,
            0,
            0,
            0,
            0,
            4200L,
            0L,
            0L,
            300000L,
            1,
            1);
        tracker.fail("context timeout");

        LaboratoryAiPlannerExecutionDiagnostic.Result result =
            LaboratoryAiPlannerExecutionDiagnostic.analyze(
                tracker.snapshot());

        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.CONTEXT_TIMEOUT,
            result.code);
        assertEquals(
            "PROFILE_CONTEXT_SETUP",
            result.nextCheck);
        assertTrue(result.explanation.contains("4200 ms"));
    }
}
