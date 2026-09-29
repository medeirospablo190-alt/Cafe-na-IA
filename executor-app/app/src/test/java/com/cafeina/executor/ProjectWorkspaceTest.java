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
import java.nio.file.Path;

public final class ProjectWorkspaceTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    @Test
    public void legacyScriptsStaySeparateFromProjectScriptsAndRuntimeFiles() throws Exception {
        File root = temp.newFolder("cafeina");
        new ProjectStore(root).create("meu-jogo");
        ProjectWorkspace legacy = ProjectWorkspace.open(root, "");
        ProjectWorkspace project = ProjectWorkspace.open(root, "meu-jogo");

        legacy.scriptStore().save("script.lua", "return 11");
        project.scriptStore().save("script.lua", "return 22");
        assertEquals("return 11", legacy.scriptStore().load("script.lua"));
        assertEquals("return 22", project.scriptStore().load("script.lua"));
        assertFalse(legacy.runtimeFilesRoot().equals(project.runtimeFilesRoot()));
        assertEquals("meu-jogo", project.label());
        assertEquals("Scripts antigos", legacy.label());
    }

    @Test
    public void autoExecuteConfigurationIsPerWorkspace() throws Exception {
        File root = temp.newFolder("cafeina");
        new ProjectStore(root).create("um");
        new ProjectStore(root).create("dois");
        ProjectWorkspace one = ProjectWorkspace.open(root, "um");
        ProjectWorkspace two = ProjectWorkspace.open(root, "dois");

        one.scriptStore().save("entry.lua", "return 1");
        one.autoExecuteStore().setEnabled("entry.lua", true);
        assertTrue(one.autoExecuteStore().isEnabled("entry.lua"));
        assertFalse(two.autoExecuteStore().isEnabled("entry.lua"));
        assertFalse(ProjectWorkspace.openLegacy(root).autoExecuteStore().isEnabled("entry.lua"));
    }

    @Test
    public void rejectsMissingAndInvalidProjectWithoutCreatingIt() throws Exception {
        File root = temp.newFolder("cafeina");
        ProjectStore store = new ProjectStore(root);
        assertThrows(IOException.class, () -> ProjectWorkspace.open(root, "missing"));
        assertThrows(IllegalArgumentException.class,
            () -> ProjectWorkspace.open(root, "../not-allowed"));
        assertTrue(store.listProjectIds().isEmpty());
    }
}
