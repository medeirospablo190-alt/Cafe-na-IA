package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
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
public final class LaboratoryAiPlannerEnvironmentStoreInstrumentedTest {
    @Test
    public void environmentSnapshotPersistsPreflightAndRuntimeMetadata()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "env" + UUID.randomUUID().toString().substring(0, 8);
        String contractId = UUID.randomUUID().toString();

        Path models = app.getFilesDir()
            .toPath()
            .resolve("models");
        Files.createDirectories(models);

        Path modelPath = models.resolve(
            "diag-" + UUID.randomUUID().toString().substring(0, 8)
                + ".gguf");
        byte[] modelBytes = new byte[] {
            0x47, 0x47, 0x55, 0x46,
            0x01, 0x00, 0x00, 0x00
        };
        Files.write(modelPath, modelBytes);

        try {
            LaboratoryAiLocalModelAdmission.AdmittedModel model =
                LaboratoryAiLocalModelAdmission.admit(
                    app.getFilesDir(),
                    modelPath.toFile());
            LaboratoryAiLocalModelPreflight.Report preflight =
                LaboratoryAiLocalModelPreflight.inspect(app, model);
            LaboratoryAiLlamaCppBackend.RuntimeConfig config =
                LaboratoryAiLlamaCppBackend.RuntimeConfig
                    .plannerDefaults();

            LaboratoryAiPlannerEnvironmentStore store =
                new LaboratoryAiPlannerEnvironmentStore(
                    app.getFilesDir(), project);
            store.writePreflight(
                contractId,
                model,
                preflight,
                config);
            store.updateRuntimeMetadata(
                contractId,
                "runtime-test-version",
                "model-test-description");

            LaboratoryAiPlannerEnvironmentStore.Snapshot snapshot =
                store.read(contractId);

            assertNotNull(snapshot);
            assertEquals(contractId, snapshot.contractId);
            assertEquals(model.fileName, snapshot.modelFileName);
            assertEquals(model.sizeBytes, snapshot.modelSizeBytes);
            assertEquals(preflight.status, snapshot.preflightStatus);
            assertEquals(
                preflight.availableRamBytes,
                snapshot.availableRamBytes);
            assertEquals(config.contextTokens, snapshot.contextTokens);
            assertEquals(config.maxTokens, snapshot.maxTokens);
            assertEquals(config.threads, snapshot.threads);
            assertEquals(
                config.maxGenerationMs,
                snapshot.maxGenerationMs);
            assertEquals(
                "runtime-test-version",
                snapshot.runtimeVersion);
            assertEquals(
                "model-test-description",
                snapshot.modelDescription);

            Path record = app.getFilesDir()
                .toPath()
                .resolve("laboratory")
                .resolve("project-" + project)
                .resolve("ai-planner-environment")
                .resolve(contractId + ".json");
            String raw = new String(
                Files.readAllBytes(record),
                StandardCharsets.UTF_8);
            assertFalse(raw.contains("PRIVATE_GOAL"));
            assertFalse(raw.contains("PRIVATE_PROMPT"));
            assertFalse(raw.contains("PRIVATE_MODEL_OUTPUT"));
            assertTrue(raw.length()
                <= LaboratoryAiPlannerEnvironmentStore.MAX_FILE_BYTES);
        } finally {
            Files.deleteIfExists(modelPath);
        }
    }
}
