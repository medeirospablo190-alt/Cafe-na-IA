package com.cafeina.executor;

import android.content.Context;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Converts sanitized team diagnostics into reviewable improvement proposals.
 * It never applies a proposal.
 */
public final class LaboratoryAiImprovementPlanner {
    private static final ExecutorService IO =
        Executors.newSingleThreadExecutor();
    private static final Object REFRESH_LOCK = new Object();

    private LaboratoryAiImprovementPlanner() {}

    public static void schedule(Context context, String projectId) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try {
                refreshNow(app, projectId);
            } catch (Exception ignored) {
                // Proposal generation must never control AI execution.
            }
        });
    }

    static List<LaboratoryAiImprovementProposalStore.Proposal> refreshNow(
            Context context, String projectId) throws IOException {
        if (context == null) {
            throw new IllegalArgumentException(
                "improvement planner context missing");
        }

        synchronized (REFRESH_LOCK) {
            LaboratoryAiTeamDiagnosticStore diagnostics =
                new LaboratoryAiTeamDiagnosticStore(
                    context.getFilesDir(), projectId);
            LaboratoryAiImprovementProposalStore proposals =
                new LaboratoryAiImprovementProposalStore(
                    context.getFilesDir(), projectId);

            for (LaboratoryAiTeamDiagnosticStore.Report report
                    : diagnostics.list()) {
                for (String recommendation : report.recommendationCodes) {
                    Mapping mapping = map(recommendation);
                    if (mapping == null) continue;
                    proposals.createIfAbsent(
                        report,
                        recommendation,
                        mapping.actionCode,
                        mapping.targetRole);
                }
            }
            return proposals.list();
        }
    }

    private static Mapping map(String recommendation) {
        if ("REVIEW_REPEATED_FAILURES".equals(recommendation)) {
            return new Mapping(
                "RUN_TARGETED_FAILURE_REVIEW",
                LaboratoryAiTeamRegistry.ROLE_REVIEWER);
        }
        if ("REVIEW_REPEATED_CANCELLATIONS".equals(recommendation)) {
            return new Mapping(
                "REVIEW_SESSION_CONTROL_FLOW",
                LaboratoryAiTeamRegistry.ROLE_REVIEWER);
        }
        if ("REVIEW_FREQUENT_INTERRUPTION".equals(recommendation)) {
            return new Mapping(
                "REVIEW_TASK_DECOMPOSITION",
                LaboratoryAiTeamRegistry.ROLE_ORCHESTRATOR);
        }
        if ("REVIEW_BUDGET_FIT".equals(recommendation)) {
            return new Mapping(
                "REVIEW_BUDGET_POLICY",
                LaboratoryAiTeamRegistry.ROLE_REVIEWER);
        }
        if ("PRIORITIZE_REGRESSION_REVIEW".equals(recommendation)) {
            return new Mapping(
                "RUN_REGRESSION_SUITE",
                LaboratoryAiTeamRegistry.ROLE_TESTER);
        }
        if ("REVIEW_RECURRENT_SIGNALS".equals(recommendation)) {
            return new Mapping(
                "CORRELATE_RECURRENT_FAILURE_PATTERN",
                LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC);
        }
        return null;
    }

    private static final class Mapping {
        final String actionCode;
        final String targetRole;

        Mapping(String actionCode, String targetRole) {
            this.actionCode = actionCode;
            this.targetRole = targetRole;
        }
    }
}
