package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
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

@RunWith(AndroidJUnit4.class)
public final class LaboratoryToolArtifactStoreInstrumentedTest {
    private static String projectId(String prefix) {
        return prefix + UUID.randomUUID().toString().substring(0, 8);
    }

    private static String sha(String source) {
        String fingerprint = LaboratoryEngine.fingerprint(source);
        return fingerprint.substring("sha256:".length(), "sha256:".length() + 64);
    }

    private static LaboratoryToolRegistry.Descriptor descriptor(
            String toolId, String version, String source) {
        return new LaboratoryToolRegistry.Descriptor(
            toolId, version, sha(source), "AI_TOOL_WORKSHOP",
            Arrays.asList("luau", "diagnostics"),
            Collections.singletonList("artifact"),
            "cafeina-lab-api-1", 2500, 4096);
    }

    private static LaboratoryEngine.Report evidence(
            Context app, String project, String source) throws Exception {
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "artifact", source, LaboratoryEngine.fingerprint(source))));
        return LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), project, request, new LaboratoryEngine.Cancellation());
    }

    @Test
    public void activeStableResolvesExactVerifiedSnapshot() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId("artifact");
        String source = "return 'verified stable tool'";
        String toolId = "verified-tool";
        String version = "0.1.0";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(app.getFilesDir(), project);

        registry.registerExperimental(descriptor(toolId, version, source));
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            "verified-tool", source.getBytes(StandardCharsets.UTF_8));

        LaboratoryToolArtifactStore.Binding binding =
            artifacts.bindLuauSource(toolId, version, snapshot.id);
        assertEquals(snapshot.id, binding.snapshotId);
        assertEquals(sha(source), binding.artifactSha256);
        assertEquals(source, binding.luauSource());
        assertTrue(artifacts.isBound(toolId, version));
        assertThrows(java.io.IOException.class, () ->
            artifacts.bindLuauSource(toolId, version, snapshot.id));

        LaboratoryEngine.Report run = evidence(app, project, source);
        registry.qualifyCandidate(toolId, version, Collections.singletonList(run.runId));
        LaboratoryToolRegistry.ApprovalGate approve =
            (action, id, from, to, approval) -> "user-approved".equals(approval);
        registry.activateStable(toolId, version,
            Collections.singletonList(run.runId), "user-approved", approve);

        LaboratoryToolArtifactStore.Binding active =
            artifacts.readActiveStableVerified(toolId);
        assertEquals(version, active.version);
        assertEquals(source, active.luauSource());
        assertEquals(snapshot.id, active.snapshotId);
    }

    @Test
    public void bindingRejectsWrongHashAndCandidateMutation() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId("freeze");
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(app.getFilesDir(), project);

        String source = "return 'expected'";
        String wrongSource = "return 'wrong'";
        registry.registerExperimental(descriptor("wrong-hash", "0.1.0", source));
        LaboratorySnapshotStore.Snapshot wrong = snapshots.create(
            "wrong-hash", wrongSource.getBytes(StandardCharsets.UTF_8));
        assertThrows(java.io.IOException.class, () ->
            artifacts.bindLuauSource("wrong-hash", "0.1.0", wrong.id));
        assertFalse(artifacts.isBound("wrong-hash", "0.1.0"));

        String frozenTool = "frozen-tool";
        String frozenVersion = "0.2.0";
        registry.registerExperimental(descriptor(frozenTool, frozenVersion, source));
        LaboratoryEngine.Report run = evidence(app, project, source);
        registry.qualifyCandidate(
            frozenTool, frozenVersion, Collections.singletonList(run.runId));
        LaboratorySnapshotStore.Snapshot late = snapshots.create(
            "late-bind", source.getBytes(StandardCharsets.UTF_8));
        assertThrows(java.io.IOException.class, () ->
            artifacts.bindLuauSource(frozenTool, frozenVersion, late.id));
    }

    @Test
    public void verifiedReadFailsIfSnapshotBytesAreAltered() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId("tamper");
        String source = "return 'immutable'";
        String toolId = "tamper-tool";
        String version = "1.0.0";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(app.getFilesDir(), project);

        registry.registerExperimental(descriptor(toolId, version, source));
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            "tamper-tool", source.getBytes(StandardCharsets.UTF_8));
        artifacts.bindLuauSource(toolId, version, snapshot.id);

        Path file = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/snapshots/" + snapshot.id + ".snap");
        byte[] bytes = Files.readAllBytes(file);
        bytes[bytes.length - 1] ^= 0x01;
        Files.write(file, bytes);

        assertThrows(java.io.IOException.class, () ->
            artifacts.readVerified(toolId, version));
    }
}
