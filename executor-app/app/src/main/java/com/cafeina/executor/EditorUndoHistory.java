package com.cafeina.executor;

import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

/**
 * Bounded, in-memory history for independent editor tabs.
 * Never writes or replaces a saved file.
 */
public final class EditorUndoHistory {
    private static final int MAX_STEPS = 24;
    private static final int MAX_SNAPSHOT_CHARS = 96 * 1024;

    private static final class State {
        final ArrayDeque<String> undo = new ArrayDeque<>();
        final ArrayDeque<String> redo = new ArrayDeque<>();
    }

    private final Map<String, State> states = new HashMap<>();

    public void record(String name, String before, String after) {
        Objects.requireNonNull(name, "tab name");
        String oldText = before == null ? "" : before;
        String newText = after == null ? "" : after;
        if (oldText.equals(newText)) return;

        State state = states.computeIfAbsent(name, ignored -> new State());
        state.redo.clear();
        // Large files stay fully editable; their contents are not duplicated in RAM.
        if (oldText.length() > MAX_SNAPSHOT_CHARS || newText.length() > MAX_SNAPSHOT_CHARS) {
            state.undo.clear();
            return;
        }
        push(state.undo, oldText);
    }

    public boolean canUndo(String name) {
        State state = states.get(name);
        return state != null && !state.undo.isEmpty();
    }

    public boolean canRedo(String name) {
        State state = states.get(name);
        return state != null && !state.redo.isEmpty();
    }

    public String undo(String name, String current) {
        State state = states.get(name);
        if (state == null || state.undo.isEmpty()) return current;
        String safe = current == null ? "" : current;
        push(state.redo, safe);
        return state.undo.removeLast();
    }

    public String redo(String name, String current) {
        State state = states.get(name);
        if (state == null || state.redo.isEmpty()) return current;
        String safe = current == null ? "" : current;
        push(state.undo, safe);
        return state.redo.removeLast();
    }

    public void forget(String name) {
        states.remove(name);
    }

    private static void push(ArrayDeque<String> history, String snapshot) {
        if (snapshot.length() > MAX_SNAPSHOT_CHARS) return;
        history.addLast(snapshot);
        while (history.size() > MAX_STEPS) history.removeFirst();
    }
}
