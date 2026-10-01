package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiTestPlanContractInstrumentedTest {
    @Test
    public void validPlannerDraftRunsAndBecomesSanitizedMinimalMemory()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "planmemory"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "planner-echo";
        prepareGrantedStable(app, project, toolId);

        String privateGoal = "PRIVATE_PLAN_GOAL_1001";
        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                privateGoal,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    512,
                    30_000L));

        String privateInput = "PRIVATE_PLANNER_INPUT_1002";
        JSONObject step = new JSONObject();
        step.put("name", "echo_case");
        step.put("toolId", toolId);
        step.put("input", privateInput);
        step.put("expectedFirstReturn", privateInput);

        JSONObject draft = new JSONObject();
        draft.put(
            "schemaVersion",
            LaboratoryAiTestPlanContract.SCHEMA_VERSION);
        draft.put("stopOnFailure", true);
        draft.put("steps", new JSONArray().put(step));

        LaboratoryAiTestPlanContract.Validation validation =
            LaboratoryAiTestPlanContract.validateDraft(
                contract, draft.toString());

        assertTrue(validation.accepted);
        assertTrue(validation.issues.isEmpty());
        assertNotNull(validation.plan);
        assertEquals(1, validation.plan.steps.size());

        LaboratoryAiTestAgent.Report report =
            LaboratoryAiTestAgent.runBlocking(
                app,
                project,
                contract.contractId,
                validation.plan);
        assertEquals("PASS", report.status);

        LaboratoryAiTestMemory memory =
            new LaboratoryAiTestMemory(app.getFilesDir(), project);
        assertEquals(1, memory.recent(10).size());
        assertEquals(1, memory.forGoal(contract.goalSha256, 10).size());
        assertEquals(1, memory.forTool(toolId, 10).size());

        LaboratoryAiTestMemory.Record remembered =
            memory.recent(10).get(0);
        assertEquals(report.reportId, remembered.reportId);
        assertEquals(contract.goalSha256, remembered.goalSha256);
        assertEquals("PASS", remembered.status);
        assertEquals(1, remembered.steps.size());
        assertEquals(toolId, remembered.steps.get(0).toolId);
        assertEquals("MATCH", remembered.steps.get(0).reason);
        assertEquals(64, remembered.steps.get(0).inputSha256.length());

        String rawReport = new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).read(report.reportId);
        assertFalse(rawReport.contains(privateGoal));
        assertFalse(rawReport.contains(privateInput));
    }

    @Test
    public void rejectedPlanReturnsStructuredIssuesBeforeGoalLockClaim()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "planreject"
            + UUID.randomUUID().toString().substring(0, 8);
        String allowedTool = "planner-allowed";
        prepareGrantedStable(app, project, allowedTool);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                "Validar plano antes de consumir Goal Lock.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(allowedTool),
                    1,
                    8,
                    30_000L));

        JSONObject first = new JSONObject();
        first.put("name", "same");
        first.put("toolId", "planner-forbidden");
        first.put("input", "123456789");
        first.put("expectedFirstReturn", "x");
        first.put("unexpected", "PRIVATE_UNKNOWN_FIELD_VALUE");

        JSONObject second = new JSONObject();
        second.put("name", "same");
        second.put("toolId", allowedTool);
        second.put("input", "z");
        second.put("expectedFirstReturn", "z");

        JSONObject draft = new JSONObject();
        draft.put(
            "schemaVersion",
            LaboratoryAiTestPlanContract.SCHEMA_VERSION);
        draft.put("stopOnFailure", true);
        draft.put("steps", new JSONArray().put(first).put(second));

        LaboratoryAiTestPlanContract.Validation validation =
            LaboratoryAiTestPlanContract.validateDraft(
                contract, draft.toString());

        assertFalse(validation.accepted);
        assertTrue(validation.hasCode(
            LaboratoryAiTestPlanContract.UNKNOWN_FIELD));
        assertTrue(validation.hasCode(
            LaboratoryAiTestPlanContract.PLAN_INVOCATION_BUDGET_EXCEEDED));
        assertTrue(validation.hasCode(
            LaboratoryAiTestPlanContract.STEP_TOOL_NOT_ALLOWED));
        assertTrue(validation.hasCode(
            LaboratoryAiTestPlanContract.STEP_NAME_DUPLICATE));
        assertTrue(validation.hasCode(
            LaboratoryAiTestPlanContract.PLAN_INPUT_BUDGET_EXCEEDED));
        assertEquals(null, validation.plan);

        LaboratoryAiTestAgent.Plan executableButForbidden =
            new LaboratoryAiTestAgent.Plan(
                Collections.singletonList(
                    new LaboratoryAiTestAgent.Step(
                        "forbidden",
                        "planner-forbidden",
                        "x",
                        "x")),
                true);

        LaboratoryAiTestPlanContract.RejectedPlanException rejected =
            assertThrows(
                LaboratoryAiTestPlanContract.RejectedPlanException.class,
                () -> LaboratoryAiTestAgent.runBlocking(
                    app,
                    project,
                    contract.contractId,
                    executableButForbidden));
        assertTrue(hasIssue(
            rejected,
            LaboratoryAiTestPlanContract.STEP_TOOL_NOT_ALLOWED));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    private static boolean hasIssue(
            LaboratoryAiTestPlanContract.RejectedPlanException rejected,
            String code) {
        for (LaboratoryAiTestPlanContract.Issue issue : rejected.issues) {
            if (code.equals(issue.code)) return true;
        }
        return false;
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
        LaboratoryEngine.Report evidence =
            LaboratoryRunner.runApprovedBuiltIn(
                app.getFilesDir(),
                project,
                request,
                new LaboratoryEngine.Cancellation());
        registry.qualifyCandidate(
            toolId, version, Collections.singletonList(evidence.runId));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId,
                version,
                System.currentTimeMillis());
        approvals.applyApprovedTransition(approval.receiptId);

        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(app.getFilesDir(), project);
        permissions.grantAfterDeviceCredential(
            toolId, System.currentTimeMillis());

        assertNotNull(registry.activeStable(toolId));
    }
}
