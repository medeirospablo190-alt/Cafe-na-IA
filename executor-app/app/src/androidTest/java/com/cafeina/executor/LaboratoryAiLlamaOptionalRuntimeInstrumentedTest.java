package com.cafeina.executor;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertThrows;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.cafeina.runtime.LlamaBridge;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiLlamaOptionalRuntimeInstrumentedTest {
    @Test
    public void optionalRuntimeCanBeProbedWithoutCrashingNormalBuild()
            throws Exception {
        if (LlamaBridge.isRuntimeAvailable()) {
            String version = LlamaBridge.version();
            assertNotNull(version);
            assertFalse(version.isEmpty());
            return;
        }

        assertThrows(
            IOException.class,
            LlamaBridge::version);
    }
}
