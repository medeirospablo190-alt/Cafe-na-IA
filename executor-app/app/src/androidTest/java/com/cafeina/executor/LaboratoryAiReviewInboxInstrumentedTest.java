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

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiReviewInboxInstrumentedTest {
    @Test
    public void inboxContainsOnlyExplicitlyRoutedProposals()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "reviewinbox"
            + UUID.randomUUID().toString().substring(0, 8);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiReviewInboxActivity.class), 0);
        assertFalse("Review inbox Activity must remain private", info.exported);

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            createProposal(app, project);
        LaboratoryAiImprovementDecisionStore decisions =
            new LaboratoryAiImprovementDecisionStore(
                app.getFilesDir(), project);
        LaboratoryAiReviewInbox inbox =
            new LaboratoryAiReviewInbox(app.getFilesDir(), project);

        assertTrue(inbox.listAllRouted().isEmpty());
        assertTrue(inbox.listForRole(
            LaboratoryAiTeamRegistry.ROLE_REVIEWER).isEmpty());
        assertThrows(java.io.IOException.class, () ->
            inbox.readRouted(proposal.proposalId));

        decisions.routeForReview(proposal.proposalId);

        List<LaboratoryAiReviewInbox.Item> routed =
            inbox.listAllRouted();
        assertEquals(1, routed.size());
        LaboratoryAiReviewInbox.Item item = routed.get(0);
        assertEquals(proposal.proposalId, item.proposalId);
        assertEquals("creator-agent", item.agentId);
        assertEquals(proposal.targetRole, item.targetRole);
        assertEquals(1, item.decisionEventCount);
        assertTrue(item.routedAtEpochMs > 0);

        assertEquals(1, inbox.listForRole(
            LaboratoryAiTeamRegistry.ROLE_REVIEWER).size());
        assertTrue(inbox.listForRole(
            LaboratoryAiTeamRegistry.ROLE_TESTER).isEmpty());

        decisions.reopen(proposal.proposalId);
        assertTrue(inbox.listAllRouted().isEmpty());

        decisions.routeForReview(proposal.proposalId);
        assertEquals(1, inbox.listAllRouted().size());

        decisions.dismiss(proposal.proposalId);
        assertTrue(inbox.listAllRouted().isEmpty());
    }

    @Test
    public void routedProposalNeverCreatesAiSessionOrToolExecution()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "reviewnosession"
            + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            createProposal(app, project);
        new LaboratoryAiImprovementDecisionStore(
            app.getFilesDir(), project)
            .routeForReview(proposal.proposalId);

        LaboratoryAiReviewInbox inbox =
            new LaboratoryAiReviewInbox(app.getFilesDir(), project);
        assertEquals(1, inbox.listAllRouted().size());

        assertTrue(new LaboratoryAiSessionStore(
            app.getFilesDir(), project).list().isEmpty());
        assertTrue(LaboratoryAiLiveSessionRegistry.list(project).isEmpty());
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
