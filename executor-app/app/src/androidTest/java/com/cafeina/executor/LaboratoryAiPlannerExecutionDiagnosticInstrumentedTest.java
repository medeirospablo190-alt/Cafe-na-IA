package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiPlannerExecutionDiagnosticInstrumentedTest {
    @Test
    public void classifiesPromptTimeoutFromRealExecutionPhase() {
        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                UUID.randomUUID().toString(),
                null);

        tracker.update(
            LaboratoryAiExecutionStatus.Phase.PLANNING,
            "Gerando proposta de plano JSON",
            1,
            2);
        tracker.updateNativePhase(2, 1, 2);
        tracker.fail(
            "local model timed out while processing prompt");

        LaboratoryAiPlannerExecutionDiagnostic.Result result =
            LaboratoryAiPlannerExecutionDiagnostic.analyze(
                tracker.snapshot());

        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.PROMPT_TIMEOUT,
            result.code);
        assertEquals(
            "MEASURE_PROMPT_TOKENS_AND_PROMPT_EVAL_SPEED",
            result.nextCheck);
        assertTrue(
            result.explanation.contains("processava o prompt"));
    }

    @Test
    public void explainsFirstPromptBatchTimeoutFromTelemetry() {
        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                UUID.randomUUID().toString(),
                null);
        tracker.updateNativeTelemetry(
            2,
            1200,
            0,
            0,
            1024,
            900L,
            120_000L,
            0L,
            120_000L,
            1,
            2);
        tracker.fail(
            "local model timed out while processing prompt");

        LaboratoryAiPlannerExecutionDiagnostic.Result result =
            LaboratoryAiPlannerExecutionDiagnostic.analyze(
                tracker.snapshot());

        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.PROMPT_TIMEOUT,
            result.code);
        assertEquals(
            "MEASURE_FIRST_PROMPT_BATCH_LATENCY",
            result.nextCheck);
        assertTrue(result.explanation.contains("nenhum batch completo"));
        assertTrue(result.explanation.contains("1200"));
    }

    @Test
    public void distinguishesTokenTimeoutAndUserCancellation() {
        LaboratoryAiExecutionStatus.Tracker timeout =
            new LaboratoryAiExecutionStatus.Tracker(
                UUID.randomUUID().toString(),
                null);
        timeout.updateNativePhase(3, 1, 2);
        timeout.fail(
            "local model timed out while generating tokens");

        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.TOKEN_TIMEOUT,
            LaboratoryAiPlannerExecutionDiagnostic
                .analyze(timeout.snapshot()).code);

        LaboratoryAiExecutionStatus.Tracker cancelled =
            new LaboratoryAiExecutionStatus.Tracker(
                UUID.randomUUID().toString(),
                null);
        cancelled.cancel("Planejamento cancelado pelo usuário");

        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.USER_CANCELLED,
            LaboratoryAiPlannerExecutionDiagnostic
                .analyze(cancelled.snapshot()).code);
    }
}
