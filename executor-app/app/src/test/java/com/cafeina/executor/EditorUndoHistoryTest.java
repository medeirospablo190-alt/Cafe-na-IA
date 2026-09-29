package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class EditorUndoHistoryTest {
    @Test
    public void undoAndRedoRestoreExactSnapshots() {
        EditorUndoHistory history = new EditorUndoHistory();
        history.record("script.lua", "a", "ab");
        history.record("script.lua", "ab", "abc");

        assertEquals("ab", history.undo("script.lua", "abc"));
        assertEquals("a", history.undo("script.lua", "ab"));
        assertFalse(history.canUndo("script.lua"));
        assertEquals("ab", history.redo("script.lua", "a"));
        assertEquals("abc", history.redo("script.lua", "ab"));
        assertFalse(history.canRedo("script.lua"));
    }

    @Test
    public void editsAfterUndoInvalidateRedoWithoutTouchingOtherTabs() {
        EditorUndoHistory history = new EditorUndoHistory();
        history.record("one.lua", "1", "12");
        history.record("two.lua", "a", "ab");
        assertEquals("1", history.undo("one.lua", "12"));
        assertTrue(history.canRedo("one.lua"));
        history.record("one.lua", "1", "13");
        assertFalse(history.canRedo("one.lua"));
        assertTrue(history.canUndo("two.lua"));
        assertEquals("a", history.undo("two.lua", "ab"));
    }

    @Test
    public void cancelAndDiscardOnlyAffectNamedTab() {
        EditorUndoHistory history = new EditorUndoHistory();
        history.record("one.lua", "keep", "");
        history.record("two.lua", "original", "changed");
        history.forget("one.lua");
        assertFalse(history.canUndo("one.lua"));
        assertEquals("original", history.undo("two.lua", "changed"));
    }

    @Test
    public void hugeEditsAvoidRetainingLargeCopiesInMemory() {
        EditorUndoHistory history = new EditorUndoHistory();
        history.record("one.lua", "a", "ab");
        String large = new String(new char[96 * 1024 + 1]).replace('\0', 'x');
        history.record("one.lua", "ab", large);
        assertFalse(history.canUndo("one.lua"));
        assertEquals(large, history.undo("one.lua", large));
    }

    @Test
    public void noOpDoesNotEraseRedoHistory() {
        EditorUndoHistory history = new EditorUndoHistory();
        history.record("one.lua", "", "x");
        assertEquals("", history.undo("one.lua", "x"));
        history.record("one.lua", "", "");
        assertTrue(history.canRedo("one.lua"));
    }
}
