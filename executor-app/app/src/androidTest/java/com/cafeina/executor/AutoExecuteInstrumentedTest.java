package com.cafeina.executor;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.TextView;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Set;

@RunWith(AndroidJUnit4.class)
public final class AutoExecuteInstrumentedTest {
    @Test
    public void explicitOptInPersistsAndRunsSavedScriptAfterReopen() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Path files = instrumentation.getTargetContext().getFilesDir().toPath();
        ScriptStore scripts = new ScriptStore(files);
        AutoExecuteStore auto = new AutoExecuteStore(files.resolve("autoexecute.txt"));

        cleanup(files, scripts);
        scripts.save("auto.lua", "print('auto-start')\nreturn 77");

        Activity first = null;
        Activity second = null;

        try {
            first = start(instrumentation);

            Button autoTab = waitForButton(instrumentation, first, "auto.lua", 7000);
            assertNotNull("auto.lua tab did not restore before opt-in", autoTab);
            instrumentation.runOnMainSync(autoTab::performClick);
            instrumentation.waitForIdleSync();

            Button off = waitForButton(instrumentation, first, "AUTO EXEC: OFF", 3000);
            assertNotNull("AUTO EXEC: OFF did not become available for auto.lua", off);

            instrumentation.runOnMainSync(off::performClick);

            long deadline = System.currentTimeMillis() + 5000;
            while (System.currentTimeMillis() < deadline) {
                Set<String> enabled = auto.load();
                if (enabled.contains("auto.lua")) break;
                Thread.sleep(50);
            }

            assertTrue(
                "Tapping AUTO EXEC: OFF did not persist auto.lua in autoexecute.txt",
                auto.load().contains("auto.lua")
            );

            instrumentation.runOnMainSync(first::finish);
            instrumentation.waitForIdleSync();
            first = null;

            second = start(instrumentation);

            TextView report = waitForTextContaining(
                instrumentation,
                second,
                "[AUTO EXEC] auto.lua",
                10000
            );
            assertNotNull(
                "Reopening the Activity did not produce an Auto Execute report for auto.lua",
                report
            );

            final String[] reportText = new String[1];
            final TextView finalReport = report;
            instrumentation.runOnMainSync(() -> reportText[0] = finalReport.getText().toString());

            assertTrue(
                "Auto Execute report did not contain script print output. Report: " + reportText[0],
                reportText[0].contains("auto-start")
            );
            assertTrue(
                "Auto Execute report did not contain return value 77. Report: " + reportText[0],
                reportText[0].contains("[77]")
            );

            Button restoredAutoTab = waitForButton(instrumentation, second, "auto.lua", 5000);
            assertNotNull("auto.lua tab did not restore after reopening", restoredAutoTab);
            instrumentation.runOnMainSync(restoredAutoTab::performClick);
            instrumentation.waitForIdleSync();

            Button on = waitForButton(instrumentation, second, "AUTO EXEC: ON", 3000);
            assertNotNull(
                "AUTO EXEC state for auto.lua was not restored as ON after reopening",
                on
            );
        } finally {
            if (first != null) {
                final Activity activity = first;
                instrumentation.runOnMainSync(activity::finish);
                instrumentation.waitForIdleSync();
            }
            if (second != null) {
                final Activity activity = second;
                instrumentation.runOnMainSync(activity::finish);
                instrumentation.waitForIdleSync();
            }
            cleanup(files, scripts);
        }
    }

    private static void cleanup(Path files, ScriptStore scripts) throws Exception {
        Files.deleteIfExists(scripts.directory().resolve("auto.lua"));
        Files.deleteIfExists(files.resolve("autoexecute.txt"));
    }

    private static Activity start(Instrumentation instrumentation) {
        Intent intent = new Intent(instrumentation.getTargetContext(), MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Activity activity = instrumentation.startActivitySync(intent);
        instrumentation.waitForIdleSync();
        return activity;
    }

    private static Button waitForButton(
        Instrumentation instrumentation,
        Activity activity,
        String text,
        long timeoutMs
    ) throws Exception {
        final Button[] found = new Button[1];
        long deadline = System.currentTimeMillis() + timeoutMs;

        while (System.currentTimeMillis() < deadline) {
            instrumentation.runOnMainSync(() -> {
                View root = activity.findViewById(android.R.id.content);
                found[0] = MainActivityStorageUiTest.findFirst(root, Button.class, text);
            });
            if (found[0] != null && found[0].isEnabled()) return found[0];
            Thread.sleep(50);
        }
        return found[0];
    }

    private static TextView waitForTextContaining(
        Instrumentation instrumentation,
        Activity activity,
        String needle,
        long timeoutMs
    ) throws Exception {
        final TextView[] found = new TextView[1];
        long deadline = System.currentTimeMillis() + timeoutMs;

        while (System.currentTimeMillis() < deadline) {
            instrumentation.runOnMainSync(() -> {
                View root = activity.findViewById(android.R.id.content);
                found[0] = findTextContaining(root, needle);
            });
            if (found[0] != null) return found[0];
            Thread.sleep(50);
        }
        return found[0];
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
