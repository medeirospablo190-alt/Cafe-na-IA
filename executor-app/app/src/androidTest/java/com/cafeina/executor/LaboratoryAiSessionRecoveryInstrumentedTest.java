package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ActivityInfo;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiSessionRecoveryInstrumentedTest {
    @Test
    public void orphanedSessionRequiresExplicitRecoveryDecision() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "recover" + UUID.randomUUID().toString().substring(0, 8);
        String sessionId = UUID.randomUUID().toString();

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiSessionRecoveryActivity.class), 0);
        assertFalse("Recovery Activity must remain private", info.exported);

        LaboratoryAiSessionStore store =
            new LaboratoryAiSessionStore(app.getFilesDir(), project);
        store.begin(
            sessionId,
            System.currentTimeMillis() - 1_000L,
            Collections.singletonList("ghost-tool"),
            5,
            100,
            60_000L);
        store.append(
            sessionId,
            LaboratoryAiSessionStore.INVOKE_REQUEST,
            "ACTIVE",
            "ghost-tool",
            LaboratoryEngine.fingerprint("private-orphan-input").substring(7, 71),
            20,
            "",
            "REQUESTED",
            2,
            20);

        assertFalse(LaboratoryAiSessionController.isLiveSession(sessionId));

        LaboratoryAiSessionRecovery recovery =
            new LaboratoryAiSessionRecovery(app.getFilesDir(), project);
        java.util.List<LaboratoryAiSessionRecovery.Item> interrupted =
            recovery.markInterruptedOrphans();

        assertEquals(1, interrupted.size());
        LaboratoryAiSessionRecovery.Item item = interrupted.get(0);
        assertEquals(sessionId, item.sessionId);
        assertEquals("INTERRUPTED", item.state);
        assertEquals(3, item.invocationsRemaining);
        assertEquals(80, item.inputBytesRemaining);
        assertTrue(item.remainingSessionMs > 0);
        assertTrue(item.canRequestRestart());

        LaboratoryAiSessionRecovery.Item pending =
            recovery.requestRestart(sessionId);
        assertEquals("RECOVERY_PENDING", pending.state);
        assertFalse(LaboratoryAiSessionController.isLiveSession(sessionId));
        assertEquals(1, store.list().size());

        LaboratoryAiSessionController.Policy remaining =
            recovery.pendingRestartPolicy(sessionId);
        assertEquals(Collections.singletonList("ghost-tool"),
            remaining.allowedToolIds);
        assertEquals(3, remaining.maxInvocations);
        assertEquals(80, remaining.maxTotalInputBytes);
        assertTrue(remaining.maxSessionMs >= 1_000L);
        assertTrue(remaining.maxSessionMs <= 60_000L);

        recovery.close(sessionId);
        assertTrue(recovery.listActionable().isEmpty());
        assertEquals("FINISHED", store.list().get(0).state);

        java.util.List<LaboratoryAiSessionStore.Event> events =
            store.readEvents(sessionId);
        assertTrue(events.stream().anyMatch(event ->
            LaboratoryAiSessionStore.INTERRUPT.equals(event.type)));
        assertTrue(events.stream().anyMatch(event ->
            LaboratoryAiSessionStore.RECOVERY_REQUEST.equals(event.type)));
        assertTrue(events.stream().anyMatch(event ->
            LaboratoryAiSessionStore.RECOVERY_CLOSE.equals(event.type)));
    }

    @Test
    public void liveSessionInCurrentProcessIsNeverMarkedInterrupted()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "liverecover"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "live-recovery-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app,
                project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    3,
                    256,
                    30_000L));

        assertTrue(LaboratoryAiSessionController.isLiveSession(
            handles.host.sessionId()));

        LaboratoryAiSessionRecovery recovery =
            new LaboratoryAiSessionRecovery(app.getFilesDir(), project);
        assertTrue(recovery.markInterruptedOrphans().isEmpty());

        LaboratoryAiSessionStore.Summary summary =
            new LaboratoryAiSessionStore(app.getFilesDir(), project)
                .list().get(0);
        assertEquals("ACTIVE", summary.state);

        handles.host.pause();
        assertTrue(LaboratoryAiSessionController.isLiveSession(
            handles.host.sessionId()));
        assertTrue(recovery.markInterruptedOrphans().isEmpty());

        handles.host.cancel();
        assertFalse(LaboratoryAiSessionController.isLiveSession(
            handles.host.sessionId()));
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
