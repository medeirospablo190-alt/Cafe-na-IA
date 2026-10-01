package com.cafeina.executor;

import android.content.Context;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Read-only deterministic diagnostics across AI-team members.
 *
 * It consumes only sanitized per-session diagnostics and immutable
 * session-to-agent attribution. It never owns session/tool handles.
 */
public final class LaboratoryAiTeamDiagnostics {
    private static final ExecutorService IO =
        Executors.newSingleThreadExecutor();

    private LaboratoryAiTeamDiagnostics() {}

    public static void schedule(Context context, String projectId) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try {
                analyzeAllNow(app, projectId);
            } catch (Exception ignored) {
                // Team diagnostics can never alter or block AI execution.
            }
        });
    }

    static List<LaboratoryAiTeamDiagnosticStore.Report> analyzeAllNow(
            Context context, String projectId) throws IOException {
        if (context == null) {
            throw new IllegalArgumentException("team diagnostic context missing");
        }

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(context.getFilesDir(), projectId);
        team.registerMember(
            "diagnostic-agent",
            "IA de Diagnóstico",
            LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC);

        Map<String, LaboratoryAiDiagnosticStore.Report> bySession =
            new HashMap<>();
        for (LaboratoryAiDiagnosticStore.Report report
                : new LaboratoryAiDiagnosticStore(
                    context.getFilesDir(), projectId).list()) {
            bySession.put(report.sessionId, report);
        }

        Map<String, List<LaboratoryAiDiagnosticStore.Report>> byAgent =
            new LinkedHashMap<>();
        for (LaboratoryAiTeamRegistry.Member member : team.listMembers()) {
            byAgent.put(member.agentId, new ArrayList<>());
        }
        for (LaboratoryAiTeamRegistry.Binding binding : team.listBindings()) {
            LaboratoryAiDiagnosticStore.Report diagnostic =
                bySession.get(binding.sessionId);
            if (diagnostic == null) continue;
            List<LaboratoryAiDiagnosticStore.Report> reports =
                byAgent.get(binding.agentId);
            if (reports != null) reports.add(diagnostic);
        }

        LaboratoryAiTeamDiagnosticStore store =
            new LaboratoryAiTeamDiagnosticStore(
                context.getFilesDir(), projectId);
        List<LaboratoryAiTeamDiagnosticStore.Report> result =
            new ArrayList<>();

        for (LaboratoryAiTeamRegistry.Member member : team.listMembers()) {
            List<LaboratoryAiDiagnosticStore.Report> reports =
                byAgent.get(member.agentId);
            if (reports == null) reports = new ArrayList<>();
            reports.sort(Comparator
                .comparingLong(report -> report.analyzedAtEpochMs));

            LaboratoryAiTeamDiagnosticStore.Report aggregate =
                aggregate(member, reports);
            store.save(aggregate);
            result.add(aggregate);
        }

        result.sort(Comparator
            .comparingInt((LaboratoryAiTeamDiagnosticStore.Report report) ->
                LaboratoryAiTeamDiagnosticStore.severityRank(
                    report.latestSeverity))
            .reversed()
            .thenComparing(report -> report.displayName)
            .thenComparing(report -> report.agentId));
        LaboratoryAiImprovementPlanner.schedule(context, projectId);
        return Collections.unmodifiableList(result);
    }

    private static LaboratoryAiTeamDiagnosticStore.Report aggregate(
            LaboratoryAiTeamRegistry.Member member,
            List<LaboratoryAiDiagnosticStore.Report> reports) {
        int healthy = 0;
        int attention = 0;
        int failures = 0;
        int failedInvocations = 0;
        int cancelledInvocations = 0;
        int pauseCount = 0;
        long invocationUseTotal = 0;
        long inputUseTotal = 0;
        Map<String, Integer> signalCounts = new HashMap<>();

        for (LaboratoryAiDiagnosticStore.Report report : reports) {
            if ("HEALTHY".equals(report.severity)) healthy++;
            else if ("ATTENTION".equals(report.severity)) attention++;
            else if ("FAILURE".equals(report.severity)) failures++;

            failedInvocations += report.failedInvocations;
            cancelledInvocations += report.cancelledInvocations;
            pauseCount += report.pauseCount;
            invocationUseTotal += report.invocationUsePercent;
            inputUseTotal += report.inputUsePercent;

            for (String code : report.recommendationCodes) {
                if ("NO_ACTION".equals(code)) continue;
                signalCounts.put(code,
                    signalCounts.containsKey(code)
                        ? signalCounts.get(code) + 1 : 1);
            }
        }

        int count = reports.size();
        int avgInvocation = count == 0 ? 0
            : (int) Math.min(100L, invocationUseTotal / count);
        int avgInput = count == 0 ? 0
            : (int) Math.min(100L, inputUseTotal / count);

        List<String> recurrent = new ArrayList<>();
        List<String> signalNames = new ArrayList<>(signalCounts.keySet());
        Collections.sort(signalNames);
        for (String code : signalNames) {
            int occurrences = signalCounts.get(code);
            if (occurrences >= 2
                    && occurrences * 2 >= Math.max(1, count)) {
                recurrent.add(code);
            }
        }

        List<String> recommendations = new ArrayList<>();
        if (count == 0) {
            recommendations.add("WAIT_FOR_SESSION_DATA");
        } else {
            if (failures >= 2 || failedInvocations >= 2) {
                recommendations.add("REVIEW_REPEATED_FAILURES");
            }
            if (cancelledInvocations >= 2) {
                recommendations.add("REVIEW_REPEATED_CANCELLATIONS");
            }
            if (pauseCount >= 4) {
                recommendations.add("REVIEW_FREQUENT_INTERRUPTION");
            }
            if (avgInvocation >= 80 || avgInput >= 80) {
                recommendations.add("REVIEW_BUDGET_FIT");
            }
        }

        String trend = trend(reports);
        if ("DEGRADING".equals(trend)) {
            recommendations.add("PRIORITIZE_REGRESSION_REVIEW");
        }
        if (!recurrent.isEmpty()) {
            recommendations.add("REVIEW_RECURRENT_SIGNALS");
        }
        if (recommendations.isEmpty()) {
            recommendations.add("NO_TEAM_ACTION");
        }

        LaboratoryAiDiagnosticStore.Report latest =
            count == 0 ? null : reports.get(count - 1);

        return new LaboratoryAiTeamDiagnosticStore.Report(
            member.agentId,
            member.agentId,
            member.displayName,
            member.role,
            System.currentTimeMillis(),
            count,
            healthy,
            attention,
            failures,
            failedInvocations,
            cancelledInvocations,
            pauseCount,
            avgInvocation,
            avgInput,
            trend,
            latest == null ? "" : latest.sessionId,
            latest == null ? "" : latest.severity,
            recurrent,
            recommendations);
    }

    private static String trend(
            List<LaboratoryAiDiagnosticStore.Report> reports) {
        if (reports.size() < 4) return "INSUFFICIENT_DATA";
        int size = reports.size();
        int olderScore = severity(
            reports.get(size - 4)) + severity(reports.get(size - 3));
        int newerScore = severity(
            reports.get(size - 2)) + severity(reports.get(size - 1));
        if (newerScore < olderScore) return "IMPROVING";
        if (newerScore > olderScore) return "DEGRADING";
        return "STABLE";
    }

    private static int severity(
            LaboratoryAiDiagnosticStore.Report report) {
        return Math.max(0,
            LaboratoryAiTeamDiagnosticStore.severityRank(report.severity));
    }
}
