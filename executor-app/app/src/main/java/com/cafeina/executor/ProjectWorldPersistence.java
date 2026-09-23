package com.cafeina.executor;

import com.cafeina.runtime.LuauBridge;

import java.io.IOException;

public final class ProjectWorldPersistence {
    interface WorldJsonBridge {
        String exportWorldJson();
        void importWorldJson(String worldJson);
    }

    private static final WorldJsonBridge NATIVE_BRIDGE = new WorldJsonBridge() {
        @Override
        public String exportWorldJson() {
            return LuauBridge.nativeExportWorldJson();
        }

        @Override
        public void importWorldJson(String worldJson) {
            LuauBridge.nativeImportWorldJson(worldJson);
        }
    };

    private final WorldDocumentStore store;
    private final WorldJsonBridge bridge;

    public ProjectWorldPersistence(ProjectStore.Project project) {
        this(new WorldDocumentStore(project), NATIVE_BRIDGE);
    }

    ProjectWorldPersistence(
        WorldDocumentStore store,
        WorldJsonBridge bridge
    ) {
        this.store = store;
        this.bridge = bridge;
    }

    public boolean hasSavedWorld() throws IOException {
        return store.exists();
    }

    public void saveCurrentWorld() throws IOException {
        String worldJson = bridge.exportWorldJson();
        if (worldJson == null) {
            throw new IOException("native world export returned null");
        }

        store.save(worldJson);
    }

    public void loadSavedWorld() throws IOException {
        String worldJson = store.load();
        bridge.importWorldJson(worldJson);
    }

    public WorldDocumentStore store() {
        return store;
    }
}
