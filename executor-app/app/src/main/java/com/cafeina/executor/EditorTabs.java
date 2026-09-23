package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

public final class EditorTabs {
    private static final class TabState {
        final String name;
        String content;
        String savedContent;

        TabState(String name, String content, String savedContent) {
            this.name = name;
            this.content = content;
            this.savedContent = savedContent;
        }

        boolean isDirty() {
            return !Objects.equals(content, savedContent);
        }
    }

    private final List<TabState> tabs = new ArrayList<>();
    private int activeIndex = 0;
    private int nextScriptNumber = 1;

    public EditorTabs(String initialContent) {
        String safe = initialContent == null ? "" : initialContent;
        tabs.add(new TabState("script.lua", safe, safe));
    }

    public int size() {
        return tabs.size();
    }

    public int activeIndex() {
        return activeIndex;
    }

    public String activeName() {
        return tabs.get(activeIndex).name;
    }

    public String activeContent() {
        return tabs.get(activeIndex).content;
    }

    public boolean activeDirty() {
        return tabs.get(activeIndex).isDirty();
    }

    public String nameAt(int index) {
        return tabs.get(index).name;
    }

    public String contentAt(int index) {
        return tabs.get(index).content;
    }

    public boolean isDirtyAt(int index) {
        return tabs.get(index).isDirty();
    }

    public int indexOfName(String name) {
        for (int i = 0; i < tabs.size(); i++) {
            if (tabs.get(i).name.equals(name)) return i;
        }
        return -1;
    }

    public boolean hasName(String name) {
        return indexOfName(name) >= 0;
    }

    public void updateActiveContent(String content) {
        tabs.get(activeIndex).content = content == null ? "" : content;
    }

    public String addTab() {
        return addTab(Collections.emptyList());
    }

    public String addTab(Collection<String> unavailableNames) {
        Collection<String> reserved = unavailableNames == null ? Collections.emptyList() : unavailableNames;

        String name;
        do {
            name = "script" + nextScriptNumber++ + ".lua";
        } while (hasName(name) || reserved.contains(name));

        tabs.add(new TabState(name, "", ""));
        activeIndex = tabs.size() - 1;
        return name;
    }

    public int openOrReplace(String name, String content) {
        if (name == null || name.isEmpty()) {
            throw new IllegalArgumentException("tab name required");
        }

        int existing = indexOfName(name);
        String safeContent = content == null ? "" : content;

        if (existing >= 0) {
            TabState tab = tabs.get(existing);
            tab.content = safeContent;
            tab.savedContent = safeContent;
            activeIndex = existing;
        } else {
            tabs.add(new TabState(name, safeContent, safeContent));
            activeIndex = tabs.size() - 1;
        }

        advanceGeneratedCounter(name);
        return activeIndex;
    }

    public void markSaved(String name, String savedContent) {
        int index = indexOfName(name);
        if (index < 0) return;
        tabs.get(index).savedContent = savedContent == null ? "" : savedContent;
    }

    public int close(int index) {
        if (index < 0 || index >= tabs.size()) {
            throw new IndexOutOfBoundsException("tab index " + index);
        }
        if (tabs.size() <= 1) {
            throw new IllegalStateException("at least one tab must remain open");
        }

        tabs.remove(index);

        if (index < activeIndex) {
            activeIndex--;
        } else if (index == activeIndex && activeIndex >= tabs.size()) {
            activeIndex = tabs.size() - 1;
        }

        return activeIndex;
    }

    public void activate(int index) {
        if (index < 0 || index >= tabs.size()) {
            throw new IndexOutOfBoundsException("tab index " + index);
        }
        activeIndex = index;
    }

    private void advanceGeneratedCounter(String name) {
        if (!name.startsWith("script") || !name.endsWith(".lua")) return;

        String middle = name.substring("script".length(), name.length() - ".lua".length());
        if (middle.isEmpty()) return;

        try {
            int number = Integer.parseInt(middle);
            if (number >= nextScriptNumber) nextScriptNumber = number + 1;
        } catch (NumberFormatException ignored) {
        }
    }
}
