package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.view.View;
import android.view.KeyEvent;
import android.widget.Button;
import android.widget.EditText;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class LuauCodeEditorInstrumentedTest {
    @Test
    public void cancelingClearKeepsUnsavedSourceInEditor() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Intent intent = new Intent(instrumentation.getTargetContext(), MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Activity activity = instrumentation.startActivitySync(intent);
        assertNotNull(activity);

        try {
            final EditText[] editor = new EditText[1];
            final Button[] clear = new Button[1];
            long deadline = System.currentTimeMillis() + 5000;
            while (System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> {
                    View root = activity.findViewById(android.R.id.content);
                    editor[0] = MainActivityStorageUiTest.findFirst(root, EditText.class, null);
                    clear[0] = MainActivityStorageUiTest.findFirst(root, Button.class, "CLEAR");
                });
                if (editor[0] != null && editor[0].isEnabled() && clear[0] != null
                    && clear[0].isEnabled()) break;
                Thread.sleep(50);
            }
            assertNotNull(editor[0]);
            assertNotNull(clear[0]);
            final String unsavedSource = "local secret = 'keep this draft'";
            instrumentation.runOnMainSync(() -> {
                editor[0].setText(unsavedSource);
                clear[0].performClick();
            });
            instrumentation.waitForIdleSync();
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);
            instrumentation.waitForIdleSync();
            instrumentation.runOnMainSync(() -> {
                assertTrue(!activity.isFinishing());
                assertEquals(unsavedSource, editor[0].getText().toString());
            });
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }

    @Test
    public void decorationLeavesEnteredLuauUntouchedAndReservesLineNumberGutter() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Intent intent = new Intent(instrumentation.getTargetContext(), MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Activity activity = instrumentation.startActivitySync(intent);
        assertNotNull(activity);

        try {
            final EditText[] editor = new EditText[1];
            long deadline = System.currentTimeMillis() + 5000;
            while (System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> {
                    View root = activity.findViewById(android.R.id.content);
                    editor[0] = MainActivityStorageUiTest.findFirst(root, EditText.class, null);
                });
                if (editor[0] != null && editor[0].isEnabled()) break;
                Thread.sleep(50);
            }

            assertNotNull(editor[0]);
            final String source = "local x = 42\nprint(\"-- not a comment\")\nreturn x";
            instrumentation.runOnMainSync(() -> {
                assertTrue(editor[0] instanceof LuauCodeEditor);
                assertTrue(editor[0].getPaddingLeft() > editor[0].getPaddingRight());
                editor[0].setText(source);
            });
            Thread.sleep(350); // Let the scheduled decoration run on the UI thread.
            instrumentation.runOnMainSync(() -> assertEquals(source, editor[0].getText().toString()));
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }
}
