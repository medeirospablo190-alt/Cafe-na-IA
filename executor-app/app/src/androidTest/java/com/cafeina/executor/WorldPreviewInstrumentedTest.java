package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.view.SurfaceView;
import android.widget.TextView;

import androidx.test.platform.app.InstrumentationRegistry;

import com.cafeina.runtime.LuauBridge;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.io.File;

public final class WorldPreviewInstrumentedTest {
    @Test
    public void luauPartFlowsIntoSharedRenderSceneAndFilamentPreview() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();

        File runtimeRoot = new File(context.getFilesDir(), "runtime-fs");
        assertTrue(runtimeRoot.mkdirs() || runtimeRoot.isDirectory());

        LuauBridge.nativeResetWorld();

        String executionRaw = LuauBridge.nativeExecuteWithFilesAndWorld(
            "local part = World.createPart('PreviewBox') " +
                "assert(World.setPosition(part, 0, 0, 0)) " +
                "assert(World.setScale(part, 2, 2, 2)) " +
                "return part",
            500,
            runtimeRoot.getAbsolutePath()
        );

        JSONObject execution = new JSONObject(executionRaw);
        assertTrue(execution.optBoolean("ok", false));

        JSONObject snapshot = new JSONObject(LuauBridge.nativeRenderSceneSnapshot());
        assertTrue(snapshot.optBoolean("ok", false));

        JSONArray items = snapshot.getJSONArray("items");
        assertEquals(1, items.length());
        assertEquals("box", items.getJSONObject(0).getString("primitive"));
        assertEquals("1", items.getJSONObject(0).getString("id"));

        Intent intent = new Intent(context, WorldPreviewActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Activity activity = InstrumentationRegistry
            .getInstrumentation()
            .startActivitySync(intent);

        try {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();

            SurfaceView surface = activity.findViewById(WorldPreviewActivity.SURFACE_VIEW_ID);
            TextView status = activity.findViewById(WorldPreviewActivity.STATUS_VIEW_ID);
            TextView cameraHint = activity.findViewById(WorldPreviewActivity.CAMERA_HINT_VIEW_ID);

            assertNotNull(surface);
            assertNotNull(status);
            assertNotNull(cameraHint);
            assertEquals(
                "WORLD PREVIEW • GPU READY • 1 item(s)",
                status.getText().toString()
            );
            assertFalse(status.getText().toString().contains("INIT ERROR"));
            assertTrue(cameraHint.getText().toString().contains("orbitar"));
            assertTrue(cameraHint.getText().toString().contains("zoom"));
            assertTrue(surface.getWidth() >= 0);
        } finally {
            activity.runOnUiThread(activity::finish);
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            LuauBridge.nativeResetWorld();
        }
    }
}
