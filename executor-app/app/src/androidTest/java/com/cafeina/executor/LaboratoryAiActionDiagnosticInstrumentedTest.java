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
    public void liveCheckpointExplainsInterruptedPlannerWithoutConsumingGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "actioncheckpoint"
                + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project);
        LaboratoryAiTaskContractStore.Contract contract =
            store.create(
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Investigar o planejador sem executar ferramentas.",
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
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            "Processando prompt",
            1,
            2);
        tracker.updateNativeTelemetry(
            2,
            150,
            63,
            0,
            128,
            90L,
            3_000L,
            0L,
            30_000L,
            1,
            2);

        new LaboratoryAiPlannerCheckpointStore(
            app.getFilesDir(), project)
            .write(tracker.snapshot());

        LaboratoryAiActionDiagnostic.Snapshot diagnosis =
            LaboratoryAiActionDiagnostic.inspect(
                app.getFilesDir(),
                project,
                contract.contractId);

        assertEquals(
            LaboratoryAiActionDiagnostic.Stage.PLANNER_RUNNING_OR_INTERRUPTED,
            diagnosis.stage);
        assertNull(diagnosis.planner);
        assertNull(diagnosis.plannerDiagnostic);
        assertTrue(diagnosis.plannerCheckpoint != null);
        assertEquals(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            diagnosis.plannerCheckpoint.phase);
        assertEquals(
            63,
            diagnosis.plannerCheckpoint.promptTokensProcessed);
        assertEquals(
            "REVIEW_PLANNER_CHECKPOINT",
            diagnosis.nextCheck);
        assertTrue(diagnosis.explanation.contains("63/150"));
        assertTrue(diagnosis.nextStep.contains("checkpoint"));
        assertFalse(diagnosis.goalLockClaimed);
        assertFalse(diagnosis.resultRecorded);

        LaboratoryAiTaskContractStore.Contract after =
            store.read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void claimedGoalLockFindsOrphanedTesterSessionWithoutReport()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "actiontester"
                + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "diagnostic.tool";

        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project);
        LaboratoryAiTaskContractStore.Contract contract =
            store.create(
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Testar diagnóstico de sessão interrompida.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    3,
                    1024,
                    30_000L));

        store.claim(contract.contractId);

        String sessionId = UUID.randomUUID().toString();
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(
                app.getFilesDir(), project);
        sessions.begin(
            sessionId,
            System.currentTimeMillis(),
            Collections.singletonList(toolId),
            3,
            1024,
            30_000L);

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(
                app.getFilesDir(), project);
        team.registerMember(
            "test-agent",
            "IA de Teste",
            LaboratoryAiTeamRegistry.ROLE_TESTER);
        team.bindSession(
            sessionId,
            "test-agent",
            contract.contractId);

        LaboratoryAiActionDiagnostic.Snapshot diagnosis =
            LaboratoryAiActionDiagnostic.inspect(
                app.getFilesDir(),
                project,
                contract.contractId);

        assertEquals(
            LaboratoryAiActionDiagnostic.Stage.TEST_AGENT_RUNNING_OR_INTERRUPTED,
            diagnosis.stage);
        assertTrue(diagnosis.goalLockClaimed);
        assertFalse(diagnosis.resultRecorded);
        assertNull(diagnosis.testReport);
        assertTrue(diagnosis.testSession != null);
        assertEquals(sessionId, diagnosis.testSession.sessionId);
        assertEquals("ACTIVE", diagnosis.testSession.state);
        assertEquals(
            "OPEN_AI_SESSION_RECOVERY",
            diagnosis.nextCheck);
        assertTrue(
            diagnosis.explanation.contains(
                "não está viva no processo atual"));

        LaboratoryAiTaskContractStore.Contract after =
            store.read(contract.contractId);
        assertTrue(after.claimed);
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
