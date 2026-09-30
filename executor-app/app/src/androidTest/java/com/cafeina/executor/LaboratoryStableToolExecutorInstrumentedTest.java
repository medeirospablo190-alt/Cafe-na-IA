package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

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
public final class LaboratoryStableToolExecutorInstrumentedTest {
    private static final class Outcome {
        LaboratoryStableToolExecutor.Execution execution;
        Throwable error;
    }

    @Test
    public void stableGateUsesOnlyVerifiedActiveArtifactAndAuditsHashes() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "stableuse" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "echo-tool";
        String version = "1.0.0";
        String source =
            "if tool_input == 'bad private input' then error('secret runtime error') end "
            + "return tool_input .. ':ok'";
        String privateInput = "hello private stable input";

        prepareStable(app, project, toolId, version, source);

        Outcome good = execute(app, project, toolId, privateInput);
        if (good.error != null) throw new AssertionError(good.error);
        assertNotNull(good.execution);
        assertEquals(privateInput + ":ok", good.execution.firstReturn);
        assertEquals(toolId, good.execution.toolId);
        assertEquals(version, good.execution.toolVersion);
        assertTrue(good.execution.audit.usable);
        assertTrue(good.execution.audit.selectionVerified);
        assertEquals("EXECUTED", good.execution.audit.workerStatus);
        assertEquals(good.execution.audit.artifactSha256,
            good.execution.audit.executedSourceSha256);
        assertEquals(good.execution.audit.inputSha256,
            good.execution.audit.executedInputSha256);

        LaboratoryStableUseStore uses =
            new LaboratoryStableUseStore(app.getFilesDir(), project);
        assertEquals(1, uses.list().size());
        LaboratoryStableUseStore.Use saved = uses.read(good.execution.runId);
        assertTrue(saved.usable);

        Path receipt = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/stable-tool-uses/"
                + good.execution.runId + ".json");
        String raw = new String(Files.readAllBytes(receipt), StandardCharsets.UTF_8);
        assertFalse(raw.contains(privateInput));
        assertFalse(raw.contains(privateInput + ":ok"));
        assertFalse(raw.contains(source));

        Outcome bad = execute(app, project, toolId, "bad private input");
        assertNull(bad.execution);
        assertNotNull(bad.error);
        assertTrue(bad.error.getMessage().contains("LUAU_ERROR"));
        assertEquals(2, uses.list().size());

        LaboratoryStableUseStore.Use failed = uses.list().stream()
            .filter(value -> !value.runId.equals(saved.runId))
            .findFirst().get();
        assertFalse(failed.usable);
        assertTrue(failed.selectionVerified);
        assertEquals("LUAU_ERROR", failed.workerStatus);

        Path failedReceipt = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/stable-tool-uses/"
                + failed.runId + ".json");
        String failedRaw = new String(
            Files.readAllBytes(failedReceipt), StandardCharsets.UTF_8);
        assertFalse(failedRaw.contains("bad private input"));
        assertFalse(failedRaw.contains("secret runtime error"));
        assertFalse(failedRaw.contains(source));
    }

    @Test
    public void experimentalToolCannotUseStableExecutionGate() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "denieduse" + UUID.randomUUID().toString().substring(0, 8);
        String source = "return tool_input";
        String toolId = "experimental-tool";
        String version = "0.1.0";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        registry.registerExperimental(descriptor(toolId, version, source));
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            "experimental-tool", source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(app.getFilesDir(), project)
            .bindLuauSource(toolId, version, snapshot.id);

        Outcome denied = execute(app, project, toolId, "must-not-run");
        assertNull(denied.execution);
        assertNotNull(denied.error);
        assertTrue(denied.error.getMessage().contains("no active STABLE"));
        assertTrue(new LaboratoryStableUseStore(app.getFilesDir(), project)
            .list().isEmpty());
    }

    @Test
    public void stableToolWithoutExecutionCapabilityIsRejected() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "capdeny" + UUID.randomUUID().toString().substring(0, 8);
        String source = "return tool_input";
        String toolId = "nonexec-tool";
        String version = "1.0.0";

        prepareStable(app, project, toolId, version, source,
            Collections.singletonList("diagnostics"));

        Outcome denied = execute(app, project, toolId, "must-not-run");
        assertNull(denied.execution);
        assertNotNull(denied.error);
        assertTrue(denied.error.getMessage().contains("lacks isolated execution capability"));
        assertTrue(new LaboratoryStableUseStore(app.getFilesDir(), project)
            .list().isEmpty());
    }

    private static void prepareStable(Context app, String project, String toolId,
            String version, String source) throws Exception {
        prepareStable(app, project, toolId, version, source,
            Arrays.asList(LaboratoryStableToolExecutor.REQUIRED_CAPABILITY, "diagnostics"));
    }

    private static void prepareStable(Context app, String project, String toolId,
            String version, String source, java.util.List<String> capabilities)
            throws Exception {
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        registry.registerExperimental(new LaboratoryToolRegistry.Descriptor(
            toolId, version, sha(source), "AI_TOOL_WORKSHOP",
            capabilities, Collections.singletonList("artifact"),
            "cafeina-lab-api-1", 1000, 4096));

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
        LaboratoryEngine.Report report = LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), project, request, new LaboratoryEngine.Cancellation());

        registry.qualifyCandidate(
            toolId, version, Collections.singletonList(report.runId));
        LaboratoryToolRegistry.ApprovalGate approval =
            (action, id, from, to, approvalId) ->
                "ACTIVATE_STABLE".equals(action)
                    && "test-user-approval".equals(approvalId);
        registry.activateStable(toolId, version,
            Collections.singletonList(report.runId),
            "test-user-approval", approval);
    }

    private static Outcome execute(Context app, String project,
            String toolId, String input) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Outcome> reference = new AtomicReference<>();
        new Thread(() -> {
            Outcome outcome = new Outcome();
            try {
                LaboratoryStableToolExecutor.executeInternal(
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
        }, "stable-tool-test").start();

        assertTrue("STABLE tool execution timed out",
            done.await(40, TimeUnit.SECONDS));
        assertNotNull(reference.get());
        return reference.get();
    }

    private static String sha(String source) {
        return LaboratoryEngine.fingerprint(source).substring(7, 71);
    }

    private static LaboratoryToolRegistry.Descriptor descriptor(
            String toolId, String version, String source) {
        return new LaboratoryToolRegistry.Descriptor(
            toolId, version, sha(source), "AI_TOOL_WORKSHOP",
            Arrays.asList(LaboratoryStableToolExecutor.REQUIRED_CAPABILITY, "diagnostics"),
            Collections.singletonList("artifact"),
            "cafeina-lab-api-1", 1000, 4096);
    }
}
