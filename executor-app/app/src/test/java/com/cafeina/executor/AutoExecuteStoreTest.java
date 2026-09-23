package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.nio.file.Path;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Set;

public final class AutoExecuteStoreTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private AutoExecuteStore newStore() throws Exception {
        Path root = temp.newFolder("auto").toPath();
        return new AutoExecuteStore(root.resolve("autoexecute.txt"));
    }

    @Test
    public void emptyStoreStartsDisabled() throws Exception {
        AutoExecuteStore store = newStore();
        assertTrue(store.load().isEmpty());
    }

    @Test
    public void persistsOnlyExplicitlyEnabledScripts() throws Exception {
        AutoExecuteStore store = newStore();
        Set<String> enabled = new LinkedHashSet<>(Arrays.asList("script.lua", "farm.lua"));

        store.save(enabled);
        Set<String> reloaded = store.load();

        assertEquals(enabled, reloaded);
        assertTrue(reloaded.contains("script.lua"));
        assertFalse(reloaded.contains("other.lua"));
    }

    @Test
    public void disablingEverythingPersistsEmptySet() throws Exception {
        AutoExecuteStore store = newStore();
        store.save(new LinkedHashSet<>(Arrays.asList("a.lua")));
        store.save(new LinkedHashSet<>());

        assertTrue(store.load().isEmpty());
    }

    @Test
    public void rejectsInvalidNames() throws Exception {
        AutoExecuteStore store = newStore();
        Set<String> invalid = new LinkedHashSet<>(Arrays.asList("../escape.lua"));

        assertThrows(IllegalArgumentException.class, () -> store.save(invalid));
    }
}
