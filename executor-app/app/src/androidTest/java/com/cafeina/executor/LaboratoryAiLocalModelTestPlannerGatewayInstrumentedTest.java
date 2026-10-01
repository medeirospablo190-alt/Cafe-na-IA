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

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiLocalModelTestPlannerGatewayInstrumentedTest {
    @Test
    public void backendReceivesPlanningProtocolAndCannotConsumeGoalLock()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "localgw"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "local-gateway-echo";
        prepareGrantedStable(app, project, toolId);

        String goal = "Planejar teste local sem executar durante inferencia.";
        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                goal,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    512,
                    30_000L));

        AtomicInteger calls = new AtomicInteger();
        LaboratoryAiLocalModelBackend backend = generation -> {
            calls.incrementAndGet();
            assertEquals(
                LaboratoryAiTestPlanContract.MAX_DRAFT_CHARS,
                generation.maxOutputChars);
            assertEquals(
                LaboratoryAiLocalModelTestPlannerGateway.DEFAULT_TEMPERATURE,
                generation.temperature,
                0.0f);
            assertEquals(
                LaboratoryAiLocalModelTestPlannerGateway.DEFAULT_SEED,
                generation.seed);

            JSONObject prompt = parsePrompt(generation.prompt);
            assertEquals(
                LaboratoryAiLlmTestPromptCodec.PROTOCOL,
                prompt.getString("protocol"));
            assertEquals(
                LaboratoryAiLlmTestPromptCodec.PROTOCOL_VERSION,
                prompt.getInt("protocolVersion"));

            JSONObject rules = prompt.getJSONObject("rules");
            assertEquals("planning_only", rules.getString("role"));
            assertFalse(rules.getBoolean("mayExecuteTools"));
            assertFalse(rules.getBoolean("mayChangePermissions"));
            assertFalse(rules.getBoolean("mayChangeGoalLock"));
            assertTrue(rules.getBoolean("useOnlyListedToolIds"));

            JSONObject task = prompt.getJSONObject("task");
            assertEquals(goal, task.getString("goal"));
            assertEquals("LEARNING", task.getString("mode"));
            assertEquals(2, task.getInt("maxInvocations"));

            JSONArray tools = prompt.getJSONArray("tools");
            assertEquals(1, tools.length());
            assertEquals(
                toolId,
                tools.getJSONObject(0).getString("toolId"));

            assertEquals(
                0,
                prompt.getJSONArray("previousValidationIssues").length());
            assertEquals(
                0,
                prompt.getJSONArray("sanitizedMemory").length());

            return validDraft(toolId, "hello");
        };

        LaboratoryAiLlmTestPlanner.Result result =
            LaboratoryAiLlmTestPlanner.plan(
                app,
                project,
                contract.contractId,
                new LaboratoryAiLocalModelTestPlannerGateway(backend));

        assertTrue(result.accepted);
        assertEquals(1, result.attempts);
        assertEquals(1, calls.get());
        assertEquals(toolId, result.plan.steps.get(0).toolId);

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
        assertTrue(new LaboratoryAiTestAgentReportStore(
            app.getFilesDir(), project).list().isEmpty());
    }

    @Test
    public void invalidBackendTextIsRepairedThroughValidationFeedback()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project = "localrepair"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "local-repair-echo";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                "Produzir um plano JSON valido.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    128,
                    30_000L));

        AtomicInteger calls = new AtomicInteger();
        LaboratoryAiLocalModelBackend backend = generation -> {
            int call = calls.incrementAndGet();
            JSONObject prompt = parsePrompt(generation.prompt);
            if (call == 1) {
                assertEquals(
                    0,
                    prompt.getJSONArray(
                        "previousValidationIssues").length());
                return "not-json-planner-output";
            }

            JSONArray issues = prompt.getJSONArray(
                "previousValidationIssues");
            assertTrue(containsIssue(
                issues,
                LaboratoryAiTestPlanContract.PLAN_JSON_INVALID));
            return validDraft(toolId, "fixed");
        };

        LaboratoryAiLlmTestPlanner.Result result =
            LaboratoryAiLlmTestPlanner.plan(
                app,
                project,
                contract.contractId,
                new LaboratoryAiLocalModelTestPlannerGateway(backend));

        assertTrue(result.accepted);
        assertEquals(2, result.attempts);
        assertEquals(2, calls.get());

        LaboratoryAiTaskContractStore.Contract after =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project).read(contract.contractId);
        assertFalse(after.claimed);
        assertFalse(after.resultRecorded);
    }

    private static JSONObject parsePrompt(String raw) throws IOException {
        try {
            return new JSONObject(raw);
        } catch (Exception error) {
            throw new IOException("invalid test planner prompt", error);
        }
    }

    private static boolean containsIssue(JSONArray issues, String code)
            throws IOException {
        try {
            for (int i = 0; i < issues.length(); i++) {
                if (code.equals(
                        issues.getJSONObject(i).getString("code"))) {
                    return true;
                }
            }
            return false;
        } catch (Exception error) {
            throw new IOException("invalid validation issue prompt", error);
        }
    }

    private static String validDraft(String toolId, String value)
            throws IOException {
        try {
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
        } catch (Exception error) {
            throw new IOException("could not encode planner draft", error);
        }
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
