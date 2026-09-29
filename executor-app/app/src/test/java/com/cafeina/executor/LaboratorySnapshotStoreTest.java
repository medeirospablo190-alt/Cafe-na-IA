package com.cafeina.executor;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;

public final class LaboratorySnapshotStoreTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    @Test
    public void snapshotIsImmutableAndRecoveryReturnsIndependentCopy() throws Exception {
        LaboratorySnapshotStore store =
            new LaboratorySnapshotStore(temp.newFolder("app"), "my-project");
        byte[] original = "return 42\n".getBytes(StandardCharsets.UTF_8);
        byte[] expected = original.clone();
        LaboratorySnapshotStore.Snapshot created = store.create("candidate-luau", original);
        original[0] = 'X';

        assertArrayEquals(expected, created.contentCopy());
        assertEquals(LaboratoryEngine.fingerprint("return 42\n").substring(7, 71),
            created.sha256);
        byte[] recovered = store.readCopy(created.id).contentCopy();
        recovered[1] = 'Y';
        assertArrayEquals(expected, store.readCopy(created.id).contentCopy());
        assertEquals(1, store.listVerified().size());
        assertEquals(created.id, store.listVerified().get(0).id);
    }

    @Test
    public void snapshotsDoNotTouchOriginalProjectScriptsOrRuntimeFiles() throws Exception {
        java.io.File app = temp.newFolder("app");
        Path project = app.toPath().resolve("projects").resolve("my-project");
        Files.createDirectories(project.resolve("scripts"));
        Files.createDirectories(project.resolve("runtime-fs"));
        Path script = project.resolve("scripts").resolve("keep.lua");
        Path runtime = project.resolve("runtime-fs").resolve("keep.txt");
        Files.write(script, "keep original".getBytes(StandardCharsets.UTF_8));
        Files.write(runtime, "keep runtime".getBytes(StandardCharsets.UTF_8));

        LaboratorySnapshotStore mine = new LaboratorySnapshotStore(app, "my-project");
        LaboratorySnapshotStore other = new LaboratorySnapshotStore(app, "other-project");
        LaboratorySnapshotStore.Snapshot snapshot = mine.create("test-only",
            "unrelated test content".getBytes(StandardCharsets.UTF_8));
        assertTrue(other.listVerified().isEmpty());
        assertThrows(IOException.class, () -> other.readCopy(snapshot.id));
        assertEquals("keep original", new String(Files.readAllBytes(script),
            StandardCharsets.UTF_8));
        assertEquals("keep runtime", new String(Files.readAllBytes(runtime),
            StandardCharsets.UTF_8));
        assertEquals("unrelated test content",
            new String(mine.readCopy(snapshot.id).contentCopy(), StandardCharsets.UTF_8));
    }

    @Test
    public void corruptedAndLinkedSnapshotsFailClosedWithoutDeletingEvidence() throws Exception {
        java.io.File app = temp.newFolder("app");
        LaboratorySnapshotStore store = new LaboratorySnapshotStore(app, "");
        LaboratorySnapshotStore.Snapshot created = store.create("fixture",
            "safe bytes".getBytes(StandardCharsets.UTF_8));
        Path storage = app.toPath().resolve("laboratory/legacy/snapshots");
        Path file = storage.resolve(created.id + ".snap");
        byte[] tampered = Files.readAllBytes(file);
        tampered[tampered.length - 1] ^= 1;
        Files.write(file, tampered);
        assertThrows(IOException.class, () -> store.readCopy(created.id));
        assertThrows(IOException.class, store::listVerified);
        assertTrue("Corrupted original evidence must not be silently discarded",
            Files.exists(file));

        Path other = temp.newFile("outside").toPath();
        Files.delete(file);
        Files.createSymbolicLink(file, other);
        assertThrows(IOException.class, () -> store.readCopy(created.id));
        assertThrows(IOException.class, () ->
            store.create("another", "data".getBytes(StandardCharsets.UTF_8)));
        assertTrue(Files.exists(other));
    }

    @Test
    public void rejectsInvalidInputsTraversalAndOversize() throws Exception {
        java.io.File app = temp.newFolder("app");
        assertThrows(IllegalArgumentException.class,
            () -> new LaboratorySnapshotStore(app, "../other"));
        LaboratorySnapshotStore store = new LaboratorySnapshotStore(app, "valid");
        assertThrows(IllegalArgumentException.class,
            () -> store.create("../evil", new byte[]{1}));
        assertThrows(IllegalArgumentException.class,
            () -> store.create("fixture", new byte[0]));
        assertThrows(IllegalArgumentException.class,
            () -> store.create("fixture", new byte[LaboratorySnapshotStore.MAX_CONTENT_BYTES + 1]));
        assertThrows(IOException.class, () -> store.readCopy("../../runtime-fs"));
        assertTrue(store.listVerified().isEmpty());
    }

    @Test
    public void fullVaultRefusesNewDataInsteadOfDeletingOldSnapshots() throws Exception {
        LaboratorySnapshotStore store =
            new LaboratorySnapshotStore(temp.newFolder("app"), "quota");
        String first = null;
        for (int index = 0; index < LaboratorySnapshotStore.MAX_SNAPSHOTS; index++) {
            LaboratorySnapshotStore.Snapshot created =
                store.create("fixture", new byte[]{(byte) index});
            if (index == 0) first = created.id;
        }
        assertEquals(LaboratorySnapshotStore.MAX_SNAPSHOTS, store.listVerified().size());
        assertThrows(IOException.class, () -> store.create("overflow", new byte[]{9}));
        assertTrue(LaboratorySnapshotStore.validId(first));
        assertArrayEquals(new byte[]{0}, store.readCopy(first).contentCopy());
        assertEquals(LaboratorySnapshotStore.MAX_SNAPSHOTS, store.listVerified().size());
    }
}
