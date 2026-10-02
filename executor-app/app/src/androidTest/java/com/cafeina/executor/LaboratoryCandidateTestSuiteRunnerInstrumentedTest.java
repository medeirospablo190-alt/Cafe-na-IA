package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryCandidateTestSuiteRunnerInstrumentedTest {
    @Test
    public void isolatedRequiredSuiteProducesLifecycleCompatibleEvidence()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "suite-" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "candidate-suite";
        String version = "1.0.0";
        String source = "return tool_input";
        String artifactSha =
            LaboratoryEngine.fingerprint(source).substring(7, 71);

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(
                app.getFilesDir(), project);
        registry.registerExperimental(
            new LaboratoryToolRegistry.Descriptor(
                toolId,
                version,
                artifactSha,
                "AI_TOOL_WORKSHOP",
                Arrays.asList(
                    LaboratoryStableToolExecutor.REQUIRED_CAPABILITY,
                    "diagnostics"),
                Arrays.asList("echo-a", "echo-b"),
                "cafeina-lab-api-1",
                2000,
                4096));

        LaboratorySnapshotStore.Snapshot snapshot =
            new LaboratorySnapshotStore(
                app.getFilesDir(), project)
                .create(
                    toolId,
                    source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(
            app.getFilesDir(), project)
            .bindLuauSource(
                toolId,
                version,
                snapshot.id);

        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryCandidateTestSuiteRunner.Result>
            resultRef = new AtomicReference<>();
        AtomicReference<Throwable> problem = new AtomicReference<>();

        LaboratoryCandidateTestSuiteRunner.run(
            app,
            project,
            toolId,
            version,
            Arrays.asList(
                new LaboratoryCandidateTestSuiteRunner.TestCase(
                    "echo-a",
                    "alpha",
                    "alpha",
                    11L,
                    1000),
                new LaboratoryCandidateTestSuiteRunner.TestCase(
                    "echo-b",
                    "beta",
                    "beta",
                    12L,
                    1000)),
            new LaboratoryCandidateTestSuiteRunner.Control(),
            null,
            (result, failure) -> {
                resultRef.set(result);
                if (failure != null) problem.set(failure);
                done.countDown();
            });

        assertTrue(
            "candidate suite did not finish",
            done.await(60, TimeUnit.SECONDS));
        if (problem.get() != null) {
            throw new AssertionError(problem.get());
        }

        LaboratoryCandidateTestSuiteRunner.Result result =
            resultRef.get();
        assertNotNull(result);
        assertEquals(
            LaboratoryCandidateTestSuiteRunner.Status.PASS,
            result.status);
        assertTrue(result.qualifiesRequiredEvidence());
        assertEquals(2, result.totalCases);
        assertEquals(2, result.passed);
        assertEquals(0, result.failed);
        assertEquals(2, result.runIds.size());

        assertEquals(
            LaboratoryToolRegistry.Stage.EXPERIMENTAL,
            registry.stage(toolId, version));

        LaboratoryReportStore reports =
            new LaboratoryReportStore(
                app.getFilesDir(), project);
        assertEquals(2, reports.list().size());

        Set<String> snapshotIds = new HashSet<>();
        Set<String> environmentIds = new HashSet<>();
        Set<String> caseNames = new HashSet<>();
        for (LaboratoryReportStore.Entry entry : reports.list()) {
            assertEquals("PASS", entry.status);
            assertFalse(entry.reportText.contains(source));
            assertFalse(entry.reportText.contains("alpha"));
            assertFalse(entry.reportText.contains("beta"));
            assertTrue(entry.reportText.contains(artifactSha));

            JSONObject report = new JSONObject(entry.reportText);
            snapshotIds.add(
                report.getString("candidateSnapshotId"));
            environmentIds.add(
                report.getString("environmentSha256"));
            caseNames.add(
                report.getJSONArray("checks")
                    .getJSONObject(0)
                    .getString("name"));
        }
        assertEquals(
            new HashSet<>(Arrays.asList("echo-a", "echo-b")),
            caseNames);
        assertEquals(1, snapshotIds.size());
        assertTrue(snapshotIds.contains(snapshot.id));
        assertEquals(1, environmentIds.size());
        assertTrue(
            environmentIds.contains(
                LaboratorySandboxEnvironment.fingerprint(app)));
        assertEquals(
            snapshot.id,
            result.snapshotId);
        assertEquals(
            1,
            new LaboratorySnapshotStore(
                app.getFilesDir(), project)
                .listVerified()
                .size());

        registry.qualifyCandidate(
            toolId,
            version,
            result.runIds);

        assertEquals(
            LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(toolId, version));
    }

    @Test
    public void suiteRefusesMissingRequiredTestBeforeExecution()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "suitemiss-" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "candidate-missing";
        String version = "1.0.0";
        String source = "return tool_input";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(
                app.getFilesDir(), project);
        registry.registerExperimental(
            new LaboratoryToolRegistry.Descriptor(
                toolId,
                version,
                LaboratoryEngine.fingerprint(source).substring(7, 71),
                "AI_TOOL_WORKSHOP",
                Arrays.asList(
                    LaboratoryStableToolExecutor.REQUIRED_CAPABILITY,
                    "diagnostics"),
                Arrays.asList("required-a", "required-b"),
                "cafeina-lab-api-1",
                2000,
                4096));
        LaboratorySnapshotStore.Snapshot snapshot =
            new LaboratorySnapshotStore(
                app.getFilesDir(), project)
                .create(
                    toolId,
                    source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(
            app.getFilesDir(), project)
            .bindLuauSource(toolId, version, snapshot.id);

        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Throwable> problem = new AtomicReference<>();
        LaboratoryCandidateTestSuiteRunner.run(
            app,
            project,
            toolId,
            version,
            Arrays.asList(
                new LaboratoryCandidateTestSuiteRunner.TestCase(
                    "required-a",
                    "a",
                    "a",
                    1L,
                    1000)),
            new LaboratoryCandidateTestSuiteRunner.Control(),
            null,
            (result, failure) -> {
                problem.set(failure);
                done.countDown();
            });

        assertTrue(done.await(20, TimeUnit.SECONDS));
        assertNotNull(problem.get());
        assertEquals(
            LaboratoryToolRegistry.Stage.EXPERIMENTAL,
            registry.stage(toolId, version));
        assertEquals(
            0,
            new LaboratoryReportStore(
                app.getFilesDir(), project)
                .list().size());
    }
}
