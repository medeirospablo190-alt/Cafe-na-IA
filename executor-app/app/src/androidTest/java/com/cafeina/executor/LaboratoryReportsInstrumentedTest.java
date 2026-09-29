package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

/**
 * Saves only synthetic fixture evidence in a fresh test project. Real user
 * scripts, projects, Auto Execute and native runtime files are never accessed.
 */
@RunWith(AndroidJUnit4.class)
public final class LaboratoryReportsInstrumentedTest {
    @Test
    public void reportsAreCreateOnlyReadableAndIsolatedPerProject() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String firstId = "labtest-" + UUID.randomUUID().toString().substring(0, 8);
        String secondId = "labtest-" + UUID.randomUUID().toString().substring(0, 8);
        LaboratoryReportStore first = new LaboratoryReportStore(app.getFilesDir(), firstId);
        LaboratoryReportStore second = new LaboratoryReportStore(app.getFilesDir(), secondId);
        final String source = "confidential fixture source -- never stored in report";

        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            12345, 5000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "fingerprint", source, LaboratoryEngine.fingerprint(source))));
        LaboratoryEngine.Report result =
            LaboratoryEngine.run(request, new LaboratoryEngine.Cancellation());

        assertEquals(LaboratoryEngine.Status.PASS, result.status);
        first.save(result);
        List<LaboratoryReportStore.Entry> items = first.list();
        assertEquals(1, items.size());
        assertEquals(result.runId, items.get(0).runId);
        assertEquals("PASS", items.get(0).status);
        assertEquals(1, items.get(0).passed);
        assertFalse(items.get(0).reportText.contains(source));
        assertTrue(first.read(result.runId).contains(result.candidateBatchSha256));
        assertTrue("Different project must not see reports", second.list().isEmpty());

        try {
            first.save(result);
            fail("Existing report should not be overwritten");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("already"));
        }
        try {
            first.read("../other.json");
            fail("Path traversal should not be accepted");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("invalid"));
        }
    }
}
