package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiSessionControllerInstrumentedTest {
    private static final class Outcome {
        LaboratoryAiToolController.Execution execution;
        Throwable error;
    }

    @Test
    public void sessionSeparatesHostControlsAndEnforcesInvocationBudget()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "aisession" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "session-tool";
        String source = "return tool_input .. ':session-ok'";
        prepareGrantedStable(app, project, toolId, source);

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app, project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    128,
                    30_000L));

        assertEquals(LaboratoryAiSessionController.State.ACTIVE,
            handles.host.snapshot().state);
        assertEquals(1, handles.ai.listAvailable().size());

        handles.host.pause();
        assertEquals(LaboratoryAiSessionController.State.PAUSED,
            handles.host.snapshot().state);
        Outcome paused = execute(handles.ai, toolId, "blocked-while-paused");
        assertNull(paused.execution);
        assertNotNull(paused.error);
        assertTrue(paused.error.getMessage().contains("paused"));

        handles.host.resume();
        assertEquals(LaboratoryAiSessionController.State.ACTIVE,
            handles.host.snapshot().state);

        Outcome first = execute(handles.ai, toolId, "one");
        if (first.error != null) throw new AssertionError(first.error);
        assertEquals("one:session-ok", first.execution.firstReturn);
        assertEquals(1, handles.host.snapshot().invocationsUsed);

        Outcome second = execute(handles.ai, toolId, "two");
        if (second.error != null) throw new AssertionError(second.error);
        assertEquals("two:session-ok", second.execution.firstReturn);

        LaboratoryAiSessionController.Snapshot exhausted =
            handles.host.snapshot();
        assertEquals(2, exhausted.invocationsUsed);
        assertEquals(0, exhausted.invocationsRemaining);
        assertEquals(LaboratoryAiSessionController.State.FINISHED,
            exhausted.state);
        assertTrue(handles.ai.listAvailable().isEmpty());

        Outcome third = execute(handles.ai, toolId, "three");
        assertNull(third.execution);
        assertNotNull(third.error);
        assertTrue(third.error.getMessage().contains("finished"));
    }

    @Test
    public void hostCancelStopsActiveInvocationAndEndsSession()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "aicancel" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "cancel-tool";
        String source =
            "if tool_input == 'loop' then while true do end end return 'ok'";
        prepareGrantedStable(app, project, toolId, source);

        LaboratoryAiSessionController.Handles handles =
            LaboratoryAiSessionController.create(
                app, project,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    3,
                    128,
                    30_000L));

        CountDownLatch launched = new CountDownLatch(1);
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Outcome> outcome = new AtomicReference<>();

        new Thread(() -> {
            Outcome value = new Outcome();
            try {
                handles.ai.execute(toolId, "loop", (success, failure) -> {
                    value.execution = success;
                    value.error = failure;
                    outcome.set(value);
                    done.countDown();
                });
                launched.countDown();
            } catch (Throwable error) {
                value.error = error;
                outcome.set(value);
                launched.countDown();
                done.countDown();
            }
        }, "ai-session-cancel-test").start();

        assertTrue("AI invocation did not launch",
            launched.await(10, TimeUnit.SECONDS));
        handles.host.cancel();

        assertTrue("Cancelled AI invocation did not finish",
            done.await(20, TimeUnit.SECONDS));
        assertNotNull(outcome.get());
        assertNull(outcome.get().execution);
        assertNotNull(outcome.get().error);
        assertEquals(LaboratoryAiSessionController.State.CANCELLED,
            handles.host.snapshot().state);
        assertTrue(handles.ai.listAvailable().isEmpty());
    }

    private static Outcome execute(LaboratoryAiSessionController.AiHandle ai,
            String toolId, String input) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Outcome> reference = new AtomicReference<>();
        new Thread(() -> {
            Outcome outcome = new Outcome();
            try {
                ai.execute(toolId, input, (success, failure) -> {
                    outcome.execution = success;
                    outcome.error = failure;
                    reference.set(outcome);
                    done.countDown();
                });
            } catch (Throwable error) {
                outcome.error = error;
                reference.set(outcome);
                done.countDown();
            }
        }, "ai-session-invoke-test").start();

        assertTrue("AI session invocation did not finish",
            done.await(30, TimeUnit.SECONDS));
        assertNotNull(reference.get());
        return reference.get();
    }

    private static void prepareGrantedStable(Context app, String project,
            String toolId, String source) throws Exception {
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
    }
}
