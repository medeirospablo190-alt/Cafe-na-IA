package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import com.cafeina.runtime.LuauBridge;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;

@RunWith(AndroidJUnit4.class)
public final class RuntimeFilesInstrumentedTest {
    @Test
    public void filesystemApiStaysInsideExplicitAndroidSandbox() throws Exception {
        Path filesDir = InstrumentationRegistry.getInstrumentation()
            .getTargetContext()
            .getFilesDir()
            .toPath();

        Path root = filesDir.resolve("runtime-fs-instrumented");
        Path outside = filesDir.resolve("escape.txt");

        deleteTree(root);
        Files.deleteIfExists(outside);

        try {
            String raw = LuauBridge.nativeExecuteWithFiles(
                "fs.write('note.txt', 'android-fs') "
                    + "local names = fs.list() "
                    + "return fs.read('note.txt'), fs.exists('note.txt'), table.concat(names, ',')",
                500,
                root.toString()
            );

            JSONObject result = new JSONObject(raw);
            assertTrue(result.optBoolean("ok", false));

            JSONArray returns = result.getJSONArray("returns");
            assertEquals(3, returns.length());
            assertEquals("android-fs", returns.getString(0));
            assertEquals("true", returns.getString(1));
            assertEquals("note.txt", returns.getString(2));

            assertTrue(Files.isRegularFile(root.resolve("note.txt")));
            assertEquals(
                "android-fs",
                new String(Files.readAllBytes(root.resolve("note.txt")), StandardCharsets.UTF_8)
            );

            String traversalRaw = LuauBridge.nativeExecuteWithFiles(
                "fs.write('../escape.txt', 'bad')",
                500,
                root.toString()
            );

            JSONObject traversal = new JSONObject(traversalRaw);
            assertFalse(traversal.optBoolean("ok", true));
            assertTrue(traversal.optString("error").contains("invalid runtime file name"));
            assertFalse(Files.exists(outside));
        } finally {
            deleteTree(root);
            Files.deleteIfExists(outside);
        }
    }

    private static void deleteTree(Path root) throws Exception {
        if (!Files.exists(root)) return;

        try (java.util.stream.Stream<Path> stream = Files.walk(root)) {
            stream
                .sorted(Comparator.reverseOrder())
                .forEach(path -> {
                    try {
                        Files.deleteIfExists(path);
                    } catch (Exception ignored) {
                    }
                });
        }
    }
}
