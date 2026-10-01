package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
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
import java.util.concurrent.atomic.AtomicInteger;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiLlmTestPlannerInstrumentedTest {
    @Test
    public void validDraftPlansWithoutClaimingOrExecuting() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "llmplan"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "llm-planner-echo";
        prepareGrantedStable(app, project, toolId);

        String privateGoal = "PRIVATE_LLM_PLANNER_GOAL_2001";
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

        AtomicInteger calls = new AtomicInteger();
        LaboratoryAiLlmTestPlanner.Result result =
            LaboratoryAiLlmTestPlanner.plan(
                app,
                project,
                contract.contractId,
                request -> {
                    calls.incrementAndGet();
                    assertEquals(1, request.attempt);
                    assertEquals(
                        LaboratoryAiTestPlanContract.SCHEMA_VERSION,
                        request.schemaVersion);
                    assertEquals("LEARNING", request.mode);
                    assertEquals(privateGoal, request.goal);
                    assertEquals(2, request.maxInvocations);
                    assertEquals(512, request.maxTotalInputBytes);
                    assertEquals(30_000L, request.maxSessionMs);
                    assertEquals(1, request.tools.size());
                    assertEquals(toolId, request.tools.get(0).toolId);
                    assertTrue(request.memory.isEmpty());
                    assertTrue(request.previousIssues.isEmpty());
                    return validDraft(toolId, "hello");
                });

        assertTrue(result.accepted);
        assertEquals(1, result.attempts);
        assertNotNull(result.plan);
        assertEquals(1, result.plan.steps.size());
        assertEquals(toolId, result.plan.steps.get(0).toolId);
        assertEquals(1, calls.get());

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    @Test
    public void invalidFirstDraftGetsSafeRepairFeedback() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "llmrepair"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "llm-repair-echo";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                "Planejar um teste sem executar durante o planejamento.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    128,
                    30_000L));

        AtomicInteger calls = new AtomicInteger();
        LaboratoryAiLlmTestPlanner.Result result =
            LaboratoryAiLlmTestPlanner.plan(
                app,
                project,
                contract.contractId,
                request -> {
                    int call = calls.incrementAndGet();
                    if (call == 1) {
                        JSONObject badStep = new JSONObject();
                        badStep.put("name", "bad");
                        badStep.put("toolId", "forbidden-planner-tool");
                        badStep.put("input", "PRIVATE_REJECTED_DRAFT_2002");
                        badStep.put(
                            "expectedFirstReturn",
                            "PRIVATE_REJECTED_DRAFT_2002");
                        JSONObject bad = new JSONObject();
                        bad.put(
                            "schemaVersion",
                            LaboratoryAiTestPlanContract.SCHEMA_VERSION);
                        bad.put("stopOnFailure", true);
                        bad.put("steps", new JSONArray().put(badStep));
                        return bad.toString();
                    }

                    assertEquals(2, request.attempt);
                    assertTrue(hasIssue(
                        request,
                        LaboratoryAiTestPlanContract.STEP_TOOL_NOT_ALLOWED,
                        0,
                        "toolId"));
                    return validDraft(toolId, "repaired");
                });

        assertTrue(result.accepted);
        assertEquals(2, result.attempts);
        assertEquals(2, calls.get());
        assertEquals(toolId, result.plan.steps.get(0).toolId);

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    @Test
    public void rejectedDraftsNeverConsumeGoalLock() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "llmreject"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "llm-reject-echo";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Rejeitar plano fora do Goal Lock.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    128,
                    30_000L));

        AtomicInteger calls = new AtomicInteger();
        LaboratoryAiLlmTestPlanner.Result result =
            LaboratoryAiLlmTestPlanner.plan(
                app,
                project,
                contract.contractId,
                request -> {
                    calls.incrementAndGet();
                    JSONObject badStep = new JSONObject();
                    badStep.put("name", "bad");
                    badStep.put("toolId", "never-allowed");
                    badStep.put("input", "x");
                    badStep.put("expectedFirstReturn", "x");
                    JSONObject bad = new JSONObject();
                    bad.put(
                        "schemaVersion",
                        LaboratoryAiTestPlanContract.SCHEMA_VERSION);
                    bad.put("stopOnFailure", true);
                    bad.put("steps", new JSONArray().put(badStep));
                    return bad.toString();
                });

        assertFalse(result.accepted);
        assertEquals(
            LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS,
            result.attempts);
        assertEquals(
            LaboratoryAiLlmTestPlanner.MAX_ATTEMPTS,
            calls.get());
        assertEquals(null, result.plan);
        assertTrue(hasIssue(
            result.issues,
            LaboratoryAiTestPlanContract.STEP_TOOL_NOT_ALLOWED));

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    private static String validDraft(String toolId, String value)
            throws Exception {
        JSONObject step = new JSONObject();
        step.put("name", "echo");
        step.put("toolId", toolId);
        step.put("input", value);
        step.put("expectedFirstReturn", value);

        JSONObject root = new JSONObject();
        root.put(
            "schemaVersion",
            LaboratoryAiTestPlanContract.SCHEMA_VERSION);
        root.put("stopOnFailure", true);
        root.put("steps", new JSONArray().put(step));
        return root.toString();
    }

    private static boolean hasIssue(
            LaboratoryAiLlmTestPlanner.Request request,
            String code,
            int stepIndex,
            String field) {
        for (LaboratoryAiLlmTestPlanner.IssueHint issue :
                request.previousIssues) {
            if (code.equals(issue.code)
                    && stepIndex == issue.stepIndex
                    && field.equals(issue.field)) {
                return true;
            }
        }
        return false;
    }

    private static boolean hasIssue(
            java.util.List<LaboratoryAiTestPlanContract.Issue> issues,
            String code) {
        for (LaboratoryAiTestPlanContract.Issue issue : issues) {
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
