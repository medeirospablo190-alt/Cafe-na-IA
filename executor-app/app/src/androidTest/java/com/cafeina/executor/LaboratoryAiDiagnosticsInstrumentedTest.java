package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiDiagnosticsInstrumentedTest {
    @Test
    public void diagnosticFindsFailureWithoutPersistingRawInput()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String sessionId = UUID.randomUUID().toString();
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), "");

        sessions.begin(sessionId, System.currentTimeMillis(),
            Arrays.asList("echo"), 4, 4096, 60_000L);

        String secret = "diagnostic-secret-must-not-be-stored";
        String inputSha = LaboratoryEngine.fingerprint(secret).substring(7, 71);
        sessions.append(sessionId, LaboratoryAiSessionStore.INVOKE_REQUEST,
            "ACTIVE", "echo", inputSha,
            secret.getBytes(StandardCharsets.UTF_8).length,
            "", "REQUESTED", 1,
            secret.getBytes(StandardCharsets.UTF_8).length);
        sessions.append(sessionId, LaboratoryAiSessionStore.INVOKE_RESULT,
            "ACTIVE", "echo", inputSha,
            secret.getBytes(StandardCharsets.UTF_8).length,
            "", "FAIL", 1,
            secret.getBytes(StandardCharsets.UTF_8).length);
        sessions.append(sessionId, LaboratoryAiSessionStore.FINISH,
            "FINISHED", "", "", 0, "",
            "HOST_COMPLETED", 1,
            secret.getBytes(StandardCharsets.UTF_8).length);

        LaboratoryAiDiagnosticStore.Report report =
            LaboratoryAiDiagnostics.analyzeNow(app, "", sessionId);

        assertEquals("FAILURE", report.severity);
        assertEquals(1, report.failedInvocations);
        assertTrue(report.recommendationCodes.contains(
            "INSPECT_TOOL_FAILURES"));

        File persisted = new File(app.getFilesDir(),
            "laboratory/legacy/ai-diagnostics/" + sessionId + ".json");
        String raw = new String(
            Files.readAllBytes(persisted.toPath()), StandardCharsets.UTF_8);
        assertFalse(raw.contains(secret));
        assertTrue(raw.contains(inputSha) == false);
    }

    @Test
    public void diagnosticMarksCleanSessionHealthy() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String sessionId = UUID.randomUUID().toString();
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), "");

        sessions.begin(sessionId, System.currentTimeMillis(),
            Arrays.asList("echo"), 4, 4096, 60_000L);
        sessions.append(sessionId, LaboratoryAiSessionStore.FINISH,
            "FINISHED", "", "", 0, "",
            "HOST_COMPLETED", 0, 0);

        LaboratoryAiDiagnosticStore.Report report =
            LaboratoryAiDiagnostics.analyzeNow(app, "", sessionId);

        assertEquals("HEALTHY", report.severity);
        assertEquals(Arrays.asList("NO_ACTION"),
            report.recommendationCodes);
    }
}
