package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Tests the actual internal orchestration, never the user's scripts or world. */
@RunWith(AndroidJUnit4.class)
public final class LaboratoryToolWorkshopInstrumentedTest {
    private static final class Outcome {
        LaboratorySandboxClient.Result execution;
        LaboratoryToolRegistry.Tool tool;
        boolean reviewRequested;
        java.io.IOException error;
    }

    @Test
    public void passingCaseRequestsReviewAndFailureRemainsExperimental() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "workshop-" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "ai-diagnostic";

        Outcome passing = testVersion(app, projectId, toolId, "0.1.0",
            "return 20 + 22", "42");
        assertNull(passing.error);
        assertNotNull(passing.execution);
        assertEquals("EXECUTED", passing.execution.status);
        assertTrue(passing.reviewRequested);
        assertNotNull(passing.tool);
        assertEquals(LaboratoryToolRegistry.State.CANDIDATE, passing.tool.state);
        assertEquals(passing.execution.runId, passing.tool.evidenceRunId);

        Outcome failing = testVersion(app, projectId, toolId, "0.1.1",
            "return 7", "8");
        assertNull(failing.error);
        assertNotNull(failing.execution);
        assertEquals("EXECUTED", failing.execution.status);
        assertFalse(failing.reviewRequested);
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL, failing.tool.state);
        assertTrue(failing.tool.evidenceRunId.isEmpty());

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId);
        assertEquals(2, registry.list().size());
        assertEquals(LaboratoryToolRegistry.State.CANDIDATE,
            registry.read(toolId, "0.1.0").state);
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL,
            registry.read(toolId, "0.1.1").state);

        LaboratoryReportStore reports =
            new LaboratoryReportStore(app.getFilesDir(), projectId);
        JSONObject passedReport = new JSONObject(reports.read(passing.execution.runId));
        JSONObject failedReport = new JSONObject(reports.read(failing.execution.runId));
        assertEquals("PASS", passedReport.getString("status"));
        assertEquals("FAIL", failedReport.getString("status"));
        assertEquals(passing.tool.snapshotId, passedReport.getString("candidateSnapshotId"));
        assertEquals(failing.tool.snapshotId, failedReport.getString("candidateSnapshotId"));
        assertFalse(reports.read(passing.execution.runId).contains("return 20 + 22"));
        assertFalse(reports.read(failing.execution.runId).contains("return 7"));

        try {
            registry.requestCandidateReview(toolId, "0.1.1", failing.execution.runId);
            org.junit.Assert.fail("Failing candidate must never qualify for review");
        } catch (java.io.IOException expected) {
            assertTrue(expected.getMessage().contains("does not prove"));
        }
    }

    private static Outcome testVersion(Context app, String projectId,
            String toolId, String version, String source, String expected) throws Exception {
        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<Outcome> finished = new AtomicReference<>();
        AtomicReference<Throwable> startupFailure = new AtomicReference<>();
        new Thread(() -> {
            try {
                LaboratoryToolWorkshop.testNewVersion(app, projectId, toolId, version,
                    source, expected, 9151L, 1200,
                    (execution, tool, awaitingReview, error) -> {
                        Outcome out = new Outcome();
                        out.execution = execution;
                        out.tool = tool;
                        out.reviewRequested = awaitingReview;
                        out.error = error;
                        finished.set(out);
                        latch.countDown();
                    });
            } catch (Throwable error) {
                startupFailure.set(error);
                latch.countDown();
            }
        }, "lab-tool-workshop-test").start();
        assertTrue("Workshop did not finish", latch.await(50, TimeUnit.SECONDS));
        if (startupFailure.get() != null) throw new AssertionError(startupFailure.get());
        assertNotNull(finished.get());
        return finished.get();
    }
}
