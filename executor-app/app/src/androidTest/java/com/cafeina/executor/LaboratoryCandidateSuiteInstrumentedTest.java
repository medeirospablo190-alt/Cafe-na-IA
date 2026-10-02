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

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryCandidateSuiteInstrumentedTest {
    @Test
    public void suiteReusesOneSnapshotAndPersistsNamedCases()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "suite" + UUID.randomUUID().toString().substring(0, 8);
        String candidate = "return tool_input";

        List<LaboratoryCandidateSuiteRunner.TestCase> cases =
            Arrays.asList(
                new LaboratoryCandidateSuiteRunner.TestCase(
                    "alpha_roundtrip",
                    "PRIVATE_ALPHA_INPUT",
                    "PRIVATE_ALPHA_INPUT",
                    1000),
                new LaboratoryCandidateSuiteRunner.TestCase(
                    "beta_roundtrip",
                    "PRIVATE_BETA_INPUT",
                    "PRIVATE_BETA_INPUT",
                    1000));

        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryCandidateSuiteRunner.Result> result =
            new AtomicReference<>();
        AtomicReference<IOExceptionHolder> failure =
            new AtomicReference<>();

        new Thread(() -> {
            try {
                LaboratoryCandidateSuiteRunner.runInternal(
                    app,
                    project,
                    candidate,
                    cases,
                    77L,
                    false,
                    (suite, error) -> {
                        result.set(suite);
                        if (error != null) {
                            failure.set(new IOExceptionHolder(error));
                        }
                        done.countDown();
                    });
            } catch (Throwable error) {
                failure.set(new IOExceptionHolder(error));
                done.countDown();
            }
        }, "candidate-suite-test").start();

        assertTrue(
            "candidate suite did not finish",
            done.await(80, TimeUnit.SECONDS));
        assertNull(
            failure.get() == null ? null : failure.get().error,
            failure.get() == null ? null : failure.get().error);
        assertNotNull(result.get());
        assertEquals("PASS", result.get().status);
        assertEquals(2, result.get().plannedCases);
        assertEquals(2, result.get().executedCases);
        assertEquals(2, result.get().passed);
        assertEquals(0, result.get().failed);

        LaboratoryReportStore reports =
            new LaboratoryReportStore(
                app.getFilesDir(), project);
        List<LaboratoryReportStore.Entry> entries =
            reports.list();
        assertEquals(2, entries.size());

        Set<String> names = new HashSet<>();
        Set<String> snapshotIds = new HashSet<>();
        for (LaboratoryReportStore.Entry entry : entries) {
            JSONObject report = new JSONObject(entry.reportText);
            names.add(
                report.getJSONArray("checks")
                    .getJSONObject(0)
                    .getString("name"));
            snapshotIds.add(
                report.getString("candidateSnapshotId"));
            assertFalse(
                entry.reportText.contains("PRIVATE_ALPHA_INPUT"));
            assertFalse(
                entry.reportText.contains("PRIVATE_BETA_INPUT"));
        }

        assertEquals(
            new HashSet<>(Arrays.asList(
                "alpha_roundtrip",
                "beta_roundtrip")),
            names);
        assertEquals(1, snapshotIds.size());
        assertTrue(snapshotIds.contains(result.get().snapshotId));

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(
                app.getFilesDir(), project);
        assertEquals(1, snapshots.listVerified().size());
        assertEquals(
            result.get().candidateSha256,
            snapshots.readCopy(result.get().snapshotId).sha256);
    }

    @Test
    public void stopOnFailurePreventsLaterCandidateCase()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "suitestop" + UUID.randomUUID().toString().substring(0, 8);

        List<LaboratoryCandidateSuiteRunner.TestCase> cases =
            Arrays.asList(
                new LaboratoryCandidateSuiteRunner.TestCase(
                    "must_fail",
                    "actual",
                    "expected",
                    1000),
                new LaboratoryCandidateSuiteRunner.TestCase(
                    "must_not_run",
                    "second",
                    "second",
                    1000));

        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryCandidateSuiteRunner.Result> result =
            new AtomicReference<>();
        AtomicReference<Throwable> failure =
            new AtomicReference<>();

        new Thread(() -> {
            try {
                LaboratoryCandidateSuiteRunner.runInternal(
                    app,
                    project,
                    "return tool_input",
                    cases,
                    88L,
                    true,
                    (suite, error) -> {
                        result.set(suite);
                        failure.set(error);
                        done.countDown();
                    });
            } catch (Throwable error) {
                failure.set(error);
                done.countDown();
            }
        }, "candidate-suite-stop-test").start();

        assertTrue(
            "candidate stop-on-failure suite did not finish",
            done.await(80, TimeUnit.SECONDS));
        if (failure.get() != null) {
            throw new AssertionError(failure.get());
        }

        assertNotNull(result.get());
        assertEquals("FAIL", result.get().status);
        assertEquals(2, result.get().plannedCases);
        assertEquals(1, result.get().executedCases);
        assertEquals(0, result.get().passed);
        assertEquals(1, result.get().failed);
        assertEquals("must_fail", result.get().cases.get(0).name);

        LaboratoryReportStore reports =
            new LaboratoryReportStore(
                app.getFilesDir(), project);
        assertEquals(1, reports.list().size());

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(
                app.getFilesDir(), project);
        assertEquals(1, snapshots.listVerified().size());
    }

    private static final class IOExceptionHolder {
        final Throwable error;

        IOExceptionHolder(Throwable error) {
            this.error = error;
        }
    }
}
