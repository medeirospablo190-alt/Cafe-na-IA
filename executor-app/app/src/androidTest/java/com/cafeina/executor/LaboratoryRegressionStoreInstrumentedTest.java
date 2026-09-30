package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryRegressionStoreInstrumentedTest {
    private static String projectId() {
        return "regress" + UUID.randomUUID().toString().substring(0, 8);
    }

    private static LaboratoryEngine.Report run(Context app, String project,
            String source, String expected, long seed) throws Exception {
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            seed,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "behavior", source, expected)));
        return LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), project, request, new LaboratoryEngine.Cancellation());
    }

    @Test
    public void passingComparisonIsPersistedWithMetricsAndEvidence() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId();
        String source = "same-behavior";
        String expected = LaboratoryEngine.fingerprint(source);

        LaboratoryEngine.Report baseline = run(app, project, source, expected, 77);
        LaboratoryEngine.Report candidate = run(app, project, source, expected, 77);

        LaboratoryRegressionStore store =
            new LaboratoryRegressionStore(app.getFilesDir(), project);
        LaboratoryRegressionStore.Record record = store.compareAndSave(
            baseline.runId,
            candidate.runId,
            new LaboratoryRegressionEngine.Policy(1000, 60_000, true));

        assertEquals("PASS", record.verdict);
        assertEquals(baseline.runId, record.baselineRunId);
        assertEquals(candidate.runId, record.candidateRunId);
        assertEquals(Collections.singletonList("behavior"), record.coveredTests);
        assertTrue(record.reasons.isEmpty());
        assertTrue(record.allowedDurationMs >= record.baselineDurationMs);
        assertEquals(1, store.list().size());
        assertEquals(record.comparisonId,
            store.read(record.comparisonId).comparisonId);
    }

    @Test
    public void seedOrBehaviorMismatchIsRecordedAsFailure() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId();
        String source = "candidate-behavior";
        String expected = LaboratoryEngine.fingerprint(source);

        LaboratoryEngine.Report baseline = run(app, project, source, expected, 10);
        LaboratoryEngine.Report differentSeed = run(app, project, source, expected, 11);
        LaboratoryEngine.Report wrongBehavior = run(app, project, source, "wrong", 10);

        LaboratoryRegressionStore store =
            new LaboratoryRegressionStore(app.getFilesDir(), project);
        LaboratoryRegressionEngine.Policy policy =
            new LaboratoryRegressionEngine.Policy(1000, 60_000, true);

        LaboratoryRegressionStore.Record seedFailure =
            store.compareAndSave(baseline.runId, differentSeed.runId, policy);
        assertEquals("FAIL", seedFailure.verdict);
        assertTrue(seedFailure.reasons.contains("seed differs"));

        LaboratoryRegressionStore.Record behaviorFailure =
            store.compareAndSave(baseline.runId, wrongBehavior.runId, policy);
        assertEquals("FAIL", behaviorFailure.verdict);
        assertTrue(behaviorFailure.reasons.contains("candidate run is not PASS"));
        assertTrue(behaviorFailure.reasons.contains("expected output changed: behavior"));

        assertEquals(2, store.list().size());
    }

    @Test
    public void sameRunCannotBeUsedAsItsOwnBaseline() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId();
        String source = "self-baseline";
        LaboratoryEngine.Report report =
            run(app, project, source, LaboratoryEngine.fingerprint(source), 1);
        LaboratoryRegressionStore store =
            new LaboratoryRegressionStore(app.getFilesDir(), project);

        try {
            store.compareAndSave(report.runId, report.runId,
                new LaboratoryRegressionEngine.Policy(10, 10, true));
            throw new AssertionError("same run must not compare against itself");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("run pair"));
        }
    }
}
