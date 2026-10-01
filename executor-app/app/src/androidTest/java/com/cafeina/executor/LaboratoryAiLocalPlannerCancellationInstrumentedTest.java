package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.io.IOException;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiLocalPlannerCancellationInstrumentedTest {
    @Test
    public void preCancelledProbeStopsBeforeModelAdmission()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();

        LaboratoryAiLocalPlannerProbe.Cancellation cancellation =
            new LaboratoryAiLocalPlannerProbe.Cancellation();
        cancellation.cancel();
        assertTrue(cancellation.isCancelled());

        IOException failure = assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalPlannerProbe.plan(
                app,
                "",
                "not-read-because-cancelled",
                new File(app.getFilesDir(), "models/missing.gguf"),
                cancellation));

        assertEquals(
            "local planner cancelled",
            failure.getMessage());
    }

    @Test
    public void cancellationIsIdempotent() {
        LaboratoryAiLocalPlannerProbe.Cancellation cancellation =
            new LaboratoryAiLocalPlannerProbe.Cancellation();

        cancellation.cancel();
        cancellation.cancel();

        assertTrue(cancellation.isCancelled());
    }
}
