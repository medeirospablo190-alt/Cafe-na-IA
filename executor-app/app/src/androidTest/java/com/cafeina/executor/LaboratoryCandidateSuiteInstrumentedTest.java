package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryCandidateSuiteInstrumentedTest {
    private static String project(String prefix) {
        return prefix + "-" + UUID.randomUUID().toString().substring(0, 8);
    }

    private static LaboratoryToolRegistry.Tool register(Context app, String projectId,
            String toolId, String version, String source, int timeoutMs) throws Exception {
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), projectId);
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            "candidate-luau", source.getBytes(StandardCharsets.UTF_8));
        return new LaboratoryToolRegistry(app.getFilesDir(), projectId)
            .registerExperimental(toolId, version, snapshot.id, timeoutMs);
    }

    @Test
    public void sameCandidateRunsMultiplePrivateInputsWithoutChangingSource() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String scope = project("candidate-batch");
        String source = "return string.upper(tool_input)";
        LaboratoryToolRegistry.Tool tool = register(
            app, scope, "text-transform", "0.1.0", source, 1000);

        LaboratoryCandidateSuiteRunner.Plan plan =
            new LaboratoryCandidateSuiteRunner.Plan(
                tool.id, tool.version, 20260930L,
                Arrays.asList(
                    new LaboratoryCandidateSuiteRunner.Case(
                        "hello-case", "hello private input", "HELLO PRIVATE INPUT"),
                    new LaboratoryCandidateSuiteRunner.Case(
                        "world-case", "world private input", "WORLD PRIVATE INPUT")
                ));
        LaboratoryCandidateSuiteStore.Summary result = run(
            app, scope, plan, new LaboratoryEngine.Cancellation());

        assertEquals(LaboratoryCandidateSuiteStore.Status.PASS, result.status);
        assertEquals(2, result.passed);
        assertEquals(0, result.failed);
        assertEquals(2, result.reportIds.size());
        assertEquals(tool.sourceSha256, result.sourceSha256);
        assertEquals(tool.snapshotId, result.snapshotId);
        assertEquals(plan.planSha256, result.planSha256);

        LaboratoryReportStore reports =
            new LaboratoryReportStore(app.getFilesDir(), scope);
        String firstRaw = reports.read(result.reportIds.get(0));
        String secondRaw = reports.read(result.reportIds.get(1));
        assertFalse(firstRaw.contains("hello private input"));
        assertFalse(secondRaw.contains("world private input"));
        assertFalse(firstRaw.contains(source));
        assertFalse(secondRaw.contains(source));

        JSONObject first = new JSONObject(firstRaw);
        JSONObject second = new JSONObject(secondRaw);
        assertEquals("PASS", first.getString("status"));
        assertEquals("PASS", second.getString("status"));
        assertEquals(tool.sourceSha256, first.getString("candidateBatchSha256"));
        assertEquals(tool.sourceSha256, second.getString("candidateBatchSha256"));
        assertEquals(
            LaboratoryEngine.fingerprint("hello private input").substring(7, 71),
            first.getString("toolInputSha256"));
        assertEquals(
            LaboratoryEngine.fingerprint("world private input").substring(7, 71),
            second.getString("toolInputSha256"));

        // A passing suite is evidence only; it does not promote the tool.
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), scope);
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL,
            registry.read(tool.id, tool.version).state);
        assertEquals(1,
            new LaboratoryCandidateSuiteStore(app.getFilesDir(), scope).list().size());
        assertTrue(new LaboratoryCandidateSuiteStore(app.getFilesDir(),
            project("unrelated")).list().isEmpty());

        LaboratoryCandidateSuiteStore.Summary failure = run(
            app, scope, new LaboratoryCandidateSuiteRunner.Plan(
                tool.id, tool.version, 20260930L,
                Collections.singletonList(
                    new LaboratoryCandidateSuiteRunner.Case(
                        "wrong-case", "hello private input", "WRONG"))),
            new LaboratoryEngine.Cancellation());
        assertEquals(LaboratoryCandidateSuiteStore.Status.FAIL, failure.status);
        assertEquals(0, failure.passed);
        assertEquals(1, failure.failed);
        assertEquals("CASE_MISMATCH", failure.reason);
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL,
            registry.read(tool.id, tool.version).state);
    }

    @Test
    public void cancellationAndTamperedSuiteEvidenceNeverBecomePass() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String scope = project("candidate-cancel");
        LaboratoryToolRegistry.Tool tool = register(
            app, scope, "cancel-tool", "0.1.0", "return tool_input", 1000);
        LaboratoryCandidateSuiteRunner.Plan plan =
            new LaboratoryCandidateSuiteRunner.Plan(
                tool.id, tool.version, 1,
                Collections.singletonList(
                    new LaboratoryCandidateSuiteRunner.Case("case", "x", "x")));

        LaboratoryEngine.Cancellation cancellation = new LaboratoryEngine.Cancellation();
        cancellation.cancel();
        LaboratoryCandidateSuiteStore.Summary cancelled =
            run(app, scope, plan, cancellation);
        assertEquals(LaboratoryCandidateSuiteStore.Status.CANCELLED, cancelled.status);
        assertTrue(cancelled.reportIds.isEmpty());

        LaboratoryCandidateSuiteStore.Summary passed =
            run(app, scope, plan, new LaboratoryEngine.Cancellation());
        assertEquals(LaboratoryCandidateSuiteStore.Status.PASS, passed.status);

        Path done = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + scope + "/candidate-suites/"
                + passed.suiteId + ".done");
        byte[] bytes = Files.readAllBytes(done);
        bytes[bytes.length - 2] ^= 1;
        Files.write(done, bytes);
        LaboratoryCandidateSuiteStore store =
            new LaboratoryCandidateSuiteStore(app.getFilesDir(), scope);
        assertThrows(IOException.class, () -> store.read(passed.suiteId));
        assertThrows(IOException.class, store::list);
        assertTrue(Files.exists(done));
    }

    private static LaboratoryCandidateSuiteStore.Summary run(Context app,
            String projectId, LaboratoryCandidateSuiteRunner.Plan plan,
            LaboratoryEngine.Cancellation cancellation) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryCandidateSuiteStore.Summary> result =
            new AtomicReference<>();
        AtomicReference<Throwable> error = new AtomicReference<>();
        new Thread(() -> {
            try {
                result.set(LaboratoryCandidateSuiteRunner.runInternal(
                    app, projectId, plan, cancellation));
            } catch (Throwable failure) {
                error.set(failure);
            } finally {
                done.countDown();
            }
        }, "candidate-suite-test").start();

        assertTrue("Candidate suite did not finish",
            done.await(60, TimeUnit.SECONDS));
        if (error.get() != null) throw new AssertionError(error.get());
        return result.get();
    }
}
