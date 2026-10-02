package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Collections;
import java.util.UUID;

/**
 * Geometry cases run without starting a Godot Activity or touching the real
 * world. The test only writes a report under its own synthetic lab project.
 */
@RunWith(AndroidJUnit4.class)
public final class LaboratoryTestWorldInstrumentedTest {
    @Test
    public void builtInGeometryToolPersistsReproducibleFixtureEvidence() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "worldtest-" + UUID.randomUUID().toString().substring(0, 8);
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.WORLD_CONTACT_TOOL, LaboratoryEngine.WORLD_CONTACT_VERSION,
            7101, 2000, Collections.singletonList(
                new LaboratoryEngine.TestCase("zone-check",
                    "0,20,-4200,100,100,100", "solids=Chao;zones=ZonaVerde")));
        LaboratoryEngine.Report outcome = LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), projectId, request, new LaboratoryEngine.Cancellation());
        assertEquals(LaboratoryEngine.Status.PASS, outcome.status);
        String expectedEnvironment =
            LaboratoryEngine.hostEnvironmentSha256(request);
        assertEquals(expectedEnvironment, outcome.environmentSha256);

        LaboratoryReportStore vault = new LaboratoryReportStore(app.getFilesDir(), projectId);
        assertEquals(1, vault.list().size());
        LaboratoryReportStore.Entry entry = vault.list().get(0);
        JSONObject report = new JSONObject(entry.reportText);
        assertEquals("PASS", report.getString("status"));
        assertEquals(expectedEnvironment,
            report.getString("environmentSha256"));
        assertEquals(1, report.getInt("passed"));
        assertTrue(report.getJSONArray("checks").getJSONObject(0).getBoolean("passed"));
        assertFalse("World fixture tests should not store or execute source code",
            entry.reportText.contains("world.gd"));
    }
}
