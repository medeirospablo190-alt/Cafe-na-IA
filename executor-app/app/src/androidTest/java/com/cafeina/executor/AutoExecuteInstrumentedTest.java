package com.cafeina.executor;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.file.Files;

@RunWith(AndroidJUnit4.class)
public final class AutoExecuteInstrumentedTest {
    @Test
    public void explicitlyEnabledSavedScriptRunsOnStartup() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        ScriptStore scripts = new ScriptStore(instrumentation.getTargetContext().getFilesDir());
        AutoExecuteStore auto = new AutoExecuteStore(instrumentation.getTargetContext().getFilesDir());

        Files.deleteIfExists(auto.metadataPath());
        Files.deleteIfExists(scripts.directory().resolve("autoexec-phase7.lua"));

        scripts.save(
            "autoexec-phase7.lua",
            "print('autoexec-phase7-ok')\nreturn 123"
        );
        auto.setEnabled("autoexec-phase7.lua", true);

        Intent intent = new Intent(instrumentation.getTargetContext(), MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Activity activity = instrumentation.startActivitySync(intent);
        assertNotNull(activity);

        try {
            final TextView[] output = new TextView[1];
            long deadline = System.currentTimeMillis() + 10000;

            while (System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync(() -> {
                    View root = activity.findViewById(android.R.id.content);
                    output[0] = findTextContaining(root, "[AUTOEXEC] autoexec-phase7.lua");
                });

                if (
                    output[0] != null
                        && output[0].getText().toString().contains("autoexec-phase7-ok")
                        && output[0].getText().toString().contains("returns: [123]")
                ) {
                    break;
                }

                Thread.sleep(75);
            }

            assertNotNull(output[0]);
            String rendered = output[0].getText().toString();
            assertTrue(rendered.contains("[AUTOEXEC] autoexec-phase7.lua"));
            assertTrue(rendered.contains("autoexec-phase7-ok"));
            assertTrue(rendered.contains("returns: [123]"));
        } finally {
            instrumentation.runOnMainSync(activity::finish);
            Files.deleteIfExists(auto.metadataPath());
            Files.deleteIfExists(scripts.directory().resolve("autoexec-phase7.lua"));
        }
    }

    private static TextView findTextContaining(View root, String needle) {
        if (root instanceof TextView) {
            TextView text = (TextView) root;
            if (text.getText() != null && text.getText().toString().contains(needle)) {
                return text;
            }
        }

        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                TextView found = findTextContaining(group.getChildAt(i), needle);
                if (found != null) return found;
            }
        }

        return null;
    }
}
