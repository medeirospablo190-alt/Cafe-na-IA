package com.cafeina.executor;

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

public final class ProjectSnapshotStoreTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();

    private ProjectStore.Project project(String id) throws Exception {
        ProjectStore store = new ProjectStore(temp.newFolder("app-" + id).toPath().resolve("projects"));
        return store.create(id);
    }

    @Test
    public void snapshotsAreImmutableAndDeterministicallyListed() throws Exception {
        ProjectSnapshotStore store = new ProjectSnapshotStore(project("stable"));
        store.save("b-state", "{\"value\":2}");
        store.save("a-state", "{\"value\":1}");

        assertEquals(Arrays.asList("a-state", "b-state"), store.listSnapshotIds());
        assertEquals("{\"value\":1}", store.load("a-state"));
        assertThrows(IOException.class, () -> store.save("a-state", "{\"value\":9}"));
        assertEquals("{\"value\":1}", store.load("a-state"));
    }

    @Test
    public void rejectsTraversalHiddenUppercaseAndOversizedSnapshots() throws Exception {
        ProjectSnapshotStore store = new ProjectSnapshotStore(project("validation"));
        assertFalse(ProjectSnapshotStore.isValidId("../escape"));
        assertFalse(ProjectSnapshotStore.isValidId(".hidden"));
        assertFalse(ProjectSnapshotStore.isValidId("State"));
        assertTrue(ProjectSnapshotStore.isValidId("checkpoint_01"));
        assertThrows(IllegalArgumentException.class, () -> store.snapshotFile("../escape"));
        String tooLarge = "x".repeat(ProjectSnapshotStore.MAX_SNAPSHOT_BYTES + 1);
        assertThrows(IOException.class, () -> store.save("huge", tooLarge));
        assertTrue(store.listSnapshotIds().isEmpty());
    }

    @Test
    public void symbolicLinkSnapshotIsRejectedWithoutReadingTarget() throws Exception {
        ProjectSnapshotStore store = new ProjectSnapshotStore(project("symlink"));
        Path target = temp.newFile("outside.json").toPath();
        Files.write(target, "outside".getBytes(StandardCharsets.UTF_8));
        Path link = store.snapshotFile("linked");
        try {
            Files.createSymbolicLink(link, target);
        } catch (UnsupportedOperationException | IOException unsupported) {
            return;
        }
        assertThrows(IOException.class, () -> store.load("linked"));
        assertFalse(store.listSnapshotIds().contains("linked"));
    }
}
