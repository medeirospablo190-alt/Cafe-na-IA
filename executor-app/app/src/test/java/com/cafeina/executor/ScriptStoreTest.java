package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;

public final class ScriptStoreTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private ScriptStore newStore() throws Exception {
        return new ScriptStore(temp.newFolder("app").toPath().resolve("scripts"));
    }

    @Test
    public void savesLoadsAndOverwritesUtf8() throws Exception {
        ScriptStore store = newStore();

        store.save("script.lua", "print('olá')");
        assertEquals("print('olá')", store.load("script.lua"));

        store.save("script.lua", "return 42");
        assertEquals("return 42", store.load("script.lua"));
    }

    @Test
    public void secondInstanceReadsSameSavedFileLikeRestart() throws Exception {
        Path scripts = temp.newFolder("restart").toPath().resolve("scripts");

        new ScriptStore(scripts).save("persist.lua", "return 'persistiu'");
        ScriptStore afterRestart = new ScriptStore(scripts);

        assertTrue(afterRestart.exists("persist.lua"));
        assertEquals("return 'persistiu'", afterRestart.load("persist.lua"));
    }

    @Test
    public void listIsSortedAndIgnoresNonScriptsAndTempFiles() throws Exception {
        ScriptStore store = newStore();
        store.save("z.lua", "z");
        store.save("A.lua", "a");
        store.save("middle.lua", "m");

        Files.write(store.directory().resolve("notes.txt"), "x".getBytes(StandardCharsets.UTF_8));
        Files.write(store.directory().resolve(".middle.lua.tmp-test"), "partial".getBytes(StandardCharsets.UTF_8));

        assertEquals(Arrays.asList("A.lua", "middle.lua", "z.lua"), store.listScripts());
    }

    @Test
    public void rejectsTraversalAndInvalidNames() throws Exception {
        ScriptStore store = newStore();

        assertFalse(ScriptStore.isValidName("../escape.lua"));
        assertFalse(ScriptStore.isValidName("folder/test.lua"));
        assertFalse(ScriptStore.isValidName("test.LUA"));
        assertFalse(ScriptStore.isValidName(".hidden.lua"));
        assertFalse(ScriptStore.isValidName(" test.lua"));

        assertThrows(IllegalArgumentException.class, () -> store.save("../escape.lua", "bad"));
    }

    @Test
    public void rejectedOversizeWriteDoesNotReplaceExistingScript() throws Exception {
        ScriptStore store = newStore();
        store.save("safe.lua", "return 1");

        String tooLarge = "x".repeat(ScriptStore.MAX_SCRIPT_BYTES + 1);
        assertThrows(IllegalArgumentException.class, () -> store.save("safe.lua", tooLarge));

        assertEquals("return 1", store.load("safe.lua"));
    }

    @Test
    public void missingScriptFailsExplicitly() throws Exception {
        ScriptStore store = newStore();
        assertThrows(java.io.IOException.class, () -> store.load("missing.lua"));
    }
}
