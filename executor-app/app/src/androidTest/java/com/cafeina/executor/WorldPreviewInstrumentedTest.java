package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Intent;
import android.view.SurfaceView;
import android.widget.TextView;

import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;

public final class WorldPreviewInstrumentedTest {
    @Test
    public void initializesFilamentPreviewOnEmulator() {
        Intent intent = new Intent(
            InstrumentationRegistry.getInstrumentation().getTargetContext(),
            WorldPreviewActivity.class
        );
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Activity activity = InstrumentationRegistry
            .getInstrumentation()
            .startActivitySync(intent);

        try {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();

            SurfaceView surface = activity.findViewById(WorldPreviewActivity.SURFACE_VIEW_ID);
            TextView status = activity.findViewById(WorldPreviewActivity.STATUS_VIEW_ID);

            assertNotNull(surface);
            assertNotNull(status);
            assertEquals("WORLD PREVIEW • GPU READY", status.getText().toString());
            assertFalse(status.getText().toString().contains("INIT ERROR"));
            assertTrue(surface.getWidth() >= 0);
        } finally {
            activity.runOnUiThread(activity::finish);
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();
        }
    }
}
