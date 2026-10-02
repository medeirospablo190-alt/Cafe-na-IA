package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.List;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiExecutionHistoryStoreInstrumentedTest {
    @Test
    public void persistsOrderedBoundedPlannerStatusHistory() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        String projectId = "exec-history-" + UUID.randomUUID().toString();
        String contractId = UUID.randomUUID().toString();

        LaboratoryAiExecutionHistoryStore store =
            new LaboratoryAiExecutionHistoryStore(
                context.getFilesDir(),
                projectId);

        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                contractId,
                null);

        tracker.update(
            LaboratoryAiExecutionStatus.Phase.MODEL_ADMISSION,
            "Validando modelo local admitido");
        tracker.update(
            LaboratoryAiExecutionStatus.Phase.PLANNING,
            "Gerando proposta de plano JSON",
            1,
            2);
        tracker.updateNativePhase(2, 1, 2);
        tracker.fail(
            "local model timed out while processing prompt");
        store.saveExecution(tracker.history());
        store.saveExecution(tracker.history());

        List<LaboratoryAiExecutionHistoryStore.Summary> summaries =
            store.list();
        assertEquals(1, summaries.size());

        LaboratoryAiExecutionHistoryStore.Summary summary =
            summaries.get(0);
        assertEquals(
            tracker.snapshot().executionId,
            summary.executionId);
        assertEquals(contractId, summary.contractId);
        assertEquals(
            LaboratoryAiExecutionStatus.State.FAILED,
            summary.state);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            summary.phase);
        assertEquals(1, summary.attempt);
        assertEquals(2, summary.maxAttempts);
        assertTrue(summary.eventCount >= 5);
        assertEquals(
            "local model timed out while processing prompt",
            summary.terminalReason);

        List<LaboratoryAiExecutionHistoryStore.Event> events =
            store.readEvents(summary.executionId);
        assertEquals(summary.eventCount, events.size());
        assertEquals(1, events.get(0).sequence);
        assertEquals(
            events.size(),
            events.get(events.size() - 1).sequence);
        assertEquals(
            LaboratoryAiExecutionStatus.State.FAILED,
            events.get(events.size() - 1).state);
        assertTrue(
            events.get(events.size() - 1).elapsedMs
                >= events.get(0).elapsedMs);
        assertFalse(
            events.get(events.size() - 1)
                .terminalReason.isEmpty());
    }

    @Test
    public void completedExecutionEndsWithCompletedPhase() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        String projectId = "exec-history-" + UUID.randomUUID().toString();
        String contractId = UUID.randomUUID().toString();

        LaboratoryAiExecutionHistoryStore store =
            new LaboratoryAiExecutionHistoryStore(
                context.getFilesDir(),
                projectId);

        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                contractId,
                null);

        tracker.update(
            LaboratoryAiExecutionStatus.Phase.VALIDATING,
            "Validando proposta determinística",
            1,
            2);
        tracker.complete(
            "Plano produzido e validado",
            1,
            2);
        store.saveExecution(tracker.history());

        LaboratoryAiExecutionHistoryStore.Summary summary =
            store.list().get(0);
        assertEquals(
            LaboratoryAiExecutionStatus.State.COMPLETED,
            summary.state);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.COMPLETED,
            summary.phase);
        assertTrue(summary.terminalReason.isEmpty());
    }
}
