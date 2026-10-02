package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.ArrayList;
import java.util.List;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiExecutionStatusInstrumentedTest {
    @Test
    public void preservesRealWorkPhaseWhenExecutionFails() {
        List<LaboratoryAiExecutionStatus.Snapshot> events =
            new ArrayList<>();
        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                "contract-status-test",
                events::add);

        tracker.update(
            LaboratoryAiExecutionStatus.Phase.PREFLIGHT,
            "Verificando modelo");
        tracker.update(
            LaboratoryAiExecutionStatus.Phase.PLANNING,
            "Gerando plano",
            1,
            2);
        tracker.updateNativePhase(2, 1, 2);
        tracker.updateNativeTelemetry(
            2,
            1000,
            500,
            0,
            1024,
            1200L,
            10_000L,
            0L,
            120_000L,
            1,
            2);
        tracker.fail("local model timed out while processing prompt");

        LaboratoryAiExecutionStatus.Snapshot snapshot =
            tracker.snapshot();
        assertEquals(
            LaboratoryAiExecutionStatus.State.FAILED,
            snapshot.state);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            snapshot.phase);
        assertEquals(1, snapshot.attempt);
        assertEquals(2, snapshot.maxAttempts);
        assertEquals(
            "local model timed out while processing prompt",
            snapshot.terminalReason);
        assertEquals(1000, snapshot.promptTokens);
        assertEquals(500, snapshot.promptTokensProcessed);
        assertEquals(1200L, snapshot.contextSetupMs);
        assertEquals(10_000L, snapshot.promptEvalMs);
        assertEquals(120_000L, snapshot.generationTimeLimitMs);
        assertEquals(10_000L, snapshot.estimatedRemainingMs);
        assertEquals(50.0, snapshot.promptTokensPerSecond(), 0.001);
        assertTrue(snapshot.elapsedMs >= 0L);
        assertTrue(events.size() >= 4);

        tracker.update(
            LaboratoryAiExecutionStatus.Phase.VALIDATING,
            "não deve substituir terminal");
        assertEquals(
            LaboratoryAiExecutionStatus.State.FAILED,
            tracker.snapshot().state);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            tracker.snapshot().phase);
    }

    @Test
    public void nativeNoneDoesNotInventProgressAndCancelIsTerminal() {
        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                "contract-cancel-test",
                null);

        tracker.updateNativePhase(0, 0, 0);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.PREPARING,
            tracker.snapshot().phase);

        tracker.cancel("cancelado pelo usuário");
        assertEquals(
            LaboratoryAiExecutionStatus.State.CANCELLED,
            tracker.snapshot().state);
        assertTrue(tracker.snapshot().terminal());
        assertFalse(tracker.snapshot().terminalReason.isEmpty());
    }
}
