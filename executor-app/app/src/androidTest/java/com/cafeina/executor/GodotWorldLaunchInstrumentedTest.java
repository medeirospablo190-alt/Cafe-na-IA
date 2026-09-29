package com.cafeina.executor;

import static org.junit.Assert.assertTrue;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.List;

/** Checks the Godot host starts in the installed Android app, not in the Godot editor. */
@RunWith(AndroidJUnit4.class)
public final class GodotWorldLaunchInstrumentedTest {
    @Test
    public void embeddedWorldProcessStarts() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        Intent intent = new Intent(app, GodotWorldActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        app.startActivity(intent);

        String expected = app.getPackageName() + ":world";
        ActivityManager manager =
            (ActivityManager) app.getSystemService(Context.ACTIVITY_SERVICE);

        long deadline = SystemClock.elapsedRealtime() + 14000;
        boolean processAlive = false;
        while (SystemClock.elapsedRealtime() < deadline) {
            List<ActivityManager.RunningAppProcessInfo> processes =
                manager.getRunningAppProcesses();
            if (processes != null) {
                for (ActivityManager.RunningAppProcessInfo process : processes) {
                    if (expected.equals(process.processName)) {
                        processAlive = true;
                        break;
                    }
                }
            }
            if (processAlive) break;
            Thread.sleep(250);
        }
        assertTrue("Godot world process did not start: " + expected, processAlive);
    }
}
