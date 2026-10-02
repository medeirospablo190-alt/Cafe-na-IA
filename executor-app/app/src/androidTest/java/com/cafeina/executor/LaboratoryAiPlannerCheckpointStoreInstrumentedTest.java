package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiPlannerCheckpointStoreInstrumentedTest {
    @Test
    public void checkpointOverwritesLatestPlannerStateAndClears()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "checkpoint" + UUID.randomUUID().toString().substring(0, 8);
        String contractId = UUID.randomUUID().toString();

        LaboratoryAiPlannerCheckpointStore store =
            new LaboratoryAiPlannerCheckpointStore(
                app.getFilesDir(), project);

        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                contractId,
                null);
        tracker.update(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            "Processando prompt",
            1,
            2);
        tracker.updateNativeTelemetry(
            2,
            120,
            40,
            0,
            128,
            50L,
            2_000L,
            0L,
            30_000L,
            1,
            2);

        store.write(tracker.snapshot());

        LaboratoryAiPlannerCheckpointStore.Checkpoint first =
            store.read(contractId);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            first.phase);
        assertEquals(40, first.promptTokensProcessed);
        assertEquals(120, first.promptTokens);
        assertEquals(1, first.attempt);
        assertEquals(2, first.maxAttempts);

        tracker.updateNativeTelemetry(
            2,
            120,
            85,
            0,
            128,
            50L,
            4_000L,
            0L,
            30_000L,
            1,
            2);
        store.write(tracker.snapshot());

        LaboratoryAiPlannerCheckpointStore.Checkpoint latest =
            store.read(contractId);
        assertEquals(first.executionId, latest.executionId);
        assertEquals(85, latest.promptTokensProcessed);
        assertTrue(
            latest.updatedAtEpochMs >= first.updatedAtEpochMs);

        Path checkpointRoot = app.getFilesDir()
            .toPath()
            .resolve("laboratory")
            .resolve("project-" + project)
            .resolve("ai-planner-checkpoints");
        String raw = new String(
            Files.readAllBytes(
                checkpointRoot.resolve(contractId + ".json")),
            StandardCharsets.UTF_8);
        assertFalse(raw.contains("PRIVATE_GOAL"));
        assertFalse(raw.contains("PRIVATE_PROMPT"));
        assertFalse(raw.contains("PRIVATE_MODEL_OUTPUT"));

        store.clear(contractId);
        assertNull(store.read(contractId));
    }

    @Test
    public void terminalStateCannotBeStoredAsLiveCheckpoint()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "checkpointterminal"
                + UUID.randomUUID().toString().substring(0, 8);
        String contractId = UUID.randomUUID().toString();

        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                contractId,
                null);
        tracker.complete("Fim", 1, 1);

        LaboratoryAiPlannerCheckpointStore store =
            new LaboratoryAiPlannerCheckpointStore(
                app.getFilesDir(), project);
        boolean failed = false;
        try {
            store.write(tracker.snapshot());
        } catch (java.io.IOException expected) {
            failed = true;
        }
        assertTrue(failed);
        assertNull(store.read(contractId));
    }
}
