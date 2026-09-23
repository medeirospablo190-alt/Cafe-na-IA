package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.nio.file.Path;

public final class ProjectWorldRecoveryTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();

    private ProjectStore.Project project(String id) throws Exception {
        Path app = temp.newFolder("app-" + id).toPath();
        return new ProjectStore(app.resolve("projects")).create(id);
    }

    @Test
    public void createsSnapshotFromCurrentNativeWorld() throws Exception {
        ProjectStore.Project project = project("snapshot");
        FakeBridge bridge = new FakeBridge();
        bridge.current = "{\"state\":1}";
        ProjectWorldRecovery recovery = new ProjectWorldRecovery(project, bridge);

        recovery.createSnapshot("before-change");

        assertEquals("{\"state\":1}", new ProjectSnapshotStore(project).load("before-change"));
    }

    @Test
    public void restoreUpdatesNativeWorldAndPersistedMainWorld() throws Exception {
        ProjectStore.Project project = project("restore");
        ProjectSnapshotStore snapshots = new ProjectSnapshotStore(project);
        snapshots.save("good", "{\"state\":2}");
        WorldDocumentStore world = new WorldDocumentStore(project);
        world.save("{\"state\":1}");

        FakeBridge bridge = new FakeBridge();
        bridge.current = "{\"state\":1}";
        ProjectWorldRecovery recovery = new ProjectWorldRecovery(world, snapshots, bridge);

        recovery.restoreSnapshot("good");

        assertEquals("{\"state\":2}", bridge.current);
        assertEquals("{\"state\":2}", world.load());
    }

    @Test
    public void invalidSnapshotImportPreservesPreviousNativeAndDiskWorld() throws Exception {
        ProjectStore.Project project = project("rollback");
        ProjectSnapshotStore snapshots = new ProjectSnapshotStore(project);
        snapshots.save("bad", "{\"bad\":true}");
        WorldDocumentStore world = new WorldDocumentStore(project);
        world.save("{\"state\":1}");

        FakeBridge bridge = new FakeBridge();
        bridge.current = "{\"state\":1}";
        bridge.reject = "{\"bad\":true}";
        ProjectWorldRecovery recovery = new ProjectWorldRecovery(world, snapshots, bridge);

        assertThrows(IllegalArgumentException.class, () -> recovery.restoreSnapshot("bad"));

        assertEquals("{\"state\":1}", bridge.current);
        assertEquals("{\"state\":1}", world.load());
    }

    private static final class FakeBridge implements ProjectWorldPersistence.WorldJsonBridge {
        String current;
        String reject;

        @Override public String exportWorldJson() {
            return current;
        }

        @Override public void importWorldJson(String worldJson) {
            if (worldJson.equals(reject)) {
                throw new IllegalArgumentException("invalid world");
            }
            current = worldJson;
        }
    }
}
