package com.cafeina.executor;

import android.content.Context;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Read-only deterministic diagnostics for every AI session.
 *
 * It never owns HostHandle/AiHandle and cannot pause, resume, cancel or execute
 * tools. It only reads the bounded session audit and writes a diagnostic
 * snapshot with reason/recommendation codes.
 */
public final class LaboratoryAiDiagnostics {
    private static final ExecutorService IO =
        Executors.newSingleThreadExecutor();

    private LaboratoryAiDiagnostics() {}

    public static void schedule(Context context, String projectId,
            String sessionId) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        IO.execute(() -> {
            try {
                analyzeNow(app, projectId, sessionId);
            } catch (Exception ignored) {
                // Diagnostics must never change session control or execution.
            }
        });
    }

    static LaboratoryAiDiagnosticStore.Report analyzeNow(
            Context context, String projectId, String sessionId)
            throws IOException {
        if (context == null) {
            throw new IllegalArgumentException("diagnostic context missing");
        }
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(context.getFilesDir(), projectId);
        LaboratoryAiSessionStore.Summary summary = null;
        for (LaboratoryAiSessionStore.Summary candidate : sessions.list()) {
            if (candidate.sessionId.equals(sessionId)) {
                summary = candidate;
                break;
            }
        }
        if (summary == null) {
            throw new IOException("AI session audit not found for diagnostic");
        }

        List<LaboratoryAiSessionStore.Event> events =
            sessions.readEvents(sessionId);
        int invocationResults = 0;
        int failedInvocations = 0;
        int cancelledInvocations = 0;
        int pauseCount = 0;
        String terminalReason = "";

        for (LaboratoryAiSessionStore.Event event : events) {
            if (LaboratoryAiSessionStore.INVOKE_RESULT.equals(event.type)) {
                invocationResults++;
                if ("CANCELLED".equals(event.outcome)) {
                    cancelledInvocations++;
                } else if (!"PASS".equals(event.outcome)
                        && !"PAUSED".equals(event.outcome)) {
                    failedInvocations++;
                }
            }
            if (LaboratoryAiSessionStore.PAUSE.equals(event.type)) {
                pauseCount++;
            }
            if (LaboratoryAiSessionStore.FINISH.equals(event.type)
                    || LaboratoryAiSessionStore.CANCEL.equals(event.type)
                    || LaboratoryAiSessionStore.INTERRUPT.equals(event.type)
                    || LaboratoryAiSessionStore.RECOVERY_CLOSE.equals(event.type)) {
                terminalReason = event.outcome;
            }
        }

        int invocationPercent = percent(
            summary.invocationsUsed, summary.maxInvocations);
        int inputPercent = percent(
            summary.inputBytesUsed, summary.maxTotalInputBytes);

        List<String> recommendations = new ArrayList<>();
        if (failedInvocations > 0) {
            recommendations.add("INSPECT_TOOL_FAILURES");
        }
        if (cancelledInvocations > 0
                || "CANCELLED".equals(summary.state)) {
            recommendations.add("REVIEW_CANCELLATION_CAUSE");
        }
        if (pauseCount >= 2) {
            recommendations.add("REVIEW_FREQUENT_PAUSES");
        }
        if (invocationPercent >= 80
                && !"FINISHED".equals(summary.state)
                && !"CANCELLED".equals(summary.state)) {
            recommendations.add("NEAR_INVOCATION_BUDGET");
        }
        if (inputPercent >= 80
                && !"FINISHED".equals(summary.state)
                && !"CANCELLED".equals(summary.state)) {
            recommendations.add("NEAR_INPUT_BUDGET");
        }
        if (terminalReason.contains("TIME")) {
            recommendations.add("REVIEW_TIME_BUDGET");
        }
        if (terminalReason.contains("BUDGET")) {
            recommendations.add("REDUCE_OR_SPLIT_PLAN");
        }
        if (recommendations.isEmpty()) {
            recommendations.add("NO_ACTION");
        }

        String severity;
        if (failedInvocations > 0 || "CANCELLED".equals(summary.state)) {
            severity = "FAILURE";
        } else if (recommendations.size() > 1
                || !"NO_ACTION".equals(recommendations.get(0))) {
            severity = "ATTENTION";
        } else {
            severity = "HEALTHY";
        }

        LaboratoryAiDiagnosticStore.Report report =
            new LaboratoryAiDiagnosticStore.Report(
                sessionId,
                sessionId,
                System.currentTimeMillis(),
                summary.state,
                terminalReason,
                severity,
                summary.eventCount,
                invocationResults,
                failedInvocations,
                cancelledInvocations,
                pauseCount,
                invocationPercent,
                inputPercent,
                recommendations);
        new LaboratoryAiDiagnosticStore(
            context.getFilesDir(), projectId).save(report);
        return report;
    }

    private static int percent(int used, int max) {
        if (max <= 0 || used <= 0) return 0;
        long value = (used * 100L) / max;
        return (int) Math.max(0L, Math.min(100L, value));
    }
}
