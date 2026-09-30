package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ActivityInfo;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiTestScenarioInstrumentedTest {
    @Test
    public void immutableScenarioRunsThroughGoalLockedTestAgent()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "scenario"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "scenario-echo";
        prepareGrantedStable(app, project, toolId);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiTestScenariosActivity.class), 0);
        assertFalse("Test scenario Activity must remain private", info.exported);

        String privateInput = "PRIVATE_SCENARIO_INPUT_921";
        LaboratoryAiTestAgent.Plan plan = new LaboratoryAiTestAgent.Plan(
            Collections.singletonList(
                new LaboratoryAiTestAgent.Step(
                    "echo_case", toolId, privateInput, privateInput)),
            true);

        LaboratoryAiTestScenarioStore store =
            new LaboratoryAiTestScenarioStore(app.getFilesDir(), project);
        LaboratoryAiTestScenarioStore.Scenario scenario =
            store.create("Echo privado", plan);

        assertEquals("Echo privado", scenario.name);
        assertEquals(1, scenario.stepCount);
        assertEquals(privateInput, scenario.plan.steps.get(0).input);
        assertEquals(64, scenario.scenarioSha256.length());
        assertEquals(1, store.list().size());

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Executar cenário imutável no agente de teste.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    256,
                    30_000L));

        LaboratoryAiTestScenarioRunner.Result result =
            LaboratoryAiTestScenarioRunner.runBlocking(
                app, project, scenario.scenarioId, contract.contractId);

        assertEquals(scenario.scenarioId, result.scenarioId);
        assertEquals(scenario.scenarioSha256, result.scenarioSha256);
        assertEquals("PASS", result.status);
        assertFalse(result.reportId.isEmpty());
        assertFalse(result.sessionId.isEmpty());

        String reportRaw = new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).read(result.reportId);
        assertFalse(reportRaw.contains(privateInput));

        Path scenarioPath = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/ai-test-scenarios/"
                + scenario.scenarioId + ".json");
        String scenarioRaw = new String(
            Files.readAllBytes(scenarioPath), StandardCharsets.UTF_8);
        assertTrue(scenarioRaw.contains(privateInput));
    }

    @Test
    public void tamperedScenarioIsRejectedBeforeGoalLockClaim()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "scenariotamper"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "scenario-tamper-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTestScenarioStore store =
            new LaboratoryAiTestScenarioStore(app.getFilesDir(), project);
        LaboratoryAiTestScenarioStore.Scenario scenario =
            store.create(
                "Cenário protegido",
                new LaboratoryAiTestAgent.Plan(
                    Collections.singletonList(
                        new LaboratoryAiTestAgent.Step(
                            "protected", toolId, "original", "original")),
                    true));

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Não consumir contrato se o cenário estiver adulterado.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    256,
                    30_000L));

        Path scenarioPath = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/ai-test-scenarios/"
                + scenario.scenarioId + ".json");
        String raw = new String(
            Files.readAllBytes(scenarioPath), StandardCharsets.UTF_8);
        raw = raw.replace("original", "tampered");
        Files.write(scenarioPath, raw.getBytes(StandardCharsets.UTF_8));

        assertThrows(java.io.IOException.class, () ->
            LaboratoryAiTestScenarioRunner.runBlocking(
                app, project, scenario.scenarioId, contract.contractId));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void incompatibleScenarioDoesNotConsumeGoalLock() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "scenariobudget"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "scenario-budget-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTestScenarioStore.Scenario scenario =
            new LaboratoryAiTestScenarioStore(app.getFilesDir(), project)
                .create(
                    "Duas chamadas",
                    new LaboratoryAiTestAgent.Plan(
                        Arrays.asList(
                            new LaboratoryAiTestAgent.Step(
                                "first", toolId, "one", "one"),
                            new LaboratoryAiTestAgent.Step(
                                "second", toolId, "two", "two")),
                        true));

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Contrato menor que o cenário.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    256,
                    30_000L));

        assertThrows(IllegalArgumentException.class, () ->
            LaboratoryAiTestScenarioRunner.runBlocking(
                app, project, scenario.scenarioId, contract.contractId));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
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
                "artifact", source, LaboratoryEngine.fingerprint(source))));
        LaboratoryEngine.Report evidence = LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), project, request,
            new LaboratoryEngine.Cancellation());
        registry.qualifyCandidate(
            toolId, version, Collections.singletonList(evidence.runId));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId, version, System.currentTimeMillis());
        approvals.applyApprovedTransition(approval.receiptId);

        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(app.getFilesDir(), project);
        permissions.grantAfterDeviceCredential(
            toolId, System.currentTimeMillis());

        assertNotNull(registry.activeStable(toolId));
    }
}
