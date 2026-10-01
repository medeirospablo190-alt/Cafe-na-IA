package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
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
public final class LaboratoryAiImprovementDecisionInstrumentedTest {
    @Test
    public void userDecisionLifecycleIsAppendOnlyAndDoesNotExecuteAnything()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "decision"
            + UUID.randomUUID().toString().substring(0, 8);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(
                app, LaboratoryAiImprovementDecisionsActivity.class), 0);
        assertFalse("Improvement decision Activity must remain private",
            info.exported);

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            createProposal(app, project);

        LaboratoryAiImprovementDecisionStore decisions =
            new LaboratoryAiImprovementDecisionStore(
                app.getFilesDir(), project);

        LaboratoryAiImprovementDecisionStore.State pending =
            decisions.state(proposal.proposalId);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_PENDING,
            pending.status);
        assertEquals(0, pending.eventCount);

        LaboratoryAiImprovementDecisionStore.Event routed =
            decisions.routeForReview(proposal.proposalId);
        assertEquals(1, routed.sequence);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_PENDING,
            routed.previousState);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_ROUTED,
            routed.newState);
        assertEquals(proposal.targetRole, routed.targetRole);
        assertEquals("USER", routed.actor);

        assertThrows(java.io.IOException.class, () ->
            decisions.routeForReview(proposal.proposalId));

        LaboratoryAiImprovementDecisionStore.Event reopened =
            decisions.reopen(proposal.proposalId);
        assertEquals(2, reopened.sequence);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_ROUTED,
            reopened.previousState);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_PENDING,
            reopened.newState);

        LaboratoryAiImprovementDecisionStore.Event dismissed =
            decisions.dismiss(proposal.proposalId);
        assertEquals(3, dismissed.sequence);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_DISMISSED,
            dismissed.newState);
        assertEquals("", dismissed.targetRole);

        LaboratoryAiImprovementDecisionStore.Event reopenedAgain =
            decisions.reopen(proposal.proposalId);
        assertEquals(4, reopenedAgain.sequence);
        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_PENDING,
            reopenedAgain.newState);

        List<LaboratoryAiImprovementDecisionStore.Event> history =
            decisions.history(proposal.proposalId);
        assertEquals(4, history.size());
        for (int i = 0; i < history.size(); i++) {
            assertEquals(i + 1, history.get(i).sequence);
        }

        assertEquals(
            LaboratoryAiImprovementDecisionStore.STATE_PENDING,
            decisions.state(proposal.proposalId).status);

        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(app.getFilesDir(), project);
        assertTrue(sessions.list().isEmpty());
    }

    @Test
    public void tamperedDecisionEventIsRejected() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "decisiontamper"
            + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            createProposal(app, project);
        LaboratoryAiImprovementDecisionStore decisions =
            new LaboratoryAiImprovementDecisionStore(
                app.getFilesDir(), project);
        decisions.routeForReview(proposal.proposalId);

        Path eventPath = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project
                + "/ai-improvement-decisions/"
                + proposal.proposalId + "/000001.json");
        String raw = new String(
            Files.readAllBytes(eventPath), StandardCharsets.UTF_8);
        raw = raw.replace(
            LaboratoryAiImprovementDecisionStore.STATE_ROUTED,
            LaboratoryAiImprovementDecisionStore.STATE_DISMISSED);
        Files.write(eventPath, raw.getBytes(StandardCharsets.UTF_8));

        assertThrows(java.io.IOException.class, () ->
            decisions.history(proposal.proposalId));
        assertThrows(java.io.IOException.class, () ->
            decisions.state(proposal.proposalId));
    }

    private static LaboratoryAiImprovementProposalStore.Proposal createProposal(
            Context app, String project) throws Exception {
        new LaboratoryAiTeamRegistry(app.getFilesDir(), project)
            .registerMember(
                "creator-agent",
                "IA Criadora",
                LaboratoryAiTeamRegistry.ROLE_CREATOR);

        LaboratoryAiTeamDiagnosticStore diagnostics =
            new LaboratoryAiTeamDiagnosticStore(
                app.getFilesDir(), project);
        diagnostics.save(new LaboratoryAiTeamDiagnosticStore.Report(
            "creator-agent",
            "creator-agent",
            "IA Criadora",
            LaboratoryAiTeamRegistry.ROLE_CREATOR,
            System.currentTimeMillis(),
            4,
            2,
            0,
            2,
            2,
            0,
            0,
            55,
            40,
            "DEGRADING",
            UUID.randomUUID().toString(),
            "FAILURE",
            Collections.singletonList("INSPECT_TOOL_FAILURES"),
            Arrays.asList("REVIEW_REPEATED_FAILURES")));

        return LaboratoryAiImprovementPlanner.refreshNow(
            app, project).get(0);
    }
}
