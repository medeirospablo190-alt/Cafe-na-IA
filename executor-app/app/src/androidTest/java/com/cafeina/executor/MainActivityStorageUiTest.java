package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.file.Files;

@RunWith(AndroidJUnit4.class)
public final class MainActivityStorageUiTest {
    @Test
    public void saveButtonPersistsActiveEditorToPrivateStorage() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        ScriptStore store = new ScriptStore(instrumentation.getTargetContext().getFilesDir());
        Files.deleteIfExists(store.directory().resolve("script.lua"));

        Intent intent = new Intent(instrumentation.getTargetContext(), MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Activity activity = instrumentation.startActivitySync(intent);
        assertNotNull(activity);

        try {
            final EditText[] editor = new EditText[1];
            final Button[] save = new Button[1];

            waitForUiReady(instrumentation, activity, editor, save);

            instrumentation.runOnMainSync(() -> {
                editor[0].setText("print('ui-save')\nreturn 55");
                save[0].performClick();
            });

            long deadline = System.currentTimeMillis() + 5000;
            while (
                (!store.exists("script.lua")
                    || !"print('ui-save')\nreturn 55".equals(store.load("script.lua")))
                    && System.currentTimeMillis() < deadline
            ) {
                Thread.sleep(50);
            }

            assertTrue(store.exists("script.lua"));
            assertEquals("print('ui-save')\nreturn 55", store.load("script.lua"));
        } finally {
            instrumentation.runOnMainSync(activity::finish);
            Files.deleteIfExists(store.directory().resolve("script.lua"));
        }
    }

    private static void waitForUiReady(
        Instrumentation instrumentation,
        Activity activity,
        EditText[] editor,
        Button[] save
    ) throws Exception {
        long deadline = System.currentTimeMillis() + 5000;
        while (System.currentTimeMillis() < deadline) {
            instrumentation.runOnMainSync(() -> {
                View root = activity.findViewById(android.R.id.content);
                editor[0] = findFirst(root, EditText.class, null);
                save[0] = findFirst(root, Button.class, "SAVE");
            });

            if (
                editor[0] != null
                    && editor[0].isEnabled()
                    && save[0] != null
                    && save[0].isEnabled()
            ) {
                return;
            }

            Thread.sleep(50);
        }

        assertNotNull(editor[0]);
        assertNotNull(save[0]);
        assertTrue(editor[0].isEnabled());
        assertTrue(save[0].isEnabled());
    }

    @SuppressWarnings("unchecked")
    static <T extends View> T findFirst(View root, Class<T> type, String text) {
        if (type.isInstance(root)) {
            if (text == null || (root instanceof Button && text.contentEquals(((Button) root).getText()))) {
                return (T) root;
            }
        }

        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                T found = findFirst(group.getChildAt(i), type, text);
                if (found != null) return found;
            }
        }

        return null;
    }
}
