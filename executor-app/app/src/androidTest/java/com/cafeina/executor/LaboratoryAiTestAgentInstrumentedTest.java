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

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiTestAgentInstrumentedTest {
    @Test
    public void deterministicAgentPassesAndPersistsPrivacySafeEvidence()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "testagent"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "test-agent-echo";
        prepareGrantedStable(app, project, toolId);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiTestAgentReportsActivity.class), 0);
        assertFalse("Test-agent reports Activity must remain private", info.exported);

        String goal = "Validar deterministicamente a ferramenta sem expor dados privados.";
        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                goal,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    3,
                    512,
                    30_000L));

        String firstInput = "PRIVATE_AGENT_INPUT_ALPHA_991";
        String secondInput = "PRIVATE_AGENT_INPUT_BETA_773";
        LaboratoryAiTestAgent.Plan plan = new LaboratoryAiTestAgent.Plan(
            Arrays.asList(
                new LaboratoryAiTestAgent.Step(
                    "echo_alpha", toolId, firstInput, firstInput),
                new LaboratoryAiTestAgent.Step(
                    "echo_beta", toolId, secondInput, secondInput)),
            true);

        LaboratoryAiTestAgent.Report report =
            LaboratoryAiTestAgent.runBlocking(
                app, project, contract.contractId, plan);

        assertEquals("PASS", report.status);
        assertEquals("", report.terminalReason);
        assertEquals(2, report.plannedSteps);
        assertEquals(2, report.executedSteps);
        assertEquals(2, report.passed);
        assertEquals(0, report.failed);
        assertFalse(report.sessionId.isEmpty());

        LaboratoryAiTestAgentReportStore reports =
            new LaboratoryAiTestAgentReportStore(app.getFilesDir(), project);
        assertEquals(1, reports.list().size());
        String raw = reports.read(report.reportId);
        assertFalse(raw.contains(firstInput));
        assertFalse(raw.contains(secondInput));
        assertFalse(raw.contains(goal));
        assertTrue(raw.contains(
            LaboratoryEngine.fingerprint(firstInput).substring(7, 71)));
        assertTrue(raw.contains(
            LaboratoryEngine.fingerprint(secondInput).substring(7, 71)));

        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), project);
        LaboratoryAiSessionStore.Summary summary = sessions.list().stream()
            .filter(item -> report.sessionId.equals(item.sessionId))
            .findFirst().orElseThrow(() -> new AssertionError("session audit missing"));
        assertEquals("FINISHED", summary.state);
        assertTrue(sessions.readEvents(report.sessionId).stream().anyMatch(event ->
            LaboratoryAiSessionStore.FINISH.equals(event.type)
                && "HOST_COMPLETED".equals(event.outcome)));

        assertTrue(LaboratoryAiLiveSessionRegistry.list(project).isEmpty());

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(app.getFilesDir(), project);
        LaboratoryAiTeamRegistry.Member member =
            team.readMember("test-agent");
        assertEquals(LaboratoryAiTeamRegistry.ROLE_TESTER, member.role);
        LaboratoryAiTeamRegistry.Binding binding =
            team.readBinding(report.sessionId);
        assertEquals("test-agent", binding.agentId);
        assertEquals(contract.contractId, binding.contractId);

        Set<String> methods = new HashSet<>();
        for (Method method :
                LaboratoryAiTaskAdmission.AiTaskHandle.class.getDeclaredMethods()) {
            methods.add(method.getName());
        }
        assertFalse(methods.contains("complete"));
        assertFalse(methods.contains("pause"));
        assertFalse(methods.contains("cancel"));
    }

    @Test
    public void mismatchStopsPlanAndStillFinishesSessionNormally()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "agentfail"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "test-agent-mismatch";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Detectar mismatch determinístico.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    3,
                    512,
                    30_000L));

        String privateInput = "PRIVATE_AGENT_MISMATCH_INPUT_443";
        String privateExpected = "PRIVATE_EXPECTED_DIFFERENT_551";
        String skippedInput = "PRIVATE_AGENT_SHOULD_NOT_RUN_662";
        LaboratoryAiTestAgent.Report report =
            LaboratoryAiTestAgent.runBlocking(
                app,
                project,
                contract.contractId,
                new LaboratoryAiTestAgent.Plan(
                    Arrays.asList(
                        new LaboratoryAiTestAgent.Step(
                            "mismatch", toolId, privateInput, privateExpected),
                        new LaboratoryAiTestAgent.Step(
                            "must_skip", toolId, skippedInput, skippedInput)),
                    true));

        assertEquals("FAIL", report.status);
        assertEquals("STOP_ON_FAILURE", report.terminalReason);
        assertEquals(1, report.executedSteps);
        assertEquals(0, report.passed);
        assertEquals(1, report.failed);
        assertEquals("RETURN_MISMATCH", report.steps.get(0).reason);

        String raw = new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).read(report.reportId);
        assertFalse(raw.contains(privateInput));
        assertFalse(raw.contains(privateExpected));
        assertFalse(raw.contains(skippedInput));

        LaboratoryAiSessionStore.Summary summary =
            new LaboratoryAiSessionStore(app.getFilesDir(), project)
                .list().stream()
                .filter(item -> report.sessionId.equals(item.sessionId))
                .findFirst().orElseThrow(() -> new AssertionError("session missing"));
        assertEquals("FINISHED", summary.state);
    }

    @Test
    public void invalidPlanDoesNotConsumeGoalLock() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "agentbudget"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "test-agent-budget";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                "Não consumir contrato se o plano exceder orçamento.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    256,
                    30_000L));

        LaboratoryAiTestAgent.Plan invalid =
            new LaboratoryAiTestAgent.Plan(
                Arrays.asList(
                    new LaboratoryAiTestAgent.Step(
                        "one", toolId, "1", "1"),
                    new LaboratoryAiTestAgent.Step(
                        "two", toolId, "2", "2")),
                true);

        assertThrows(IllegalArgumentException.class, () ->
            LaboratoryAiTestAgent.runBlocking(
                app, project, contract.contractId, invalid));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    @Test
    public void admissionFailureIsReportedWithoutRawGoalOrInput()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "agentadmit"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "test-agent-revoked";
        prepareGrantedStable(app, project, toolId);

        String privateGoal = "PRIVATE_GOAL_AGENT_ADMISSION_884";
        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                privateGoal,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    128,
                    30_000L));

        new LaboratoryAiPermissionStore(app.getFilesDir(), project)
            .revoke(toolId);

        String privateInput = "PRIVATE_AGENT_ADMISSION_INPUT_885";
        LaboratoryAiTestAgent.Report report =
            LaboratoryAiTestAgent.runBlocking(
                app,
                project,
                contract.contractId,
                new LaboratoryAiTestAgent.Plan(
                    Collections.singletonList(
                        new LaboratoryAiTestAgent.Step(
                            "admission", toolId, privateInput, privateInput)),
                    true));

        assertEquals("ADMISSION_FAILED", report.status);
        assertEquals("SecurityException", report.terminalReason);
        assertEquals("", report.sessionId);
        assertEquals(0, report.executedSteps);
        assertEquals(0, report.failed);

        String raw = new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).read(report.reportId);
        assertFalse(raw.contains(privateGoal));
        assertFalse(raw.contains(privateInput));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertTrue(after.claimed);
        assertTrue(after.resultRecorded);
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
