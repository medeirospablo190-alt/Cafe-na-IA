package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;

public final class EditorTabsTest {
    @Test
    public void startsWithCleanScriptLua() {
        EditorTabs tabs = new EditorTabs("return 1");
        assertEquals(1, tabs.size());
        assertEquals(0, tabs.activeIndex());
        assertEquals("script.lua", tabs.activeName());
        assertEquals("return 1", tabs.activeContent());
        assertFalse(tabs.activeDirty());
    }

    @Test
    public void editingMarksDirtyAndSavingClearsOnlyMatchingSnapshot() {
        EditorTabs tabs = new EditorTabs("return 1");

        tabs.updateActiveContent("return 2");
        assertTrue(tabs.activeDirty());

        tabs.markSaved("script.lua", "return 2");
        assertFalse(tabs.activeDirty());

        tabs.updateActiveContent("return 3");
        tabs.markSaved("script.lua", "return 2");
        assertTrue(tabs.activeDirty());
    }

    @Test
    public void newTabsUseStableNamesAndPreserveContents() {
        EditorTabs tabs = new EditorTabs("first");
        tabs.updateActiveContent("first-edited");

        assertEquals("script1.lua", tabs.addTab());
        assertEquals(1, tabs.activeIndex());
        assertEquals("", tabs.activeContent());
        assertFalse(tabs.activeDirty());

        tabs.updateActiveContent("second");
        assertTrue(tabs.activeDirty());

        tabs.activate(0);
        assertEquals("first-edited", tabs.activeContent());
        assertTrue(tabs.activeDirty());

        tabs.activate(1);
        assertEquals("second", tabs.activeContent());

        assertEquals("script2.lua", tabs.addTab());
        assertEquals(3, tabs.size());
    }

    @Test
    public void newTabSkipsNamesAlreadySavedOnDisk() {
        EditorTabs tabs = new EditorTabs("");
        String created = tabs.addTab(Arrays.asList("script1.lua", "script2.lua"));
        assertEquals("script3.lua", created);
    }

    @Test
    public void loadingNamedScriptIsCleanAndAdvancesGeneratedCounter() {
        EditorTabs tabs = new EditorTabs("");

        int index = tabs.openOrReplace("script5.lua", "return 5");
        assertEquals(index, tabs.activeIndex());
        assertEquals("script5.lua", tabs.activeName());
        assertEquals("return 5", tabs.activeContent());
        assertTrue(tabs.hasName("script5.lua"));
        assertFalse(tabs.activeDirty());

        assertEquals("script6.lua", tabs.addTab());
    }

    @Test
    public void loadingExistingTabReplacesThatTabsContentWithoutDuplicatingIt() {
        EditorTabs tabs = new EditorTabs("draft");
        tabs.updateActiveContent("changed");
        assertTrue(tabs.activeDirty());

        tabs.openOrReplace("script.lua", "saved");

        assertEquals(1, tabs.size());
        assertEquals("script.lua", tabs.activeName());
        assertEquals("saved", tabs.activeContent());
        assertFalse(tabs.activeDirty());
    }

    @Test
    public void closingActiveTabSelectsAValidNeighbor() {
        EditorTabs tabs = new EditorTabs("");
        tabs.addTab();
        tabs.addTab();
        assertEquals("script2.lua", tabs.activeName());

        tabs.close(2);

        assertEquals(2, tabs.size());
        assertEquals("script1.lua", tabs.activeName());
    }

    @Test
    public void closingTabBeforeActiveKeepsSameLogicalTabActive() {
        EditorTabs tabs = new EditorTabs("");
        tabs.addTab();
        tabs.addTab();
        assertEquals("script2.lua", tabs.activeName());

        tabs.close(0);

        assertEquals("script2.lua", tabs.activeName());
        assertEquals(1, tabs.activeIndex());
    }

    @Test
    public void cannotCloseLastTab() {
        EditorTabs tabs = new EditorTabs("");
        assertThrows(IllegalStateException.class, () -> tabs.close(0));
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void invalidTabIndexFailsExplicitly() {
        EditorTabs tabs = new EditorTabs("");
        tabs.activate(5);
    }
}
