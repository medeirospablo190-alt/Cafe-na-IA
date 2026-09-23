package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;

public final class AutoExecuteStoreTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    private AutoExecuteStore newStore() throws Exception {
        Path root = temp.newFolder("autoexec").toPath();
        return new AutoExecuteStore(root.resolve("autoexec.list"));
    }

    @Test
    public void startsEmptyAndPersistsExplicitOptIn() throws Exception {
        AutoExecuteStore store = newStore();

        assertTrue(store.enabledScripts().isEmpty());
        assertFalse(store.isEnabled("one.lua"));

        store.setEnabled("one.lua", true);
        store.setEnabled("two.lua", true);

        assertEquals(Arrays.asList("one.lua", "two.lua"), store.enabledScripts());
        assertTrue(new AutoExecuteStore(store.metadataPath()).isEnabled("one.lua"));
    }

    @Test
    public void enablingSameScriptIsIdempotentAndDisableRemovesOnlyThatEntry() throws Exception {
        AutoExecuteStore store = newStore();

        store.setEnabled("one.lua", true);
        store.setEnabled("one.lua", true);
        store.setEnabled("two.lua", true);
        store.setEnabled("one.lua", false);

        assertEquals(Arrays.asList("two.lua"), store.enabledScripts());
    }

    @Test
    public void ignoresInvalidOrDuplicateMetadataLinesWhenReading() throws Exception {
        AutoExecuteStore store = newStore();
        Files.createDirectories(store.metadataPath().getParent());
        Files.write(
            store.metadataPath(),
            Arrays.asList("good.lua", "../bad.lua", "good.lua", "second.lua")
        );

        assertEquals(Arrays.asList("good.lua", "second.lua"), store.enabledScripts());
    }

    @Test
    public void rejectsInvalidNames() throws Exception {
        AutoExecuteStore store = newStore();
        assertThrows(IllegalArgumentException.class, () -> store.setEnabled("../bad.lua", true));
    }

    @Test
    public void enforcesEntryLimitWithoutDroppingExistingEntries() throws Exception {
        AutoExecuteStore store = newStore();

        for (int i = 0; i < AutoExecuteStore.MAX_ENTRIES; i++) {
            store.setEnabled("a" + i + ".lua", true);
        }

        assertEquals(AutoExecuteStore.MAX_ENTRIES, store.enabledScripts().size());
        assertThrows(java.io.IOException.class, () -> store.setEnabled("overflow.lua", true));
        assertEquals(AutoExecuteStore.MAX_ENTRIES, store.enabledScripts().size());
    }
}
