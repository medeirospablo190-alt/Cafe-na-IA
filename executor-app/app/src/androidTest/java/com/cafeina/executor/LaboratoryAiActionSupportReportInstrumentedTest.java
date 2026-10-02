package com.cafeina.executor;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiActionSupportReportInstrumentedTest {
    @Test
    public void supportReportOmitsSensitiveTaskContent()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "support" + UUID.randomUUID().toString().substring(0, 8);
        String secretGoal =
            "PRIVATE_GOAL_DO_NOT_EXPORT_"
                + UUID.randomUUID().toString();

        LaboratoryAiTaskContractStore.Contract contract =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .create(
                    LaboratoryAiTaskContractStore.Mode.LEARNING,
                    secretGoal,
                    new LaboratoryAiSessionController.Policy(
                        Collections.singletonList("support.tool"),
                        2,
                        1024,
                        30_000L));

        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                contract.contractId,
                null);
        tracker.update(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            "Processando prompt",
            1,
            1);
        tracker.updateNativeTelemetry(
            2,
            100,
            25,
            0,
            64,
            20L,
            900L,
            0L,
            30_000L,
            1,
            1);
        new LaboratoryAiPlannerCheckpointStore(
            app.getFilesDir(), project)
            .write(tracker.snapshot());

        String report =
            LaboratoryAiActionSupportReport.build(
                app.getFilesDir(),
                project,
                contract.contractId,
                "");

        assertFalse(report.contains(secretGoal));
        assertFalse(report.contains("Processando prompt"));
        assertTrue(report.contains("[PLANEJADOR_CHECKPOINT]"));
        assertTrue(report.contains("prompt_tokens=25/100"));
        assertTrue(report.contains("objetivo_exato=OMITIDO"));
        assertTrue(report.contains("prompt=OMITIDO"));
        assertTrue(
            report.length()
                <= LaboratoryAiActionSupportReport.MAX_REPORT_CHARS);
    }
}
