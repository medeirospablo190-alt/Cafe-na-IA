package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ActivityInfo;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiTeamDiagnosticsInstrumentedTest {
    @Test
    public void teamDiagnosticFindsRepeatedFailuresAndDegradingTrend()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "teamdiag"
            + UUID.randomUUID().toString().substring(0, 8);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiTeamDiagnosticsActivity.class), 0);
        assertFalse("Team diagnostics Activity must remain private", info.exported);

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(app.getFilesDir(), project);
        LaboratoryAiTeamRegistry.Member creator = team.registerMember(
            "creator-agent",
            "IA Criadora",
            LaboratoryAiTeamRegistry.ROLE_CREATOR);
        assertEquals("creator-agent", creator.agentId);

        String[] secrets = {
            "TEAM_PRIVATE_HEALTHY_A_1001",
            "TEAM_PRIVATE_HEALTHY_B_1002",
            "TEAM_PRIVATE_FAIL_C_1003",
            "TEAM_PRIVATE_FAIL_D_1004"
        };

        for (int i = 0; i < 4; i++) {
            String sessionId = UUID.randomUUID().toString();
            createSession(
                app, project, sessionId, secrets[i], i >= 2);
            team.bindSession(sessionId, "creator-agent", "");
            LaboratoryAiDiagnostics.analyzeNow(app, project, sessionId);
            Thread.sleep(20L);
        }

        List<LaboratoryAiTeamDiagnosticStore.Report> reports =
            LaboratoryAiTeamDiagnostics.analyzeAllNow(app, project);
        LaboratoryAiTeamDiagnosticStore.Report creatorReport =
            reports.stream()
                .filter(report -> "creator-agent".equals(report.agentId))
                .findFirst()
                .orElseThrow(() -> new AssertionError("creator report missing"));

        assertEquals(4, creatorReport.sessionCount);
        assertEquals(2, creatorReport.healthySessions);
        assertEquals(0, creatorReport.attentionSessions);
        assertEquals(2, creatorReport.failureSessions);
        assertEquals(2, creatorReport.failedInvocations);
        assertEquals("DEGRADING", creatorReport.trend);
        assertEquals("FAILURE", creatorReport.latestSeverity);
        assertTrue(creatorReport.recurrentSignals.contains(
            "INSPECT_TOOL_FAILURES"));
        assertTrue(creatorReport.recommendationCodes.contains(
            "REVIEW_REPEATED_FAILURES"));
        assertTrue(creatorReport.recommendationCodes.contains(
            "PRIORITIZE_REGRESSION_REVIEW"));
        assertTrue(creatorReport.recommendationCodes.contains(
            "REVIEW_RECURRENT_SIGNALS"));

        LaboratoryAiTeamDiagnosticStore.Report diagnosticAgent =
            reports.stream()
                .filter(report -> "diagnostic-agent".equals(report.agentId))
                .findFirst()
                .orElseThrow(() -> new AssertionError("diagnostic agent missing"));
        assertEquals(LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC,
            diagnosticAgent.role);
        assertEquals(0, diagnosticAgent.sessionCount);
        assertEquals(Arrays.asList("WAIT_FOR_SESSION_DATA"),
            diagnosticAgent.recommendationCodes);

        Path persisted = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project
                + "/ai-team-diagnostics/creator-agent.json");
        String raw = new String(
            Files.readAllBytes(persisted), StandardCharsets.UTF_8);
        for (String secret : secrets) {
            assertFalse(raw.contains(secret));
            assertFalse(raw.contains(
                LaboratoryEngine.fingerprint(secret).substring(7, 71)));
        }

        Path spoofed = persisted.getParent().resolve("other-agent.json");
        Files.copy(persisted, spoofed);
        assertThrows(java.io.IOException.class, () ->
            new LaboratoryAiTeamDiagnosticStore(
                app.getFilesDir(), project).read("other-agent"));
        Files.deleteIfExists(spoofed);
    }

    @Test
    public void sessionAttributionIsImmutableAndProjectScoped()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "teambind"
            + UUID.randomUUID().toString().substring(0, 8);
        String sessionId = UUID.randomUUID().toString();

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(app.getFilesDir(), project);
        team.registerMember(
            "creator-agent",
            "IA Criadora",
            LaboratoryAiTeamRegistry.ROLE_CREATOR);
        team.registerMember(
            "reviewer-agent",
            "IA Revisora",
            LaboratoryAiTeamRegistry.ROLE_REVIEWER);

        new LaboratoryAiSessionStore(app.getFilesDir(), project).begin(
            sessionId,
            System.currentTimeMillis(),
            Arrays.asList("tool"),
            2,
            256,
            30_000L);

        LaboratoryAiTeamRegistry.Binding binding =
            team.bindSession(sessionId, "creator-agent", "");
        assertEquals("creator-agent", binding.agentId);

        LaboratoryAiTeamRegistry.Binding same =
            team.bindSession(sessionId, "creator-agent", "");
        assertEquals(binding.recordSha256, same.recordSha256);

        assertThrows(java.io.IOException.class, () ->
            team.bindSession(sessionId, "reviewer-agent", ""));
    }

    private static void createSession(Context app, String project,
            String sessionId, String secret, boolean fail) throws Exception {
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), project);
        sessions.begin(
            sessionId,
            System.currentTimeMillis(),
            Arrays.asList("team-tool"),
            4,
            4096,
            60_000L);

        if (fail) {
            byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
            String inputSha =
                LaboratoryEngine.fingerprint(secret).substring(7, 71);
            sessions.append(
                sessionId,
                LaboratoryAiSessionStore.INVOKE_REQUEST,
                "ACTIVE",
                "team-tool",
                inputSha,
                bytes.length,
                "",
                "REQUESTED",
                1,
                bytes.length);
            sessions.append(
                sessionId,
                LaboratoryAiSessionStore.INVOKE_RESULT,
                "ACTIVE",
                "team-tool",
                inputSha,
                bytes.length,
                "",
                "FAIL",
                1,
                bytes.length);
        }

        sessions.append(
            sessionId,
            LaboratoryAiSessionStore.FINISH,
            "FINISHED",
            "",
            "",
            0,
            "",
            "HOST_COMPLETED",
            fail ? 1 : 0,
            fail ? secret.getBytes(StandardCharsets.UTF_8).length : 0);
    }
}
