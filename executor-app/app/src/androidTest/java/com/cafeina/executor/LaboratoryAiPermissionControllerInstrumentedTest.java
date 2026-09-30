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
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiPermissionControllerInstrumentedTest {
    private static final class Outcome {
        LaboratoryAiToolController.Execution execution;
        Throwable error;
    }

    @Test
    public void aiIsDeniedByDefaultThenCanUseOnlyExplicitlyGrantedStable()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "aiperm" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "ai-echo-tool";
        String version = "1.0.0";
        String source = "return tool_input .. ':ai-ok'";

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiPermissionsActivity.class), 0);
        assertFalse("AI permission Activity must remain private", info.exported);

        prepareHumanApprovedStable(app, project, toolId, version, source);

        assertTrue(LaboratoryAiToolController.listAvailable(app, project).isEmpty());
        Outcome denied = execute(app, project, toolId, "before-grant");
        assertNull(denied.execution);
        assertNotNull(denied.error);
        assertTrue(denied.error instanceof SecurityException);

        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(app.getFilesDir(), project);
        assertThrows(java.io.IOException.class, () ->
            permissions.grantAfterDeviceCredential(
                toolId, System.currentTimeMillis() - 120_000L));

        LaboratoryAiPermissionStore.Grant grant =
            permissions.grantAfterDeviceCredential(
                toolId, System.currentTimeMillis());
        assertEquals(toolId, grant.toolId);
        assertEquals(version, grant.version);
        assertEquals(64, grant.artifactSha256.length());
        assertEquals(1, permissions.listActiveGrants().size());

        assertEquals(1, LaboratoryAiToolController.listAvailable(app, project).size());
        LaboratoryAiToolController.Tool visible =
            LaboratoryAiToolController.listAvailable(app, project).get(0);
        assertEquals(toolId, visible.toolId);
        assertEquals(version, visible.version);
        assertTrue(visible.capabilities.contains(
            LaboratoryStableToolExecutor.REQUIRED_CAPABILITY));

        Outcome allowed = execute(app, project, toolId, "case-42");
        if (allowed.error != null) throw new AssertionError(allowed.error);
        assertNotNull(allowed.execution);
        assertEquals("case-42:ai-ok", allowed.execution.firstReturn);
        assertEquals(toolId, allowed.execution.toolId);
        assertEquals(version, allowed.execution.toolVersion);

        assertThrows(java.io.IOException.class, () ->
            permissions.grantAfterDeviceCredential(
                toolId, System.currentTimeMillis()));

        permissions.revoke(toolId);
        assertFalse(permissions.isGranted(toolId));
        assertTrue(LaboratoryAiToolController.listAvailable(app, project).isEmpty());

        Outcome revoked = execute(app, project, toolId, "after-revoke");
        assertNull(revoked.execution);
        assertNotNull(revoked.error);
        assertTrue(revoked.error instanceof SecurityException);
    }

    private static void prepareHumanApprovedStable(Context app, String project,
            String toolId, String version, String source) throws Exception {
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

        assertNotNull(registry.activeStable(toolId));
        assertEquals(version, registry.activeStable(toolId).version);
    }

    private static Outcome execute(Context app, String project,
            String toolId, String input) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Outcome> reference = new AtomicReference<>();
        new Thread(() -> {
            Outcome outcome = new Outcome();
            try {
                LaboratoryAiToolController.executeInternal(
                    app, project, toolId, input, (success, failure) -> {
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
        }, "ai-tool-controller-test").start();

        assertTrue("AI tool controller did not finish",
            done.await(40, TimeUnit.SECONDS));
        assertNotNull(reference.get());
        return reference.get();
    }
}
