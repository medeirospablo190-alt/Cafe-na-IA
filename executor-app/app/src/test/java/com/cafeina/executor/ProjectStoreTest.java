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
import java.nio.file.Path;
import java.util.Arrays;

public final class ProjectStoreTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private ProjectStore newStore() throws Exception {
        return new ProjectStore(temp.newFolder("app").toPath().resolve("projects"));
    }

    @Test
    public void createsStableProjectLayoutAndReopensIt() throws Exception {
        ProjectStore store = newStore();

        ProjectStore.Project created = store.create("movement-lab");
        assertEquals("movement-lab", created.id());
        assertTrue(Files.isDirectory(created.scriptsDirectory()));
        assertTrue(Files.isDirectory(created.runtimeFilesDirectory()));
        assertTrue(Files.isDirectory(created.worldsDirectory()));
        assertTrue(Files.isDirectory(created.assetsDirectory()));
        assertTrue(Files.isDirectory(created.snapshotsDirectory()));

        ProjectStore.Project reopened = store.open("movement-lab");
        assertEquals(created.root(), reopened.root());
        assertTrue(store.exists("movement-lab"));
    }

    @Test
    public void listOnlyReturnsCompleteCafeinaProjects() throws Exception {
        ProjectStore store = newStore();
        store.create("z-project");
        store.create("a-project");

        Files.createDirectories(store.projectsDirectory().resolve("foreign-folder"));
        Files.createDirectories(store.projectsDirectory().resolve("broken-project").resolve("scripts"));

        assertEquals(
            Arrays.asList("a-project", "z-project"),
            store.listProjectIds()
        );
    }

    @Test
    public void rejectsTraversalUppercaseWhitespaceAndHiddenIds() throws Exception {
        ProjectStore store = newStore();

        assertFalse(ProjectStore.isValidId("../escape"));
        assertFalse(ProjectStore.isValidId("folder/project"));
        assertFalse(ProjectStore.isValidId("Project"));
        assertFalse(ProjectStore.isValidId("two words"));
        assertFalse(ProjectStore.isValidId(".hidden"));
        assertTrue(ProjectStore.isValidId("project_01"));

        assertThrows(
            IllegalArgumentException.class,
            () -> store.create("../escape")
        );
    }

    @Test
    public void duplicateProjectCreationFailsWithoutChangingExistingProject() throws Exception {
        ProjectStore store = newStore();
        ProjectStore.Project project = store.create("stable");

        Files.write(project.scriptsDirectory().resolve("keep.lua"), "return 1".getBytes());

        assertThrows(IOException.class, () -> store.create("stable"));
        assertTrue(Files.isRegularFile(project.scriptsDirectory().resolve("keep.lua")));
        assertTrue(store.exists("stable"));
    }

    @Test
    public void incompleteProjectFailsOpenAndIsNotListed() throws Exception {
        ProjectStore store = newStore();
        ProjectStore.Project project = store.create("incomplete");

        Files.delete(project.worldsDirectory());

        assertFalse(store.exists("incomplete"));
        assertThrows(IOException.class, () -> store.open("incomplete"));
        assertTrue(store.listProjectIds().isEmpty());
    }

    @Test
    public void foreignProjectMarkerVersionFailsClosed() throws Exception {
        ProjectStore store = newStore();
        ProjectStore.Project project = store.create("versioned");

        Files.write(
            project.root().resolve(".cafeina-project"),
            "CAFEINA_PROJECT\n999\n".getBytes()
        );

        assertFalse(store.exists("versioned"));
        assertThrows(IOException.class, () -> store.open("versioned"));
    }
}
