package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiActionPreflightInstrumentedTest {
    @Test
    public void missingModelBlocksWithoutConsumingGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "preflightnomodel"
                + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "preflight-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Validar pré-diagnóstico sem modelo selecionado.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    1024,
                    30_000L));

        LaboratoryAiActionPreflight.Report report =
            LaboratoryAiActionPreflight.inspect(
                app,
                project,
                contract.contractId,
                "");

        assertEquals(
            LaboratoryAiActionPreflight.Status.BLOCKED,
            report.status);
        assertFalse(report.canPlan);
        assertTrue(report.checks.stream().anyMatch(check ->
            "LOCAL_MODEL_NOT_SELECTED".equals(check.code)
                && check.status
                    == LaboratoryAiActionPreflight.Status.BLOCKED));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void revokedToolBlocksBeforeModelExecution()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "preflighttool"
                + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "preflight-revoked";
        prepareGrantedStable(app, project, toolId);
        String modelName = prepareMinimalGguf(app, project);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Detectar mudança de permissão antes do planejamento.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    1024,
                    30_000L));

        new LaboratoryAiPermissionStore(
            app.getFilesDir(), project)
            .revoke(toolId);

        LaboratoryAiActionPreflight.Report report =
            LaboratoryAiActionPreflight.inspect(
                app,
                project,
                contract.contractId,
                modelName);

        assertEquals(
            LaboratoryAiActionPreflight.Status.BLOCKED,
            report.status);
        assertFalse(report.canPlan);
        assertTrue(report.checks.stream().anyMatch(check ->
            "TASK_TOOL_PERMISSION_CHANGED".equals(check.code)));
    }

    @Test
    public void readyDependenciesPermitPlanningAttempt()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "preflightready"
                + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "preflight-ready";
        prepareGrantedStable(app, project, toolId);
        String modelName = prepareMinimalGguf(app, project);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Confirmar dependências essenciais antes de planejar.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    1024,
                    30_000L));

        LaboratoryAiActionPreflight.Report report =
            LaboratoryAiActionPreflight.inspect(
                app,
                project,
                contract.contractId,
                modelName);

        assertTrue(report.checks.stream().anyMatch(check ->
            "GOAL_LOCK_UNUSED".equals(check.code)));
        assertTrue(report.checks.stream().anyMatch(check ->
            "TASK_TOOLS_READY".equals(check.code)));
        assertTrue(report.checks.stream().anyMatch(check ->
            "LOCAL_MODEL_ADMITTED".equals(check.code)));

        if (LaboratoryAiLlamaCppBackend.isRuntimePackaged()) {
            assertTrue(report.canPlan);
            assertTrue(
                report.status == LaboratoryAiActionPreflight.Status.READY
                    || report.status
                        == LaboratoryAiActionPreflight.Status.ATTENTION);
        } else {
            assertFalse(report.canPlan);
            assertEquals(
                LaboratoryAiActionPreflight.Status.BLOCKED,
                report.status);
            assertTrue(report.checks.stream().anyMatch(check ->
                "LOCAL_MODEL_DEVICE_PREFLIGHT".equals(check.code)
                    && check.status
                        == LaboratoryAiActionPreflight.Status.BLOCKED
                    && check.detail.contains(
                        LaboratoryAiLocalModelPreflight
                            .RUNTIME_NOT_PACKAGED)));
        }
    }

    private static String prepareMinimalGguf(
            Context app,
            String project) throws Exception {
        java.io.File models =
            LaboratoryAiLocalModelAdmission.modelDirectory(
                app.getFilesDir());
        Files.createDirectories(models.toPath());
        String name =
            "preflight-" + project + ".gguf";
        Files.write(
            models.toPath().resolve(name),
            new byte[] {0x47, 0x47, 0x55, 0x46});
        return name;
    }

    private static void prepareGrantedStable(
            Context app, String project, String toolId) throws Exception {
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
            new LaboratorySnapshotStore(
                app.getFilesDir(), project);
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            toolId,
            source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(
            app.getFilesDir(), project)
            .bindLuauSource(toolId, version, snapshot.id);

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
        approvals.applyApprovedTransition(approval.receiptId);

        new LaboratoryAiPermissionStore(
            app.getFilesDir(), project)
            .grantAfterDeviceCredential(
                toolId,
                System.currentTimeMillis());
    }
}
