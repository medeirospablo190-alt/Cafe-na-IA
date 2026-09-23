package com.cafeina.executor;

import java.io.IOException;

public final class ProjectWorldRecovery {
    private final WorldDocumentStore worldStore;
    private final ProjectSnapshotStore snapshotStore;
    private final ProjectWorldPersistence.WorldJsonBridge bridge;

    public ProjectWorldRecovery(
        ProjectStore.Project project,
        ProjectWorldPersistence.WorldJsonBridge bridge
    ) {
        this(new WorldDocumentStore(project), new ProjectSnapshotStore(project), bridge);
    }

    ProjectWorldRecovery(
        WorldDocumentStore worldStore,
        ProjectSnapshotStore snapshotStore,
        ProjectWorldPersistence.WorldJsonBridge bridge
    ) {
        this.worldStore = worldStore;
        this.snapshotStore = snapshotStore;
        this.bridge = bridge;
    }

    public void createSnapshot(String snapshotId) throws IOException {
        String worldJson = bridge.exportWorldJson();
        if (worldJson == null) {
            throw new IOException("native world export returned null");
        }
        snapshotStore.save(snapshotId, worldJson);
    }

    public void restoreSnapshot(String snapshotId) throws IOException {
        String candidate = snapshotStore.load(snapshotId);
        String previous = bridge.exportWorldJson();
        if (previous == null) {
            throw new IOException("native world export returned null");
        }

        try {
            bridge.importWorldJson(candidate);
            worldStore.save(candidate);
        } catch (RuntimeException | IOException failure) {
            try {
                bridge.importWorldJson(previous);
            } catch (RuntimeException rollbackFailure) {
                failure.addSuppressed(rollbackFailure);
            }
            throw failure;
        }
    }
}
