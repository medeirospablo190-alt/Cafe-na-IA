package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertThrows;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiValidatedPlanExecutionGateInstrumentedTest {
    @Test
    public void preparePersistsScenarioWithoutConsumingGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "planprep" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "plan-gate-echo";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            createContract(app, project, toolId, "Preparar sem executar.");
        LaboratoryAiTestAgent.Plan plan =
            oneStepPlan(toolId, "hello");

        LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
            LaboratoryAiValidatedPlanExecutionGate.prepare(
                app,
                project,
                contract.contractId,
                plan);

        assertEquals(contract.contractId, prepared.contractId);
        assertEquals(contract.contractSha256, prepared.contractSha256);
        assertEquals(contract.goalSha256, prepared.goalSha256);
        assertEquals(1, prepared.stepCount);

        LaboratoryAiTestScenarioStore.Scenario scenario =
            new LaboratoryAiTestScenarioStore(
                app.getFilesDir(), project)
                .read(prepared.scenarioId);
        assertEquals(prepared.scenarioSha256, scenario.scenarioSha256);
        assertEquals(toolId, scenario.plan.steps.get(0).toolId);

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    @Test
    public void invalidPlanCannotBePreparedOrConsumeGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "planreject" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "plan-allowed-echo";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            createContract(app, project, toolId, "Rejeitar plano fora do lock.");
        LaboratoryAiTestAgent.Plan invalid =
            oneStepPlan("not-allowed-tool", "blocked");

        assertThrows(
            LaboratoryAiTestPlanContract.RejectedPlanException.class,
            () -> LaboratoryAiValidatedPlanExecutionGate.prepare(
                app,
                project,
                contract.contractId,
                invalid));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestScenarioStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    @Test
    public void executionRequiresPreparedScenarioAndConsumesGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "planexec" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "plan-exec-echo";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            createContract(app, project, toolId, "Executar após gate.");
        LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
            LaboratoryAiValidatedPlanExecutionGate.prepare(
                app,
                project,
                contract.contractId,
                oneStepPlan(toolId, "verified"));

        LaboratoryAiValidatedPlanExecutionGate.Execution execution =
            LaboratoryAiValidatedPlanExecutionGate.executePrepared(
                app,
                project,
                prepared);

        assertEquals(contract.contractId, execution.contractId);
        assertEquals(prepared.scenarioId, execution.scenarioId);
        assertEquals(prepared.scenarioSha256, execution.scenarioSha256);
        assertEquals("PASS", execution.status);
        assertNotNull(execution.reportId);
        assertFalse(execution.reportId.isEmpty());
        assertNotNull(execution.sessionId);
        assertFalse(execution.sessionId.isEmpty());

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertTrue(after.claimed);
        assertTrue(after.resultRecorded);

        LaboratoryAiTaskContractStore.Result admission =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .readResult(contract.contractId);
        assertEquals("SESSION_CREATED", admission.status);
        assertEquals(execution.sessionId, admission.sessionId);
    }

    private static LaboratoryAiTaskContractStore.Contract createContract(
            Context app,
            String project,
            String toolId,
            String goal) throws Exception {
        return LaboratoryAiTaskAdmission.createContract(
            app,
            project,
            LaboratoryAiTaskContractStore.Mode.LEARNING,
            goal,
            new LaboratoryAiSessionController.Policy(
                Collections.singletonList(toolId),
                1,
                128,
                30_000L));
    }

    private static LaboratoryAiTestAgent.Plan oneStepPlan(
            String toolId,
            String value) {
        return new LaboratoryAiTestAgent.Plan(
            Collections.singletonList(
                new LaboratoryAiTestAgent.Step(
                    "echo",
                    toolId,
                    value,
                    value)),
            true);
    }

    private static void prepareGrantedStable(
            Context app,
            String project,
            String toolId) throws Exception {
        String version = "1.0.0";
        String source = "return tool_input";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratoryToolRegistry.Descriptor descriptor =
            new LaboratoryToolRegistry.Descriptor(
                toolId,
                version,
                LaboratoryEngine.fingerprint(source).substring(7, 71),
                "AI_TOOL_WORKSHOP",
                Arrays.asList(
                    LaboratoryStableToolExecutor.REQUIRED_CAPABILITY,
                    "diagnostics"),
                Collections.singletonList("artifact"),
                "cafeina-lab-api-1",
                1000,
                4096);
        registry.registerExperimental(descriptor);

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            toolId, source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(app.getFilesDir(), project)
            .bindLuauSource(toolId, version, snapshot.id);

        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "artifact",
                source,
                LaboratoryEngine.fingerprint(source))));
        LaboratoryEngine.Report evidence =
            LaboratoryRunner.runApprovedBuiltIn(
                app.getFilesDir(),
                project,
                request,
                new LaboratoryEngine.Cancellation());
        registry.qualifyCandidate(
            toolId,
            version,
            Collections.singletonList(evidence.runId));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(
                app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId,
                version,
                System.currentTimeMillis());
        approvals.applyApprovedTransition(approval.receiptId);

        new LaboratoryAiPermissionStore(
            app.getFilesDir(), project)
            .grantAfterDeviceCredential(
                toolId,
                System.currentTimeMillis());

        assertNotNull(registry.activeStable(toolId));
    }
}
