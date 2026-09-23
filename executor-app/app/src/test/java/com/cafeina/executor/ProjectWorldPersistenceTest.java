package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.IOException;
import java.nio.file.Path;

public final class ProjectWorldPersistenceTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private ProjectStore.Project createProject(String id) throws Exception {
        Path app = temp.newFolder("app-" + id).toPath();
        ProjectStore projects = new ProjectStore(app.resolve("projects"));
        return projects.create(id);
    }

    @Test
    public void savesNativeExportIntoProjectWorldFile() throws Exception {
        ProjectStore.Project project = createProject("save-world");
        WorldDocumentStore store = new WorldDocumentStore(project);

        FakeBridge bridge = new FakeBridge();
        bridge.exported = "{\"format\":\"CAFEINA_WORLD\",\"version\":2}";

        ProjectWorldPersistence persistence =
            new ProjectWorldPersistence(store, bridge);

        assertFalse(persistence.hasSavedWorld());

        persistence.saveCurrentWorld();

        assertTrue(persistence.hasSavedWorld());
        assertEquals(bridge.exported, store.load());
        assertEquals(1, bridge.exportCalls);
    }

    @Test
    public void loadsSavedProjectWorldIntoBridge() throws Exception {
        ProjectStore.Project project = createProject("load-world");
        WorldDocumentStore store = new WorldDocumentStore(project);

        String saved = "{\"format\":\"CAFEINA_WORLD\",\"version\":2,\"nextObjectId\":4}";
        store.save(saved);

        FakeBridge bridge = new FakeBridge();
        ProjectWorldPersistence persistence =
            new ProjectWorldPersistence(store, bridge);

        persistence.loadSavedWorld();

        assertEquals(saved, bridge.imported);
        assertEquals(1, bridge.importCalls);
    }

    @Test
    public void nullNativeExportDoesNotCreateWorldFile() throws Exception {
        ProjectStore.Project project = createProject("null-export");
        WorldDocumentStore store = new WorldDocumentStore(project);

        FakeBridge bridge = new FakeBridge();
        bridge.exported = null;

        ProjectWorldPersistence persistence =
            new ProjectWorldPersistence(store, bridge);

        assertThrows(IOException.class, persistence::saveCurrentWorld);
        assertFalse(store.exists());
    }

    private static final class FakeBridge
        implements ProjectWorldPersistence.WorldJsonBridge {

        String exported;
        String imported;
        int exportCalls;
        int importCalls;

        @Override
        public String exportWorldJson() {
            exportCalls++;
            return exported;
        }

        @Override
        public void importWorldJson(String worldJson) {
            importCalls++;
            imported = worldJson;
        }
    }
}
