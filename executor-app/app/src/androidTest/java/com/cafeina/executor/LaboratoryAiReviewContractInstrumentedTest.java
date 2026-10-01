package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiReviewContractInstrumentedTest {
    @Test
    public void reviewContractIsOneUseRoleBoundAndRevocable()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "reviewcontract"
            + UUID.randomUUID().toString().substring(0, 8);

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
        team.registerMember(
            "tester-agent",
            "IA de Teste Auxiliar",
            LaboratoryAiTeamRegistry.ROLE_TESTER);

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            createProposal(app, project);
        LaboratoryAiImprovementDecisionStore decisions =
            new LaboratoryAiImprovementDecisionStore(
                app.getFilesDir(), project);
        decisions.routeForReview(proposal.proposalId);

        LaboratoryAiReviewContractStore store =
            new LaboratoryAiReviewContractStore(
                app.getFilesDir(), project);
        LaboratoryAiReviewContractStore.Contract contract =
            store.createForRoutedProposal(proposal.proposalId);

        assertEquals(proposal.proposalId, contract.proposalId);
        assertEquals(proposal.proposalKeySha256,
            contract.proposalKeySha256);
        assertEquals(LaboratoryAiTeamRegistry.ROLE_REVIEWER,
            contract.targetRole);
        assertFalse(contract.claimed);

        assertThrows(java.io.IOException.class, () ->
            store.claim(contract.reviewContractId, "tester-agent"));

        LaboratoryAiReviewContractStore.Claim claim =
            store.claim(contract.reviewContractId, "reviewer-agent");
        assertEquals("reviewer-agent", claim.reviewerAgentId);
        assertEquals(LaboratoryAiTeamRegistry.ROLE_REVIEWER,
            claim.reviewerRole);

        assertThrows(java.io.IOException.class, () ->
            store.claim(contract.reviewContractId, "reviewer-agent"));

        LaboratoryAiReviewContractStore.Claim active =
            store.requireActiveClaim(contract.reviewContractId);
        assertEquals(claim.claimId, active.claimId);

        decisions.reopen(proposal.proposalId);
        assertThrows(java.io.IOException.class, () ->
            store.requireActiveClaim(contract.reviewContractId));

        decisions.routeForReview(proposal.proposalId);
        assertThrows(java.io.IOException.class, () ->
            store.requireActiveClaim(contract.reviewContractId));

        LaboratoryAiReviewContractStore.Contract newContract =
            store.createForRoutedProposal(proposal.proposalId);
        assertFalse(contract.reviewContractId.equals(
            newContract.reviewContractId));
        LaboratoryAiReviewContractStore.Contract deduplicated =
            store.createForRoutedProposal(proposal.proposalId);
        assertEquals(newContract.reviewContractId,
            deduplicated.reviewContractId);

        assertTrue(new LaboratoryAiSessionStore(
            app.getFilesDir(), project).list().isEmpty());
        assertTrue(LaboratoryAiLiveSessionRegistry.list(project).isEmpty());
    }

    @Test
    public void contractCannotBeCreatedUnlessProposalIsCurrentlyRouted()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext().getApplicationContext();
        String project = "reviewcontractstate"
            + UUID.randomUUID().toString().substring(0, 8);

        new LaboratoryAiTeamRegistry(app.getFilesDir(), project)
            .registerMember(
                "creator-agent",
                "IA Criadora",
                LaboratoryAiTeamRegistry.ROLE_CREATOR);

        LaboratoryAiImprovementProposalStore.Proposal proposal =
            createProposal(app, project);
        LaboratoryAiReviewContractStore store =
            new LaboratoryAiReviewContractStore(
                app.getFilesDir(), project);

        assertThrows(java.io.IOException.class, () ->
            store.createForRoutedProposal(proposal.proposalId));

        LaboratoryAiImprovementDecisionStore decisions =
            new LaboratoryAiImprovementDecisionStore(
                app.getFilesDir(), project);
        decisions.routeForReview(proposal.proposalId);
        LaboratoryAiReviewContractStore.Contract contract =
            store.createForRoutedProposal(proposal.proposalId);
        assertEquals(proposal.proposalId, contract.proposalId);

        decisions.dismiss(proposal.proposalId);
        assertThrows(java.io.IOException.class, () ->
            store.createForRoutedProposal(proposal.proposalId));
    }

    private static LaboratoryAiImprovementProposalStore.Proposal createProposal(
            Context app, String project) throws Exception {
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
