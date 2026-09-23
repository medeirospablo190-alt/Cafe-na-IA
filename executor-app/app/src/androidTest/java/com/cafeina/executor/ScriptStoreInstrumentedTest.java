package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;

@RunWith(AndroidJUnit4.class)
public final class ScriptStoreInstrumentedTest {
    @Test
    public void scriptsPersistInAndroidInternalStorageAcrossStoreInstances() throws Exception {
        File filesDir = InstrumentationRegistry.getInstrumentation().getTargetContext().getFilesDir();
        Path testRoot = filesDir.toPath().resolve("phase4-script-store-" + System.nanoTime());
        Path scripts = testRoot.resolve("scripts");

        try {
            ScriptStore first = new ScriptStore(scripts);
            first.save("script.lua", "print('android-storage')\nreturn 42");

            ScriptStore reopened = new ScriptStore(scripts);
            assertTrue(reopened.exists("script.lua"));
            assertEquals(
                "print('android-storage')\nreturn 42",
                reopened.load("script.lua")
            );
            assertEquals(1, reopened.listScripts().size());
            assertEquals("script.lua", reopened.listScripts().get(0));
        } finally {
            if (Files.exists(testRoot)) {
                try (java.util.stream.Stream<Path> stream = Files.walk(testRoot)) {
                    stream.sorted(Comparator.reverseOrder()).forEach(path -> {
                        try {
                            Files.deleteIfExists(path);
                        } catch (Exception ignored) {
                        }
                    });
                }
            }
        }
    }
}
