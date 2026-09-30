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

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryStableActivationInstrumentedTest {
    private static final class WorkshopOutcome {
        LaboratoryToolRegistry.Tool tool;
        Throwable error;
    }

    @Test
    public void approvedCandidateCanActivateDeactivateAndRollbackWithoutExecution()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "stable-" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "stable-checker";
        String version = "0.1.0";

        ActivityInfo activity = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryStableToolsActivity.class), 0);
        assertFalse("STABLE control activity must remain private", activity.exported);

        WorkshopOutcome prepared = prepareCandidate(
            app, projectId, toolId, version, "return 6 * 7", "42");
        if (prepared.error != null) throw new AssertionError(prepared.error);
        assertNotNull(prepared.tool);
        assertEquals(LaboratoryToolRegistry.State.CANDIDATE, prepared.tool.state);

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), projectId);
        approvals.recordDeviceCredentialApproval(
            toolId, version, System.currentTimeMillis());
        assertTrue(approvals.isApproved(toolId, version));

        LaboratoryStableActivationStore stable =
            new LaboratoryStableActivationStore(app.getFilesDir(), projectId);
        assertNull(stable.current(toolId));

        LaboratoryStableActivationStore.Event activated =
            stable.activateApproved(toolId, version, System.currentTimeMillis());
        assertEquals(LaboratoryStableActivationStore.Type.ACTIVATE, activated.type);
        LaboratoryStableActivationStore.Active active = stable.current(toolId);
        assertNotNull(active);
        assertEquals(version, active.version);
        assertEquals(prepared.tool.sourceSha256, active.sourceSha256);
        assertEquals(prepared.tool.manifestSha256, active.manifestSha256);
        assertTrue(stable.isActive(toolId, version));

        // STABLE selection is a separate control plane; registry remains CANDIDATE.
        assertEquals(LaboratoryToolRegistry.State.CANDIDATE,
            new LaboratoryToolRegistry(app.getFilesDir(), projectId)
                .read(toolId, version).state);

        assertThrows(IOException.class, () ->
            stable.activateApproved(toolId, version, System.currentTimeMillis()));

        LaboratoryStableActivationStore.Event deactivated =
            stable.deactivate(toolId, System.currentTimeMillis());
        assertEquals(LaboratoryStableActivationStore.Type.DEACTIVATE, deactivated.type);
        assertNull(stable.current(toolId));
        assertFalse(stable.isActive(toolId, version));

        // Re-activation is an append-only rollback; old events stay intact.
        LaboratoryStableActivationStore.Event rollback =
            stable.activateApproved(toolId, version, System.currentTimeMillis());
        assertEquals(LaboratoryStableActivationStore.Type.ACTIVATE, rollback.type);
        assertEquals(version, stable.current(toolId).version);
        assertEquals(3, stable.listHistory(toolId).size());
        assertEquals(1, stable.listActive().size());

        LaboratoryStableActivationStore unrelated =
            new LaboratoryStableActivationStore(app.getFilesDir(),
                "other-" + UUID.randomUUID().toString().substring(0, 8));
        assertTrue(unrelated.listActive().isEmpty());

        assertThrows(IOException.class, () ->
            stable.deactivate(toolId, System.currentTimeMillis() - 120_000L));
        assertEquals(version, stable.current(toolId).version);
    }

    @Test
    public void tamperedStableEventFailsClosedAndHistoryIsPreserved() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "stable-tamper-" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "tamper-stable";
        String version = "1.0.0";

        WorkshopOutcome prepared = prepareCandidate(
            app, projectId, toolId, version, "return 'ok'", "ok");
        if (prepared.error != null) throw new AssertionError(prepared.error);
        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), projectId);
        approvals.recordDeviceCredentialApproval(
            toolId, version, System.currentTimeMillis());

        LaboratoryStableActivationStore stable =
            new LaboratoryStableActivationStore(app.getFilesDir(), projectId);
        LaboratoryStableActivationStore.Event event =
            stable.activateApproved(toolId, version, System.currentTimeMillis());

        Path file = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + projectId + "/stable-tool-events/"
                + toolId + "/" + event.eventId + ".event");
        byte[] bytes = Files.readAllBytes(file);
        bytes[bytes.length - 2] ^= 1;
        Files.write(file, bytes);

        assertThrows(IOException.class, () -> stable.current(toolId));
        assertThrows(IOException.class, () -> stable.listHistory(toolId));
        assertTrue("Tampered evidence must remain visible for diagnosis", Files.exists(file));
    }

    private static WorkshopOutcome prepareCandidate(Context app, String projectId,
            String toolId, String version, String source, String expected) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<WorkshopOutcome> result = new AtomicReference<>();
        new Thread(() -> {
            WorkshopOutcome out = new WorkshopOutcome();
            try {
                LaboratoryToolWorkshop.testNewVersion(app, projectId, toolId, version,
                    source, expected, 4401L, 1000,
                    (execution, tool, awaitingReview, error) -> {
                        out.tool = tool;
                        if (error != null) out.error = error;
                        else if (!awaitingReview) {
                            out.error = new AssertionError(
                                "passing tool did not reach CANDIDATE review");
                        }
                        result.set(out);
                        done.countDown();
                    });
            } catch (Throwable error) {
                out.error = error;
                result.set(out);
                done.countDown();
            }
        }, "stable-tool-prepare").start();

        assertTrue("candidate preparation timed out", done.await(45, TimeUnit.SECONDS));
        assertNotNull(result.get());
        return result.get();
    }
}
