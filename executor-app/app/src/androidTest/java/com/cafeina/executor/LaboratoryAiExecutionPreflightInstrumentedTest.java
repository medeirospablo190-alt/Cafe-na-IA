package com.cafeina.executor;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

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
public final class LaboratoryAiExecutionPreflightInstrumentedTest {
    @Test
    public void readyScenarioPassesWithoutClaimingGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "preflight" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "preflight.tool";
        prepareGrantedStable(
            app,
            project,
            toolId,
            4096);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Validar execução antes de consumir Goal Lock.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    1024,
                    30_000L));

        LaboratoryAiTestAgent.Plan plan =
            new LaboratoryAiTestAgent.Plan(
                Collections.singletonList(
                    new LaboratoryAiTestAgent.Step(
                        "check",
                        toolId,
                        "input",
                        "input")),
                true);

        LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
            LaboratoryAiValidatedPlanExecutionGate.prepare(
                app,
                project,
                contract.contractId,
                plan);

        LaboratoryAiExecutionPreflight.Result result =
            LaboratoryAiExecutionPreflight.inspect(
                app,
                project,
                contract.contractId,
                prepared.scenarioId);

        assertTrue(result.ready);
        assertTrue(hasCode(
            result,
            "CONTRACT_SCENARIO_INTEGRITY"));
        assertTrue(hasCode(
            result,
            "ALLOWLIST_AVAILABLE"));
        assertTrue(hasCode(
            result,
            "STABLE_USE_AUDIT_CAPACITY_OK"));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void revokedPermissionBlocksWithoutClaimingGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "preflightrev"
                + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "preflight.revoked";
        prepareGrantedStable(
            app,
            project,
            toolId,
            4096);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Não executar se a permissão mudar.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    1024,
                    30_000L));

        LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
            LaboratoryAiValidatedPlanExecutionGate.prepare(
                app,
                project,
                contract.contractId,
                new LaboratoryAiTestAgent.Plan(
                    Collections.singletonList(
                        new LaboratoryAiTestAgent.Step(
                            "check",
                            toolId,
                            "input",
                            "input")),
                    true));

        new LaboratoryAiPermissionStore(
            app.getFilesDir(), project)
            .revoke(toolId);

        LaboratoryAiExecutionPreflight.Result result =
            LaboratoryAiExecutionPreflight.inspect(
                app,
                project,
                contract.contractId,
                prepared.scenarioId);

        assertFalse(result.ready);
        assertTrue(hasBlockCode(
            result,
            "ALLOWLIST_TOOL_NOT_AVAILABLE"));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void perToolInputLimitBlocksBeforeExecution()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "preflightinput"
                + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "preflight.input";
        prepareGrantedStable(
            app,
            project,
            toolId,
            4);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Respeitar o limite específico da ferramenta.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    1024,
                    30_000L));

        LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
            LaboratoryAiValidatedPlanExecutionGate.prepare(
                app,
                project,
                contract.contractId,
                new LaboratoryAiTestAgent.Plan(
                    Collections.singletonList(
                        new LaboratoryAiTestAgent.Step(
                            "check",
                            toolId,
                            "12345",
                            "12345")),
                    true));

        LaboratoryAiExecutionPreflight.Result result =
            LaboratoryAiExecutionPreflight.inspect(
                app,
                project,
                contract.contractId,
                prepared.scenarioId);

        assertFalse(result.ready);
        assertTrue(hasBlockCode(
            result,
            "STEP_TOOL_INPUT_LIMIT_EXCEEDED"));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertFalse(after.claimed);
    }

    private static boolean hasCode(
            LaboratoryAiExecutionPreflight.Result result,
            String code) {
        for (LaboratoryAiExecutionPreflight.Check check : result.checks) {
            if (code.equals(check.code)) return true;
        }
        return false;
    }

    private static boolean hasBlockCode(
            LaboratoryAiExecutionPreflight.Result result,
            String code) {
        for (LaboratoryAiExecutionPreflight.Check check : result.checks) {
            if (code.equals(check.code)
                    && check.level
                        == LaboratoryAiExecutionPreflight.Level.BLOCK) {
                return true;
            }
        }
        return false;
    }

    private static void prepareGrantedStable(
            Context app,
            String project,
            String toolId,
            int maxInputBytes) throws Exception {
        String version = "1.0.0";
        String source = "return tool_input";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(
                app.getFilesDir(), project);
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
                maxInputBytes);
        registry.registerExperimental(descriptor);

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(
                app.getFilesDir(), project);
        LaboratorySnapshotStore.Snapshot snapshot =
            snapshots.create(
                toolId,
                source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(
            app.getFilesDir(), project)
            .bindLuauSource(
                toolId,
                version,
                snapshot.id);

        LaboratoryEngine.Request request =
            new LaboratoryEngine.Request(
                LaboratoryEngine.FINGERPRINT_TOOL,
                LaboratoryEngine.FINGERPRINT_VERSION,
                20260930L,
                1000,
                Collections.singletonList(
                    new LaboratoryEngine.TestCase(
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
        approvals.applyApprovedTransition(
            approval.receiptId);

        new LaboratoryAiPermissionStore(
            app.getFilesDir(), project)
            .grantAfterDeviceCredential(
                toolId,
                System.currentTimeMillis());
    }
}
