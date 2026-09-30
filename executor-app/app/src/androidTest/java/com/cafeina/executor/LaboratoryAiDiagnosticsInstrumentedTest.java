package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiDiagnosticsInstrumentedTest {
    @Test
    public void diagnosticFindsFailureWithoutPersistingRawInput()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String sessionId = UUID.randomUUID().toString();
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), "");

        sessions.begin(sessionId, System.currentTimeMillis(),
            Arrays.asList("echo"), 4, 4096, 60_000L);

        String secret = "diagnostic-secret-must-not-be-stored";
        String inputSha = LaboratoryEngine.fingerprint(secret).substring(7, 71);
        sessions.append(sessionId, LaboratoryAiSessionStore.INVOKE_REQUEST,
            "ACTIVE", "echo", inputSha,
            secret.getBytes(StandardCharsets.UTF_8).length,
            "", "REQUESTED", 1,
            secret.getBytes(StandardCharsets.UTF_8).length);
        sessions.append(sessionId, LaboratoryAiSessionStore.INVOKE_RESULT,
            "ACTIVE", "echo", inputSha,
            secret.getBytes(StandardCharsets.UTF_8).length,
            "", "FAIL", 1,
            secret.getBytes(StandardCharsets.UTF_8).length);
        sessions.append(sessionId, LaboratoryAiSessionStore.FINISH,
            "FINISHED", "", "", 0, "",
            "HOST_COMPLETED", 1,
            secret.getBytes(StandardCharsets.UTF_8).length);

        LaboratoryAiDiagnosticStore.Report report =
            LaboratoryAiDiagnostics.analyzeNow(app, "", sessionId);

        assertEquals("FAILURE", report.severity);
        assertEquals(1, report.failedInvocations);
        assertTrue(report.recommendationCodes.contains(
            "INSPECT_TOOL_FAILURES"));

        File persisted = new File(app.getFilesDir(),
            "laboratory/legacy/ai-diagnostics/" + sessionId + ".json");
        String raw = new String(
            Files.readAllBytes(persisted.toPath()), StandardCharsets.UTF_8);
        assertFalse(raw.contains(secret));
        assertTrue(raw.contains(inputSha) == false);
    }

    @Test
    public void controllerAutomaticallyProducesDiagnosticForAnySession()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "diagauto"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "diag-auto-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app,
                project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    4,
                    4096,
                    30_000L));

        String sessionId = handles.host.sessionId();
        handles.host.complete();

        LaboratoryAiDiagnosticStore store =
            new LaboratoryAiDiagnosticStore(app.getFilesDir(), project);
        LaboratoryAiDiagnosticStore.Report report = null;
        for (int attempt = 0; attempt < 100 && report == null; attempt++) {
            try {
                report = store.read(sessionId);
            } catch (java.io.IOException notReady) {
                Thread.sleep(20L);
            }
        }

        assertNotNull("automatic session diagnostic was not persisted", report);
        assertEquals("HEALTHY", report.severity);
        assertEquals("FINISHED", report.state);
        assertEquals("HOST_COMPLETED", report.terminalReason);
    }

    @Test
    public void diagnosticMarksCleanSessionHealthy() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String sessionId = UUID.randomUUID().toString();
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), "");

        sessions.begin(sessionId, System.currentTimeMillis(),
            Arrays.asList("echo"), 4, 4096, 60_000L);
        sessions.append(sessionId, LaboratoryAiSessionStore.FINISH,
            "FINISHED", "", "", 0, "",
            "HOST_COMPLETED", 0, 0);

        LaboratoryAiDiagnosticStore.Report report =
            LaboratoryAiDiagnostics.analyzeNow(app, "", sessionId);

        assertEquals("HEALTHY", report.severity);
        assertEquals(Arrays.asList("NO_ACTION"),
            report.recommendationCodes);
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
