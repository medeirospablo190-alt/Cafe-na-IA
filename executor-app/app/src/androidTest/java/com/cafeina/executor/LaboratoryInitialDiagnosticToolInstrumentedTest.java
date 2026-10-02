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

import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryInitialDiagnosticToolInstrumentedTest {
    private static final class ExecutionOutcome {
        LaboratoryAiToolController.Execution execution;
        Throwable error;
    }

    @Test
    public void bootstrapStopsAtCandidateThenRequiresHumanStableAndAiGrant()
            throws Exception {
        Context app =
            InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project =
            "bootstrap" + UUID.randomUUID().toString().substring(0, 8);

        assertEquals(
            LaboratoryInitialDiagnosticTool.State.MISSING,
            LaboratoryInitialDiagnosticTool.state(
                app.getFilesDir(), project));

        assertEquals(
            LaboratoryInitialDiagnosticTool.State.CANDIDATE,
            prepareOffMain(app, project));

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        assertNull(registry.activeStable(
            LaboratoryInitialDiagnosticTool.TOOL_ID));
        assertTrue(
            LaboratoryAiToolController.listAvailable(app, project).isEmpty());

        // Preparing again must not create a second version or self-promote.
        assertEquals(
            LaboratoryInitialDiagnosticTool.State.CANDIDATE,
            prepareOffMain(app, project));
        int bootstrapVersions = 0;
        for (LaboratoryToolRegistry.Descriptor descriptor :
                registry.listRegisteredVersions()) {
            if (LaboratoryInitialDiagnosticTool.TOOL_ID.equals(
                    descriptor.toolId)) {
                bootstrapVersions++;
            }
        }
        assertEquals(1, bootstrapVersions);

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(
                app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                LaboratoryInitialDiagnosticTool.TOOL_ID,
                LaboratoryInitialDiagnosticTool.VERSION,
                System.currentTimeMillis());
        approvals.applyApprovedTransition(approval.receiptId);

        assertNotNull(registry.activeStable(
            LaboratoryInitialDiagnosticTool.TOOL_ID));
        // STABLE is still deny-by-default for the AI.
        assertTrue(
            LaboratoryAiToolController.listAvailable(app, project).isEmpty());

        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(
                app.getFilesDir(), project);
        permissions.grantAfterDeviceCredential(
            LaboratoryInitialDiagnosticTool.TOOL_ID,
            System.currentTimeMillis());

        List<LaboratoryAiToolController.Tool> available =
            LaboratoryAiToolController.listAvailable(app, project);
        assertEquals(1, available.size());
        assertEquals(
            LaboratoryInitialDiagnosticTool.TOOL_ID,
            available.get(0).toolId);
        assertTrue(
            available.get(0).capabilities.contains("text-roundtrip"));

        ExecutionOutcome outcome =
            executeOffMain(app, project, "roundtrip-ok");
        if (outcome.error != null) {
            throw new AssertionError(outcome.error);
        }
        assertNotNull(outcome.execution);
        assertEquals(
            "roundtrip-ok",
            outcome.execution.firstReturn);
    }

    private static LaboratoryInitialDiagnosticTool.State prepareOffMain(
            Context app, String project) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryInitialDiagnosticTool.State> state =
            new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();
        new Thread(() -> {
            try {
                state.set(
                    LaboratoryInitialDiagnosticTool.prepareCandidate(
                        app, project));
            } catch (Throwable error) {
                failure.set(error);
            } finally {
                done.countDown();
            }
        }, "diagnostic-bootstrap-test").start();

        assertTrue(
            "diagnostic bootstrap timed out",
            done.await(30, TimeUnit.SECONDS));
        if (failure.get() != null) {
            throw new AssertionError(failure.get());
        }
        return state.get();
    }

    private static ExecutionOutcome executeOffMain(
            Context app, String project, String input) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<ExecutionOutcome> result =
            new AtomicReference<>();
        new Thread(() -> {
            ExecutionOutcome outcome = new ExecutionOutcome();
            try {
                LaboratoryAiToolController.executeInternal(
                    app,
                    project,
                    LaboratoryInitialDiagnosticTool.TOOL_ID,
                    input,
                    (success, failure) -> {
                        outcome.execution = success;
                        outcome.error = failure;
                        result.set(outcome);
                        done.countDown();
                    });
            } catch (Throwable error) {
                outcome.error = error;
                result.set(outcome);
                done.countDown();
            }
        }, "diagnostic-roundtrip-test").start();

        assertTrue(
            "diagnostic roundtrip timed out",
            done.await(40, TimeUnit.SECONDS));
        assertNotNull(result.get());
        return result.get();
    }
}
