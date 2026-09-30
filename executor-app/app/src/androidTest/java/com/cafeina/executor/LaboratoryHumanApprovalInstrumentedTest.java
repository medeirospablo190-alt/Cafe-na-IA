package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
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
public final class LaboratoryHumanApprovalInstrumentedTest {
    @Test
    public void authenticatedReceiptDoesNotActivateUntilSecondExplicitAction()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "human" + UUID.randomUUID().toString().substring(0, 8);
        String source = "return tool_input";
        String toolId = "human-approved-tool";
        String version = "1.0.0";

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryApprovalActivity.class), 0);
        assertFalse("Human approval Activity must remain private", info.exported);

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(app.getFilesDir(), project);

        LaboratoryToolRegistry.Descriptor descriptor =
            descriptor(toolId, version, source);
        registry.registerExperimental(descriptor);
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            toolId, source.getBytes(StandardCharsets.UTF_8));
        artifacts.bindLuauSource(toolId, version, snapshot.id);

        LaboratoryEngine.Report evidence = evidence(app, project, source);
        registry.qualifyCandidate(
            toolId, version, Collections.singletonList(evidence.runId));
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(toolId, version));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Preview preview =
            approvals.previewActivation(toolId, version);
        assertEquals(LaboratoryHumanApprovalStore.ACTIVATE_STABLE, preview.action);
        assertEquals("", preview.fromVersion);
        assertEquals(version, preview.toVersion);
        assertEquals(descriptor.artifactSha256, preview.artifactSha256);
        assertEquals(snapshot.id, preview.snapshotId);
        assertEquals(Collections.singletonList(evidence.runId),
            preview.evidenceRunIds);
        assertTrue(preview.regressionComparisonIds.isEmpty());

        assertThrows(java.io.IOException.class, () ->
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId, version, System.currentTimeMillis() - 120_000L));

        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId, version, System.currentTimeMillis());

        assertFalse(approval.consumed);
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(toolId, version));
        assertNull(registry.activeStable(toolId));
        assertEquals(64, approval.receiptSha256.length());

        assertThrows(java.io.IOException.class, () ->
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId, version, System.currentTimeMillis()));

        approvals.applyApprovedTransition(approval.receiptId);

        assertEquals(version, registry.activeStable(toolId).version);
        assertEquals(LaboratoryToolRegistry.Stage.STABLE,
            registry.stage(toolId, version));
        LaboratoryHumanApprovalStore.Approval consumed =
            approvals.read(approval.receiptId);
        assertTrue(consumed.consumed);

        LaboratoryToolRegistry.Event last =
            registry.history(toolId).get(registry.history(toolId).size() - 1);
        assertEquals("ACTIVATE_STABLE", last.action);
        assertEquals(64, last.approvalSha256.length());
        assertEquals(Collections.singletonList(evidence.runId),
            last.evidenceRunIds);

        assertThrows(java.io.IOException.class, () ->
            approvals.applyApprovedTransition(approval.receiptId));
    }

    @Test
    public void changedExecutableSnapshotInvalidatesPendingHumanDecision()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "tamperapproval"
            + UUID.randomUUID().toString().substring(0, 8);
        String source = "return 'approved artifact'";
        String toolId = "approval-tamper-tool";
        String version = "0.1.0";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(app.getFilesDir(), project);

        registry.registerExperimental(descriptor(toolId, version, source));
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            toolId, source.getBytes(StandardCharsets.UTF_8));
        artifacts.bindLuauSource(toolId, version, snapshot.id);
        LaboratoryEngine.Report evidence = evidence(app, project, source);
        registry.qualifyCandidate(
            toolId, version, Collections.singletonList(evidence.runId));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId, version, System.currentTimeMillis());

        Path snapshotPath = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/snapshots/"
                + snapshot.id + ".snap");
        byte[] bytes = Files.readAllBytes(snapshotPath);
        bytes[bytes.length - 1] ^= 0x01;
        Files.write(snapshotPath, bytes);

        assertThrows(java.io.IOException.class, () ->
            approvals.applyApprovedTransition(approval.receiptId));
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(toolId, version));
        assertEquals(null, registry.activeStable(toolId));
    }

    private static LaboratoryEngine.Report evidence(
            Context app, String project, String source) throws Exception {
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "artifact", source, LaboratoryEngine.fingerprint(source))));
        return LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), project, request,
            new LaboratoryEngine.Cancellation());
    }

    private static LaboratoryToolRegistry.Descriptor descriptor(
            String toolId, String version, String source) {
        return new LaboratoryToolRegistry.Descriptor(
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
    }
}
