package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public final class LaboratoryToolRegistryTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();

    private static LaboratorySnapshotStore.Snapshot baseline(File app, String project,
            String source) throws IOException {
        return new LaboratorySnapshotStore(app, project).create("candidate-luau",
            source.getBytes(StandardCharsets.UTF_8));
    }

    @Test
    public void tracksTwoImmutableVersionsWithoutActivatingEitherOne() throws Exception {
        File app = temp.newFolder("app");
        String scope = "editor-lab";
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(app, scope);
        assertTrue(registry.list().isEmpty());
        LaboratorySnapshotStore.Snapshot first = baseline(app, scope, "return 4");
        LaboratorySnapshotStore.Snapshot second = baseline(app, scope, "return 5");
        LaboratoryToolRegistry.Tool a =
            registry.registerExperimental("geometry-checker", "0.1.0", first.id, 1000);
        LaboratoryToolRegistry.Tool b =
            registry.registerExperimental("geometry-checker", "0.2.0", second.id, 1000);

        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL, a.state);
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL, b.state);
        assertEquals("LUAU_ISOLATED_NO_FILES", a.capability);
        assertEquals(first.sha256, registry.read("geometry-checker", "0.1.0").sourceSha256);
        assertEquals(second.sha256, registry.read("geometry-checker", "0.2.0").sourceSha256);
        assertEquals(64, a.manifestSha256.length());
        assertEquals(2, registry.list().size());
        assertThrows(IOException.class,
            () -> registry.registerExperimental("geometry-checker", "0.1.0", first.id, 1000));
        assertEquals(first.sha256, registry.read("geometry-checker", "0.1.0").sourceSha256);
        assertEquals(2, registry.list().size());
        assertEquals(2, LaboratoryToolRegistry.State.values().length);
    }

    @Test
    public void eachProjectSeesOnlyItsOwnVersionsAndSnapshots() throws Exception {
        File app = temp.newFolder("app");
        LaboratorySnapshotStore.Snapshot snapshot = baseline(app, "first", "return 7");
        LaboratoryToolRegistry mine = new LaboratoryToolRegistry(app, "first");
        LaboratoryToolRegistry other = new LaboratoryToolRegistry(app, "second");
        mine.registerExperimental("private-tool", "0.0.1", snapshot.id, 1000);
        assertTrue(other.list().isEmpty());
        assertThrows(IOException.class, () -> other.read("private-tool", "0.0.1"));
        assertEquals(1, mine.list().size());
    }

    @Test
    public void refusesTraversalInvalidVersionsAndNonCandidateSnapshots() throws Exception {
        File app = temp.newFolder("app");
        assertThrows(IllegalArgumentException.class,
            () -> new LaboratoryToolRegistry(app, "../user"));
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(app, "safe");
        LaboratorySnapshotStore.Snapshot snap = baseline(app, "safe", "return 1");
        assertThrows(IllegalArgumentException.class,
            () -> registry.registerExperimental("../escape", "0.0.1", snap.id, 1000));
        assertThrows(IllegalArgumentException.class,
            () -> registry.registerExperimental("test-tool", "1.0.0/../", snap.id, 1000));
        assertThrows(IllegalArgumentException.class,
            () -> registry.registerExperimental("test-tool", "1.0.0", snap.id, 3001));
        LaboratorySnapshotStore.Snapshot unrelated =
            new LaboratorySnapshotStore(app, "safe").create("unrelated",
                "return 1".getBytes(StandardCharsets.UTF_8));
        assertThrows(IOException.class,
            () -> registry.registerExperimental("test-tool", "1.0.0", unrelated.id, 1000));
        assertTrue(registry.list().isEmpty());
    }

    @Test
    public void modifiedManifestFailsClosedAndDoesNotEraseTheSnapshot() throws Exception {
        File app = temp.newFolder("app");
        String scope = "verify";
        LaboratorySnapshotStore.Snapshot snapshot = baseline(app, scope, "return 9");
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(app, scope);
        registry.registerExperimental("stored-tool", "1.0.0", snapshot.id, 500);
        Path manifest = app.toPath().resolve(
            "laboratory/project-verify/tools/manifests/stored-tool@1.0.0.tool");
        byte[] bytes = Files.readAllBytes(manifest);
        bytes[bytes.length - 2] = bytes[bytes.length - 2] == 'a' ? (byte) 'b' : (byte) 'a';
        Files.write(manifest, bytes);
        assertThrows(IOException.class, () -> registry.read("stored-tool", "1.0.0"));
        assertThrows(IOException.class, registry::list);
        assertTrue(Files.exists(manifest));
        assertEquals(snapshot.sha256,
            new LaboratorySnapshotStore(app, scope).readCopy(snapshot.id).sha256);
    }

    @Test
    public void tamperedSnapshotBlocksAnOtherwiseValidTool() throws Exception {
        File app = temp.newFolder("app");
        LaboratorySnapshotStore.Snapshot snapshot = baseline(app, "tamper", "return 21");
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(app, "tamper");
        registry.registerExperimental("replay-tool", "2.0.0", snapshot.id, 1000);
        Path source = app.toPath().resolve(
            "laboratory/project-tamper/snapshots/" + snapshot.id + ".snap");
        byte[] altered = Files.readAllBytes(source);
        altered[altered.length - 1] ^= 1;
        Files.write(source, altered);
        assertThrows(IOException.class,
            () -> registry.read("replay-tool", "2.0.0"));
        assertThrows(IOException.class, registry::list);
    }

    @Test
    public void reportMustBeGenuineBeforeReviewAndStableIsNotAvailable() throws Exception {
        File app = temp.newFolder("app");
        LaboratorySnapshotStore.Snapshot snapshot = baseline(app, "review", "return 42");
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(app, "review");
        registry.registerExperimental("diagnostic-tool", "0.1.0", snapshot.id, 500);
        assertThrows(IOException.class, () -> registry.requestCandidateReview(
            "diagnostic-tool", "0.1.0", java.util.UUID.randomUUID().toString()));
        assertEquals(LaboratoryToolRegistry.State.EXPERIMENTAL,
            registry.read("diagnostic-tool", "0.1.0").state);
        assertEquals(0, registry.list().stream()
            .filter(t -> t.state == LaboratoryToolRegistry.State.CANDIDATE).count());
    }
}
