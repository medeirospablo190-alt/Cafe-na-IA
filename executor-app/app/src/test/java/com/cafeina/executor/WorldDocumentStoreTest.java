package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.stream.Stream;

public final class WorldDocumentStoreTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private ProjectStore.Project createProject(String id) throws Exception {
        Path app = temp.newFolder("app-" + id).toPath();
        ProjectStore projects = new ProjectStore(app.resolve("projects"));
        return projects.create(id);
    }

    @Test
    public void savesLoadsAndOverwritesMainWorldAtomically() throws Exception {
        ProjectStore.Project project = createProject("world-test");
        WorldDocumentStore store = new WorldDocumentStore(project);

        assertFalse(store.exists());

        String first = "{\"format\":\"CAFEINA_WORLD\",\"version\":2}";
        store.save(first);

        assertTrue(store.exists());
        assertEquals(first, store.load());
        assertEquals(
            project.worldsDirectory().resolve(WorldDocumentStore.MAIN_WORLD_FILE),
            store.worldFile()
        );

        String second = "{\"format\":\"CAFEINA_WORLD\",\"version\":2,\"nextObjectId\":9}";
        store.save(second);

        assertEquals(second, store.load());

        try (Stream<Path> entries = Files.list(project.worldsDirectory())) {
            assertEquals(
                0,
                entries.filter(path ->
                    path.getFileName().toString().startsWith(
                        "." + WorldDocumentStore.MAIN_WORLD_FILE + ".tmp-"
                    )
                ).count()
            );
        }
    }

    @Test
    public void missingWorldFailsLoad() throws Exception {
        ProjectStore.Project project = createProject("missing");
        WorldDocumentStore store = new WorldDocumentStore(project);

        assertThrows(IOException.class, store::load);
    }

    @Test
    public void nullWorldJsonIsRejected() throws Exception {
        ProjectStore.Project project = createProject("null-json");
        WorldDocumentStore store = new WorldDocumentStore(project);

        assertThrows(IllegalArgumentException.class, () -> store.save(null));
    }

    @Test
    public void symbolicLinkWorldFileIsRejectedWithoutTouchingTarget() throws Exception {
        ProjectStore.Project project = createProject("symlink-file");
        WorldDocumentStore store = new WorldDocumentStore(project);
        Path target = temp.newFile("outside-world.json").toPath();
        Files.write(target, "outside".getBytes(StandardCharsets.UTF_8));

        try {
            Files.createSymbolicLink(store.worldFile(), target);
        } catch (UnsupportedOperationException | IOException unsupported) {
            return;
        }

        assertThrows(IOException.class, () -> store.save("replacement"));
        assertEquals("outside", new String(Files.readAllBytes(target), StandardCharsets.UTF_8));
    }

    @Test
    public void symbolicLinkWorldsDirectoryIsRejected() throws Exception {
        Path real = temp.newFolder("real-worlds").toPath();
        Path link = temp.getRoot().toPath().resolve("linked-worlds");
        try {
            Files.createSymbolicLink(link, real);
        } catch (UnsupportedOperationException | IOException unsupported) {
            return;
        }

        WorldDocumentStore store = new WorldDocumentStore(link);
        assertThrows(IOException.class, () -> store.save("{}"));
        assertThrows(IOException.class, store::exists);
    }

    @Test
    public void oversizedWorldJsonIsRejectedBeforeWrite() throws Exception {
        ProjectStore.Project project = createProject("oversized");
        WorldDocumentStore store = new WorldDocumentStore(project);

        String tooLarge = "x".repeat(WorldDocumentStore.MAX_WORLD_BYTES + 1);

        assertThrows(IOException.class, () -> store.save(tooLarge));
        assertFalse(store.exists());
    }
}
