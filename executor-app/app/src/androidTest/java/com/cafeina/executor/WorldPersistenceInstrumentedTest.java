package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.platform.app.InstrumentationRegistry;

import com.cafeina.runtime.LuauBridge;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.io.File;

public final class WorldPersistenceInstrumentedTest {
    @Test
    public void exportsResetsAndRestoresSharedWorldOnAndroid() throws Exception {
        Context context = InstrumentationRegistry
            .getInstrumentation()
            .getTargetContext();

        File runtimeRoot = new File(context.getFilesDir(), "runtime-fs");
        assertTrue(runtimeRoot.mkdirs() || runtimeRoot.isDirectory());

        LuauBridge.nativeResetWorld();

        try {
            String executionRaw = LuauBridge.nativeExecuteWithFilesAndWorld(
                "local part = World.createPart('PersistedBox') " +
                    "assert(World.setPosition(part, 7, 2, -3)) " +
                    "assert(World.setScale(part, 2, 3, 4)) " +
                    "return part",
                500,
                runtimeRoot.getAbsolutePath()
            );

            JSONObject execution = new JSONObject(executionRaw);
            assertTrue(execution.optBoolean("ok", false));

            String exported = LuauBridge.nativeExportWorldJson();
            JSONObject worldDocument = new JSONObject(exported);

            assertEquals("CAFEINA_WORLD", worldDocument.getString("format"));
            assertEquals(2, worldDocument.getInt("version"));
            assertEquals(1, worldDocument.getJSONArray("objects").length());

            LuauBridge.nativeResetWorld();

            JSONObject emptySnapshot = new JSONObject(
                LuauBridge.nativeRenderSceneSnapshot()
            );
            assertTrue(emptySnapshot.optBoolean("ok", false));
            assertEquals(0, emptySnapshot.getJSONArray("items").length());

            LuauBridge.nativeImportWorldJson(exported);

            JSONObject restoredSnapshot = new JSONObject(
                LuauBridge.nativeRenderSceneSnapshot()
            );
            assertTrue(restoredSnapshot.optBoolean("ok", false));

            JSONArray items = restoredSnapshot.getJSONArray("items");
            assertEquals(1, items.length());

            JSONObject item = items.getJSONObject(0);
            assertEquals("1", item.getString("id"));
            assertEquals("box", item.getString("primitive"));

            JSONArray matrix = item.getJSONArray("worldMatrix");
            assertEquals(7.0, matrix.getDouble(12), 0.0001);
            assertEquals(2.0, matrix.getDouble(13), 0.0001);
            assertEquals(-3.0, matrix.getDouble(14), 0.0001);

            boolean invalidRejected = false;
            try {
                LuauBridge.nativeImportWorldJson("{not valid json");
            } catch (IllegalArgumentException expected) {
                invalidRejected = true;
            }
            assertTrue(invalidRejected);

            JSONObject afterInvalid = new JSONObject(
                LuauBridge.nativeRenderSceneSnapshot()
            );
            assertTrue(afterInvalid.optBoolean("ok", false));
            assertFalse(afterInvalid.getJSONArray("items").isEmpty());
            assertEquals(
                "1",
                afterInvalid.getJSONArray("items").getJSONObject(0).getString("id")
            );
        } finally {
            LuauBridge.nativeResetWorld();
        }
    }
}
