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
public final class LaboratoryAiLiveSessionControlInstrumentedTest {
    @Test
    public void liveDashboardControlsOnlyHostHandleAndCurrentProject()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "livepanel"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "live-panel-tool";
        prepareGrantedStable(app, project, toolId);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiLiveSessionActivity.class), 0);
        assertFalse("Live session Activity must remain private", info.exported);

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app,
                project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    4,
                    256,
                    30_000L));

        assertEquals(1, LaboratoryAiLiveSessionRegistry.list(project).size());
        LaboratoryAiLiveSessionRegistry.Info live =
            LaboratoryAiLiveSessionRegistry.list(project).get(0);
        assertEquals(handles.host.sessionId(), live.sessionId);
        assertEquals(
            LaboratoryAiSessionController.State.ACTIVE,
            live.snapshot.state);
        assertEquals(Collections.singletonList(toolId), live.allowedToolIds);

        assertTrue(LaboratoryAiLiveSessionRegistry
            .list(project + "other").isEmpty());
        assertThrows(java.io.IOException.class, () ->
            LaboratoryAiLiveSessionRegistry.pause(
                project + "other", handles.host.sessionId()));

        LaboratoryAiSessionController.Snapshot paused =
            LaboratoryAiLiveSessionRegistry.pause(
                project, handles.host.sessionId());
        assertEquals(LaboratoryAiSessionController.State.PAUSED, paused.state);
        assertEquals(
            LaboratoryAiSessionController.State.PAUSED,
            handles.host.snapshot().state);

        LaboratoryAiSessionController.Snapshot resumed =
            LaboratoryAiLiveSessionRegistry.resume(
                project, handles.host.sessionId());
        assertEquals(LaboratoryAiSessionController.State.ACTIVE, resumed.state);

        LaboratoryAiLiveSessionRegistry.cancel(
            project, handles.host.sessionId());
        assertEquals(
            LaboratoryAiSessionController.State.CANCELLED,
            handles.host.snapshot().state);
        assertTrue(LaboratoryAiLiveSessionRegistry.list(project).isEmpty());

        Set<String> aiMethods = new HashSet<>();
        for (Method method :
                LaboratoryAiSessionController.AiHandle.class.getDeclaredMethods()) {
            aiMethods.add(method.getName());
        }
        assertTrue(aiMethods.contains("listAvailable"));
        assertTrue(aiMethods.contains("execute"));
        assertTrue(aiMethods.contains("sessionId"));
        assertFalse(aiMethods.contains("pause"));
        assertFalse(aiMethods.contains("resume"));
        assertFalse(aiMethods.contains("cancel"));
        assertFalse(aiMethods.contains("snapshot"));
    }

    @Test
    public void livePauseCancelsCurrentWorkerAndKeepsSessionPaused()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "livepause"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "live-pause-tool";
        prepareGrantedStable(
            app, project, toolId,
            "if tool_input == 'loop' then while true do end end return tool_input");

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app,
                project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    3,
                    256,
                    30_000L));

        java.util.concurrent.CountDownLatch done =
            new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.atomic.AtomicReference<Outcome> ref =
            new java.util.concurrent.atomic.AtomicReference<>();

        new Thread(() -> {
            Outcome outcome = new Outcome();
            try {
                handles.ai.execute(toolId, "loop", (success, failure) -> {
                    outcome.returned = success;
                    outcome.error = failure;
                    ref.set(outcome);
                    done.countDown();
                });
            } catch (Throwable error) {
                outcome.error = error;
                ref.set(outcome);
                done.countDown();
            }
        }, "live-session-pause-worker").start();

        long deadline = System.currentTimeMillis() + 10_000L;
        boolean active = false;
        while (System.currentTimeMillis() < deadline) {
            java.util.List<LaboratoryAiLiveSessionRegistry.Info> list =
                LaboratoryAiLiveSessionRegistry.list(project);
            if (!list.isEmpty() && list.get(0).snapshot.hasActiveInvocation) {
                active = true;
                break;
            }
            Thread.sleep(25L);
        }
        assertTrue("Worker never became active", active);

        LaboratoryAiSessionController.Snapshot paused =
            LaboratoryAiLiveSessionRegistry.pause(
                project, handles.host.sessionId());
        assertEquals(LaboratoryAiSessionController.State.PAUSED, paused.state);

        assertTrue("Paused worker did not finish",
            done.await(20, java.util.concurrent.TimeUnit.SECONDS));
        assertNotNull(ref.get());
        assertNull(ref.get().returned);
        assertNotNull(ref.get().error);
        assertEquals(
            LaboratoryAiSessionController.State.PAUSED,
            handles.host.snapshot().state);

        LaboratoryAiLiveSessionRegistry.resume(
            project, handles.host.sessionId());
        assertEquals(
            LaboratoryAiSessionController.State.ACTIVE,
            handles.host.snapshot().state);
        LaboratoryAiLiveSessionRegistry.cancel(
            project, handles.host.sessionId());
    }

    @Test
    public void finishedSessionIsPrunedFromLiveDashboard() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "livefinish"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "live-finish-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app,
                project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    1,
                    256,
                    30_000L));

        Outcome outcome = execute(handles.ai, toolId, "finish");
        if (outcome.error != null) throw new AssertionError(outcome.error);
        assertNotNull(outcome.returned);
        assertEquals("finish", outcome.returned.firstReturn);
        assertEquals(
            LaboratoryAiSessionController.State.FINISHED,
            handles.host.snapshot().state);

        assertTrue(LaboratoryAiLiveSessionRegistry.list(project).isEmpty());
    }

    private static final class Outcome {
        LaboratoryAiToolController.Execution returned;
        Throwable error;
    }

    private static Outcome execute(
            LaboratoryAiSessionController.AiHandle ai,
            String toolId, String input) throws Exception {
        java.util.concurrent.CountDownLatch done =
            new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.atomic.AtomicReference<Outcome> ref =
            new java.util.concurrent.atomic.AtomicReference<>();

        new Thread(() -> {
            Outcome outcome = new Outcome();
            try {
                ai.execute(toolId, input, (success, failure) -> {
                    outcome.returned = success;
                    outcome.error = failure;
                    ref.set(outcome);
                    done.countDown();
                });
            } catch (Throwable error) {
                outcome.error = error;
                ref.set(outcome);
                done.countDown();
            }
        }, "live-session-panel-test").start();

        assertTrue(done.await(30, java.util.concurrent.TimeUnit.SECONDS));
        assertNotNull(ref.get());
        return ref.get();
    }

    private static void prepareGrantedStable(
            Context app, String project, String toolId) throws Exception {
        prepareGrantedStable(app, project, toolId, "return tool_input");
    }

    private static void prepareGrantedStable(
            Context app, String project, String toolId, String source)
            throws Exception {
        String version = "1.0.0";

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
