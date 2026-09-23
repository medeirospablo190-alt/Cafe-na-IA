package com.cafeina.executor;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class EditorTabsTest {
    @Test
    public void startsWithScriptLua() {
        EditorTabs tabs = new EditorTabs("return 1");
        assertEquals(1, tabs.size());
        assertEquals(0, tabs.activeIndex());
        assertEquals("script.lua", tabs.activeName());
        assertEquals("return 1", tabs.activeContent());
    }

    @Test
    public void newTabsUseStableNamesAndPreserveContents() {
        EditorTabs tabs = new EditorTabs("first");
        tabs.updateActiveContent("first-edited");

        assertEquals("script1.lua", tabs.addTab());
        assertEquals(1, tabs.activeIndex());
        assertEquals("", tabs.activeContent());

        tabs.updateActiveContent("second");
        tabs.activate(0);
        assertEquals("script.lua", tabs.activeName());
        assertEquals("first-edited", tabs.activeContent());

        tabs.activate(1);
        assertEquals("script1.lua", tabs.activeName());
        assertEquals("second", tabs.activeContent());

        assertEquals("script2.lua", tabs.addTab());
        assertEquals(3, tabs.size());
    }

    @Test(expected = IndexOutOfBoundsException.class)
    public void invalidTabIndexFailsExplicitly() {
        EditorTabs tabs = new EditorTabs("");
        tabs.activate(5);
    }
}
