package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ServiceInfo;
import android.os.Process;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratorySandboxInstrumentedTest {
    @Test
    public void workerHasIsolatedUidAndNoFilesystemCapability() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        ServiceInfo info = app.getPackageManager().getServiceInfo(
            new ComponentName(app, LaboratorySandboxService.class), 0);
        assertFalse("Laboratory service must not be exported", info.exported);
        assertTrue("Laboratory service must have an isolated Android UID",
            (info.flags & ServiceInfo.FLAG_ISOLATED_PROCESS) != 0);

        LaboratorySandboxClient.Result arithmetic = run(app, "return 2 + 2", 1000);
        assertEquals(arithmetic.error, "EXECUTED", arithmetic.status);
        assertEquals("4", arithmetic.firstReturn);
        assertNotEquals("Worker UID must differ from host UID",
            Process.myUid(), arithmetic.workerUid);

        LaboratorySandboxClient.Result denied = run(app, "return fs == nil", 1000);
        assertEquals(denied.error, "EXECUTED", denied.status);
        assertEquals("true", denied.firstReturn);
        assertNotEquals(Process.myUid(), denied.workerUid);
    }

    @Test
    public void hostCanCancelACandidateWithoutModelCooperation() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratorySandboxClient.Result> outcome = new AtomicReference<>();
        LaboratorySandboxClient.Session session = LaboratorySandboxClient.execute(
            app, "while true do end", 3000, result -> {
                outcome.set(result);
                done.countDown();
            });
        session.cancel();
        assertTrue("Host cancellation did not finish",
            done.await(10, TimeUnit.SECONDS));
        assertNotNull(outcome.get());
        assertEquals("CANCELLED", outcome.get().status);
    }

    @Test
    public void isolatedCandidateTestMustRecordPrivacySafeReport() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "isolated-" + UUID.randomUUID().toString().substring(0, 8);
        String fixture = "return 2 + 2 -- never persist this original candidate text";
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratorySandboxClient.Result> execution = new AtomicReference<>();
        AtomicReference<Throwable> problem = new AtomicReference<>();
        new Thread(() -> {
            try {
                LaboratoryCandidateRunner.runInternal(app, projectId, fixture, "4", 42L,
                    1000, (result, passed, recordingError) -> {
                        execution.set(result);
                        if (!passed || recordingError != null) {
                            problem.set(recordingError == null
                                ? new AssertionError("candidate test did not pass")
                                : recordingError);
                        }
                        done.countDown();
                    });
            } catch (Throwable error) {
                problem.set(error);
                done.countDown();
            }
        }, "lab-test-caller").start();

        assertTrue("Candidate report was not recorded",
            done.await(40, TimeUnit.SECONDS));
        if (problem.get() != null) throw new AssertionError(problem.get());
        assertNotNull(execution.get());
        LaboratoryReportStore vault = new LaboratoryReportStore(app.getFilesDir(), projectId);
        assertEquals(1, vault.list().size());
        LaboratoryReportStore.Entry entry = vault.list().get(0);
        assertEquals("luau-isolated-candidate", entry.toolId);
        assertEquals("PASS", entry.status);
        assertFalse(entry.reportText.contains(fixture));
        assertFalse(entry.reportText.contains("return 2 + 2"));
        assertTrue(entry.reportText.contains(execution.get().sourceSha256));
        JSONObject report = new JSONObject(entry.reportText);
        assertTrue("Candidate source baseline must have been verified",
            report.getBoolean("snapshotVerified"));
        String snapshotId = report.getString("candidateSnapshotId");
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), projectId);
        LaboratorySnapshotStore.Snapshot saved = snapshots.readCopy(snapshotId);
        assertEquals(execution.get().sourceSha256, saved.sha256);
        assertEquals(fixture, new String(saved.contentCopy(),
            java.nio.charset.StandardCharsets.UTF_8));
        assertEquals(1, snapshots.listVerified().size());

        // Only an actually persisted PASS of this exact snapshot can open
        // a review request. A candidate is not STABLE or auto-activated.
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId);
        LaboratoryToolRegistry.Tool experimental =
            registry.registerExperimental("isolation-checker", "0.1.0", snapshotId, 1000);
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL, experimental.state);
        assertEquals(saved.sha256, experimental.sourceSha256);
        LaboratoryToolRegistry.Tool candidate =
            registry.requestCandidateReview("isolation-checker", "0.1.0", entry.runId);
        assertEquals(LaboratoryToolRegistry.State.CANDIDATE, candidate.state);
        assertEquals(entry.runId, candidate.evidenceRunId);
        assertEquals("LUAU_ISOLATED_NO_FILES", candidate.capability);
        assertEquals(LaboratoryToolRegistry.State.CANDIDATE,
            registry.read("isolation-checker", "0.1.0").state);

        try {
            registry.requestCandidateReview("isolation-checker", "0.1.0", entry.runId);
            org.junit.Assert.fail("Duplicate candidate review must fail");
        } catch (java.io.IOException expected) {
            assertTrue(expected.getMessage().contains("already"));
        }

        LaboratorySnapshotStore.Snapshot different = snapshots.create(
            "candidate-luau", "return 'not the tested source'".getBytes(
                java.nio.charset.StandardCharsets.UTF_8));
        registry.registerExperimental("different-tool", "0.1.0", different.id, 1000);
        try {
            registry.requestCandidateReview("different-tool", "0.1.0", entry.runId);
            org.junit.Assert.fail("Evidence for another source must be rejected");
        } catch (java.io.IOException expected) {
            assertTrue(expected.getMessage().contains("does not prove"));
        }
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL,
            registry.read("different-tool", "0.1.0").state);
    }

    private static LaboratorySandboxClient.Result run(Context app, String source, int timeoutMs)
            throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratorySandboxClient.Result> outcome = new AtomicReference<>();
        LaboratorySandboxClient.execute(app, source, timeoutMs, result -> {
            outcome.set(result);
            done.countDown();
        });
        assertTrue("Isolated worker did not answer before host watchdog",
            done.await(30, TimeUnit.SECONDS));
        assertNotNull(outcome.get());
        return outcome.get();
    }
}
