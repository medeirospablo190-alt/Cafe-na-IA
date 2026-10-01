package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Read-only derived inbox for improvement proposals explicitly routed by user.
 *
 * No duplicated workflow state is stored here. Eligibility is recomputed from
 * the proposal + append-only decision ledger, so REOPEN/DISMISS immediately
 * removes an item from the inbox.
 */
public final class LaboratoryAiReviewInbox {
    public static final class Item {
        public final String proposalId;
        public final String agentId;
        public final String agentRole;
        public final String sourceRecommendationCode;
        public final String suggestedActionCode;
        public final String targetRole;
        public final String sourceTrend;
        public final int sourceSessionCount;
        public final int sourceFailureSessions;
        public final int sourceFailedInvocations;
        public final long proposalCreatedAtEpochMs;
        public final int decisionEventCount;
        public final long routedAtEpochMs;

        private Item(
                LaboratoryAiImprovementProposalStore.Proposal proposal,
                LaboratoryAiImprovementDecisionStore.State state) {
            this.proposalId = proposal.proposalId;
            this.agentId = proposal.agentId;
            this.agentRole = proposal.agentRole;
            this.sourceRecommendationCode =
                proposal.sourceRecommendationCode;
            this.suggestedActionCode = proposal.suggestedActionCode;
            this.targetRole = proposal.targetRole;
            this.sourceTrend = proposal.sourceTrend;
            this.sourceSessionCount = proposal.sourceSessionCount;
            this.sourceFailureSessions = proposal.sourceFailureSessions;
            this.sourceFailedInvocations = proposal.sourceFailedInvocations;
            this.proposalCreatedAtEpochMs = proposal.createdAtEpochMs;
            this.decisionEventCount = state.eventCount;
            this.routedAtEpochMs = state.updatedAtEpochMs;
        }
    }

    private final LaboratoryAiImprovementProposalStore proposals;
    private final LaboratoryAiImprovementDecisionStore decisions;

    public LaboratoryAiReviewInbox(
            File appFilesDirectory, String projectId) {
        proposals = new LaboratoryAiImprovementProposalStore(
            appFilesDirectory, projectId);
        decisions = new LaboratoryAiImprovementDecisionStore(
            appFilesDirectory, projectId);
    }

    public List<Item> listAllRouted() throws IOException {
        return listForRole(null);
    }

    public List<Item> listForRole(String role) throws IOException {
        if (role != null) validateRole(role);

        List<Item> result = new ArrayList<>();
        for (LaboratoryAiImprovementProposalStore.Proposal proposal
                : proposals.list()) {
            if (role != null && !role.equals(proposal.targetRole)) continue;

            LaboratoryAiImprovementDecisionStore.State state =
                decisions.state(proposal.proposalId);
            if (!LaboratoryAiImprovementDecisionStore.STATE_ROUTED
                    .equals(state.status)) {
                continue;
            }
            result.add(new Item(proposal, state));
        }

        result.sort(Comparator
            .comparing((Item item) -> item.targetRole)
            .thenComparingLong(item -> item.routedAtEpochMs)
            .thenComparing(item -> item.proposalId));
        return Collections.unmodifiableList(result);
    }

    public Item readRouted(String proposalId) throws IOException {
        LaboratoryAiImprovementProposalStore.Proposal proposal =
            proposals.read(proposalId);
        LaboratoryAiImprovementDecisionStore.State state =
            decisions.state(proposalId);
        if (!LaboratoryAiImprovementDecisionStore.STATE_ROUTED
                .equals(state.status)) {
            throw new IOException(
                "AI improvement proposal is not routed for review");
        }
        return new Item(proposal, state);
    }

    private static void validateRole(String role) {
        if (!(LaboratoryAiTeamRegistry.ROLE_TESTER.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_CREATOR.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_REVIEWER.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_RESEARCHER.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_ORCHESTRATOR.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_SPECIALIST.equals(role))) {
            throw new IllegalArgumentException("invalid AI review role");
        }
    }
}
