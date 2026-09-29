package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ActivityInfo;
import android.graphics.Point;
import android.content.Intent;
import android.os.SystemClock;
import android.view.WindowManager;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** Checks the Godot host starts in the installed Android app, not in the Godot editor. */
@RunWith(AndroidJUnit4.class)
public final class GodotWorldLaunchInstrumentedTest {
    @Test
    public void embeddedWorldProcessStarts() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();

        // A previous regression set the manifest to landscape but Godot to portrait.
        ActivityInfo world = app.getPackageManager().getActivityInfo(
            new ComponentName(app, GodotWorldActivity.class), 0);
        assertEquals("Android World Activity must be landscape",
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, world.screenOrientation);
        ByteArrayOutputStream packaged = new ByteArrayOutputStream();
        try (InputStream project = app.getAssets().open("project.godot")) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = project.read(buffer)) != -1) {
                packaged.write(buffer, 0, count);
            }
        }
        String settings = new String(packaged.toByteArray(), StandardCharsets.UTF_8);
        assertTrue("Packaged Godot world must request landscape (orientation=0)",
            settings.contains("window/handheld/orientation=0"));

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

        // Check the actual Android display, not only the manifest or the process.
        WindowManager windows =
            (WindowManager) app.getSystemService(Context.WINDOW_SERVICE);
        Point screen = new Point();
        boolean landscape = false;
        long rotationDeadline = SystemClock.elapsedRealtime() + 12000;
        while (SystemClock.elapsedRealtime() < rotationDeadline) {
            windows.getDefaultDisplay().getRealSize(screen);
            if (screen.x > screen.y) {
                landscape = true;
                break;
            }
            Thread.sleep(250);
        }
        assertTrue("Godot world remained portrait: " + screen.x + "x" + screen.y,
            landscape);
    }
}
