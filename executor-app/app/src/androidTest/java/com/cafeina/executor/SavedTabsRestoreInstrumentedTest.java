package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.file.Files;

@RunWith(AndroidJUnit4.class)
public final class SavedTabsRestoreInstrumentedTest {
    @Test
    public void savedScriptReturnsAsCleanTabAfterActivityReopens() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        ScriptStore store = new ScriptStore(instrumentation.getTargetContext().getFilesDir());

        Files.deleteIfExists(store.directory().resolve("restored.lua"));
        store.save("restored.lua", "print('restored')\nreturn 88");

        Intent intent = new Intent(instrumentation.getTargetContext(), MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Activity activity = instrumentation.startActivitySync(intent);
        assertNotNull(activity);

        try {
            final Button[] restoredTab = new Button[1];
            final EditText[] editor = new EditText[1];

            long deadline = System.currentTimeMillis() + 5000;
            while (System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> {
                    View root = activity.findViewById(android.R.id.content);
                    restoredTab[0] = MainActivityStorageUiTest.findFirst(root, Button.class, "restored.lua");
                    editor[0] = MainActivityStorageUiTest.findFirst(root, EditText.class, null);
                });

                if (restoredTab[0] != null && editor[0] != null && editor[0].isEnabled()) break;
                Thread.sleep(50);
            }

            assertNotNull(restoredTab[0]);
            assertNotNull(editor[0]);
            assertTrue(editor[0].isEnabled());

            instrumentation.runOnMainSync(() -> restoredTab[0].performClick());
            instrumentation.waitForIdleSync();

            assertEquals("print('restored')\nreturn 88", editor[0].getText().toString());

            final Button[] dirtyLabel = new Button[1];
            instrumentation.runOnMainSync(() -> {
                View root = activity.findViewById(android.R.id.content);
                dirtyLabel[0] = MainActivityStorageUiTest.findFirst(root, Button.class, "restored.lua *");
            });
            assertNull(dirtyLabel[0]);
        } finally {
            instrumentation.runOnMainSync(activity::finish);
            Files.deleteIfExists(store.directory().resolve("restored.lua"));
        }
    }
}
