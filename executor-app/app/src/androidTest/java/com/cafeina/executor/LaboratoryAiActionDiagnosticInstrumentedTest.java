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

import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiActionDiagnosticInstrumentedTest {
    @Test
    public void diagnosisReadsPlannerFailureWithoutConsumingGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "actiondiag" + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project);
        LaboratoryAiTaskContractStore.Contract contract =
            store.create(
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Verificar o gargalo do planejador sem executar ferramenta.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList("diagnostic.tool"),
                    1,
                    256,
                    30_000L));

        LaboratoryAiExecutionStatus.Tracker tracker =
            new LaboratoryAiExecutionStatus.Tracker(
                contract.contractId,
                null);
        tracker.update(
            LaboratoryAiExecutionStatus.Phase.PLANNING,
            "Montando plano",
            1,
            2);
        tracker.updateNativeTelemetry(
            2,
            120,
            40,
            0,
            128,
            100L,
            2_000L,
            0L,
            30_000L,
            1,
            2);
        tracker.fail("local model timed out while processing prompt");

        new LaboratoryAiExecutionHistoryStore(
            app.getFilesDir(), project)
            .saveExecution(tracker.history());

        LaboratoryAiActionDiagnostic.Snapshot diagnosis =
            LaboratoryAiActionDiagnostic.inspect(
                app.getFilesDir(),
                project,
                contract.contractId);

        assertEquals(
            LaboratoryAiActionDiagnostic.Stage.PLANNER_FAILED,
            diagnosis.stage);
        assertFalse(diagnosis.goalLockClaimed);
        assertFalse(diagnosis.resultRecorded);
        assertEquals(1, diagnosis.allowedToolCount);
        assertEquals(
            LaboratoryAiPlannerExecutionDiagnostic.Code.PROMPT_TIMEOUT,
            diagnosis.plannerDiagnostic.code);
        assertEquals(
            "PROFILE_PROMPT_EVAL_THROUGHPUT",
            diagnosis.nextCheck);
        assertTrue(
            diagnosis.nextStep.contains("tamanho do prompt"));
        assertTrue(diagnosis.explanation.contains("40/120"));
        assertNull(diagnosis.testReport);

        LaboratoryAiTaskContractStore.Contract after =
            store.read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void freshGoalLockReportsReadyWithoutInventingExecution()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "actionfresh" + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiTaskContractStore.Contract contract =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .create(
                    LaboratoryAiTaskContractStore.Mode.CREATION,
                    "Criar algo somente depois da minha confirmação.",
                    new LaboratoryAiSessionController.Policy(
                        Collections.singletonList("diagnostic.tool"),
                        2,
                        512,
                        30_000L));

        LaboratoryAiActionDiagnostic.Snapshot diagnosis =
            LaboratoryAiActionDiagnostic.inspect(
                app.getFilesDir(),
                project,
                contract.contractId);

        assertEquals(
            LaboratoryAiActionDiagnostic.Stage.GOAL_LOCK_READY,
            diagnosis.stage);
        assertNull(diagnosis.planner);
        assertNull(diagnosis.plannerDiagnostic);
        assertNull(diagnosis.testReport);
        assertTrue(
            diagnosis.nextStep.contains("gere o plano"));
        assertFalse(diagnosis.goalLockClaimed);
        assertFalse(diagnosis.resultRecorded);
    }
}
