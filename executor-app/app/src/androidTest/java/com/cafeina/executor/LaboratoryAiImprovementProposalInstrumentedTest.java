package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
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
import java.util.Collections;
import java.util.List;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiImprovementProposalInstrumentedTest {
    @Test
    public void diagnosticRecommendationsBecomeDeduplicatedRoleRoutedProposals()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "improve"
            + UUID.randomUUID().toString().substring(0, 8);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(
                app, LaboratoryAiImprovementProposalsActivity.class), 0);
        assertFalse("Improvement proposal Activity must remain private",
            info.exported);

        new LaboratoryAiTeamRegistry(app.getFilesDir(), project)
            .registerMember(
                "creator-agent",
                "IA Criadora",
                LaboratoryAiTeamRegistry.ROLE_CREATOR);

        String latestSessionId = UUID.randomUUID().toString();
        LaboratoryAiTeamDiagnosticStore diagnostics =
            new LaboratoryAiTeamDiagnosticStore(app.getFilesDir(), project);
        diagnostics.save(report(
            latestSessionId,
            4,
            2,
            2,
            "DEGRADING"));

        List<LaboratoryAiImprovementProposalStore.Proposal> first =
            LaboratoryAiImprovementPlanner.refreshNow(app, project);
        assertEquals(3, first.size());

        LaboratoryAiImprovementProposalStore.Proposal failureReview =
            first.stream()
                .filter(item -> "REVIEW_REPEATED_FAILURES".equals(
                    item.sourceRecommendationCode))
                .findFirst()
                .orElseThrow(() -> new AssertionError("failure proposal missing"));
        assertEquals("RUN_TARGETED_FAILURE_REVIEW",
            failureReview.suggestedActionCode);
        assertEquals(LaboratoryAiTeamRegistry.ROLE_REVIEWER,
            failureReview.targetRole);

        LaboratoryAiImprovementProposalStore.Proposal regression =
            first.stream()
                .filter(item -> "PRIORITIZE_REGRESSION_REVIEW".equals(
                    item.sourceRecommendationCode))
                .findFirst()
                .orElseThrow(() -> new AssertionError("regression proposal missing"));
        assertEquals("RUN_REGRESSION_SUITE", regression.suggestedActionCode);
        assertEquals(LaboratoryAiTeamRegistry.ROLE_TESTER,
            regression.targetRole);

        LaboratoryAiImprovementProposalStore.Proposal recurrent =
            first.stream()
                .filter(item -> "REVIEW_RECURRENT_SIGNALS".equals(
                    item.sourceRecommendationCode))
                .findFirst()
                .orElseThrow(() -> new AssertionError("recurrent proposal missing"));
        assertEquals("CORRELATE_RECURRENT_FAILURE_PATTERN",
            recurrent.suggestedActionCode);
        assertEquals(LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC,
            recurrent.targetRole);

        List<LaboratoryAiImprovementProposalStore.Proposal> sameEvidence =
            LaboratoryAiImprovementPlanner.refreshNow(app, project);
        assertEquals(3, sameEvidence.size());
        assertEquals(
            first.stream().map(item -> item.proposalKeySha256).sorted().toList(),
            sameEvidence.stream()
                .map(item -> item.proposalKeySha256).sorted().toList());

        diagnostics.save(report(
            UUID.randomUUID().toString(),
            5,
            3,
            3,
            "DEGRADING"));
        List<LaboratoryAiImprovementProposalStore.Proposal> newerEvidence =
            LaboratoryAiImprovementPlanner.refreshNow(app, project);
        assertEquals(6, newerEvidence.size());
    }

    @Test
    public void proposalIntegrityRejectsTampering() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "improvetamper"
            + UUID.randomUUID().toString().substring(0, 8);

        new LaboratoryAiTeamRegistry(app.getFilesDir(), project)
            .registerMember(
                "creator-agent",
                "IA Criadora",
                LaboratoryAiTeamRegistry.ROLE_CREATOR);

        LaboratoryAiTeamDiagnosticStore diagnostics =
            new LaboratoryAiTeamDiagnosticStore(app.getFilesDir(), project);
        diagnostics.save(report(
            UUID.randomUUID().toString(),
            4,
            2,
            2,
            "DEGRADING"));

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            LaboratoryAiImprovementPlanner.refreshNow(app, project).get(0);

        Path path = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project
                + "/ai-improvement-proposals/"
                + proposal.proposalId + ".json");
        String raw = new String(
            Files.readAllBytes(path), StandardCharsets.UTF_8);
        raw = raw.replace(
            proposal.suggestedActionCode,
            "TAMPERED_ACTION");
        Files.write(path, raw.getBytes(StandardCharsets.UTF_8));

        assertThrows(java.io.IOException.class, () ->
            new LaboratoryAiImprovementProposalStore(
                app.getFilesDir(), project).read(proposal.proposalId));
    }

    private static LaboratoryAiTeamDiagnosticStore.Report report(
            String latestSessionId, int sessionCount,
            int failureSessions, int failedInvocations, String trend) {
        return new LaboratoryAiTeamDiagnosticStore.Report(
            "creator-agent",
            "creator-agent",
            "IA Criadora",
            LaboratoryAiTeamRegistry.ROLE_CREATOR,
            System.currentTimeMillis(),
            sessionCount,
            sessionCount - failureSessions,
            0,
            failureSessions,
            failedInvocations,
            0,
            0,
            55,
            40,
            trend,
            latestSessionId,
            failureSessions > 0 ? "FAILURE" : "HEALTHY",
            Collections.singletonList("INSPECT_TOOL_FAILURES"),
            Arrays.asList(
                "REVIEW_REPEATED_FAILURES",
                "PRIORITIZE_REGRESSION_REVIEW",
                "REVIEW_RECURRENT_SIGNALS"));
    }
}
