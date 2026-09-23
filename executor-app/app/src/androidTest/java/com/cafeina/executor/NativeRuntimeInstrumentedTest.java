package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.cafeina.runtime.LuauBridge;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class NativeRuntimeInstrumentedTest {
    @Test
    public void nativeRuntimeExecutesLuauInsideAndroid() throws Exception {
        String raw = LuauBridge.nativeExecute("print('android-ok') return 21 * 2", 500);
        JSONObject result = new JSONObject(raw);

        assertTrue(result.optBoolean("ok", false));
        assertEquals("android-ok\n", result.optString("output"));

        JSONArray returns = result.getJSONArray("returns");
        assertEquals(1, returns.length());
        assertEquals("42", returns.getString(0));
    }
}
