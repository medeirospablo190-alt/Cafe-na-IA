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
import java.util.LinkedHashSet;
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
        scripts.save("script.lua", "print('auto-start')\nreturn 77");

        Set<String> probe = new LinkedHashSet<>();
        probe.add("script.lua");
        auto.save(probe);
        assertTrue(
            "AutoExecuteStore could not persist script.lua directly on Android",
            auto.load().contains("script.lua")
        );
        auto.save(new LinkedHashSet<>());
        assertTrue(
            "AutoExecuteStore could not clear its direct Android probe",
            auto.load().isEmpty()
        );

        Activity first = null;
        Activity second = null;

        try {
            first = start(instrumentation);

            Button autoTab = waitForButton(instrumentation, first, "script.lua", 7000);
            assertNotNull("script.lua tab did not restore before opt-in", autoTab);
            instrumentation.runOnMainSync(autoTab::performClick);
            instrumentation.waitForIdleSync();

            Button off = waitForButton(instrumentation, first, "AUTO EXEC: OFF", 3000);
            assertNotNull("AUTO EXEC: OFF did not become available for script.lua", off);

            instrumentation.runOnMainSync(off::performClick);

            long deadline = System.currentTimeMillis() + 5000;
            while (System.currentTimeMillis() < deadline) {
                Set<String> enabled = auto.load();
                if (enabled.contains("script.lua")) break;
                Thread.sleep(50);
            }

            if (!auto.load().contains("script.lua")) {
                final String[] uiDump = new String[1];
                instrumentation.runOnMainSync(() -> {
                    View root = first.findViewById(android.R.id.content);
                    uiDump[0] = collectText(root);
                });
                throw new AssertionError(
                    "Tapping AUTO EXEC: OFF did not persist script.lua in autoexecute.txt. UI: "
                        + uiDump[0]
                        + " | savedScripts="
                        + scripts.listScripts()
                );
            }

            instrumentation.runOnMainSync(first::finish);
            instrumentation.waitForIdleSync();
            first = null;

            second = start(instrumentation);

            TextView report = waitForTextContaining(
                instrumentation,
                second,
                "[AUTO EXEC] script.lua",
                10000
            );
            assertNotNull(
                "Reopening the Activity did not produce an Auto Execute report for script.lua",
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

            Button restoredAutoTab = waitForButton(instrumentation, second, "script.lua", 5000);
            assertNotNull("script.lua tab did not restore after reopening", restoredAutoTab);
            instrumentation.runOnMainSync(restoredAutoTab::performClick);
            instrumentation.waitForIdleSync();

            Button on = waitForButton(instrumentation, second, "AUTO EXEC: ON", 3000);
            assertNotNull(
                "AUTO EXEC state for script.lua was not restored as ON after reopening",
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
        Files.deleteIfExists(scripts.directory().resolve("script.lua"));
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

    private static String collectText(View root) {
        StringBuilder out = new StringBuilder();
        collectText(root, out);
        return out.toString();
    }

    private static void collectText(View root, StringBuilder out) {
        if (root instanceof TextView) {
            CharSequence value = ((TextView) root).getText();
            if (value != null && value.length() > 0) {
                if (out.length() > 0) out.append(" | ");
                out.append(value);
            }
        }

        if (root instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) root;
            for (int i = 0; i < group.getChildCount(); i++) {
                collectText(group.getChildAt(i), out);
            }
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
