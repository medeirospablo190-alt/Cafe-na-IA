package com.cafeina.executor;

import java.util.ArrayList;
import java.util.List;

public final class EditorTabs {
    private static final class TabState {
        final String name;
        String content;

        TabState(String name, String content) {
            this.name = name;
            this.content = content;
        }
    }

    private final List<TabState> tabs = new ArrayList<>();
    private int activeIndex = 0;
    private int nextScriptNumber = 1;

    public EditorTabs(String initialContent) {
        tabs.add(new TabState("script.lua", initialContent == null ? "" : initialContent));
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

    public String nameAt(int index) {
        return tabs.get(index).name;
    }

    public void updateActiveContent(String content) {
        tabs.get(activeIndex).content = content == null ? "" : content;
    }

    public String addTab() {
        String name = "script" + nextScriptNumber++ + ".lua";
        tabs.add(new TabState(name, ""));
        activeIndex = tabs.size() - 1;
        return name;
    }

    public void activate(int index) {
        if (index < 0 || index >= tabs.size()) {
            throw new IndexOutOfBoundsException("tab index " + index);
        }
        activeIndex = index;
    }
}
