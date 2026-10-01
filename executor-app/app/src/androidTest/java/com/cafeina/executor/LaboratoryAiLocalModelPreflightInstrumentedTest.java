package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiLocalModelPreflightInstrumentedTest {
    @Test
    public void normalBuildReportsFactsWithoutLoadingModel()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        Path models = LaboratoryAiLocalModelAdmission
            .modelDirectory(app.getFilesDir()).toPath();
        Files.createDirectories(models);
        Path model = models.resolve(
            "preflight-" + UUID.randomUUID() + ".gguf");
        Files.write(model, new byte[] {
            0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00
        });

        try {
            LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
                LaboratoryAiLocalModelAdmission.admit(
                    app.getFilesDir(), model.toFile());
            LaboratoryAiLocalModelPreflight.Report report =
                LaboratoryAiLocalModelPreflight.inspect(
                    app, admitted);

            assertEquals(8L, report.modelSizeBytes);
            assertTrue(report.cpuCores >= 1);
            assertTrue(report.totalRamBytes > 0L);
            assertTrue(report.availableRamBytes > 0L);
            assertTrue(report.lowMemoryThresholdBytes >= 0L);
            assertTrue(report.appUsableStorageBytes >= 0L);

            // The normal app CI intentionally does not package the optional
            // llama.cpp runtime. Preflight must report that fact without
            // attempting to load the fake GGUF.
            assertFalse(report.runtimePackaged);
            assertFalse(report.canAttemptLoad);
            assertEquals(
                LaboratoryAiLocalModelPreflight.STATUS_BLOCKED,
                report.status);
            assertTrue(report.signalCodes.contains(
                LaboratoryAiLocalModelPreflight.RUNTIME_NOT_PACKAGED));
        } finally {
            Files.deleteIfExists(model);
        }
    }

    @Test
    public void publicLoadPathRejectsUiThreadBeforeNativeLoad()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        AtomicReference<Throwable> failure =
            new AtomicReference<>();

        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            try {
                LaboratoryAiLocalModelPreflight.open(
                    app,
                    new java.io.File(
                        app.getFilesDir(), "models/not-loaded.gguf"),
                    LaboratoryAiLlamaCppBackend.RuntimeConfig
                        .plannerDefaults());
            } catch (Throwable error) {
                failure.set(error);
            }
        });

        assertTrue(
            "UI-thread model open was not rejected",
            failure.get() instanceof IllegalStateException);
    }
}
