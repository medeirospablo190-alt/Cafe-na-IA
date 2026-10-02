package com.cafeina.executor;

import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Read-only, derived timeline for one controlled AI action.
 *
 * No new audit is written here. The timeline joins the existing Goal Lock,
 * planner history/checkpoint, optional prepared scenario, TestAgent session
 * audit and terminal result records.
 */
public final class LaboratoryAiActionTimeline {
    public enum Source {
        GOAL_LOCK,
        PLANNER,
        SCENARIO,
        TEST_AGENT,
        RESULT
    }

    public static final class Item {
        public final long atEpochMs;
        public final Source source;
        public final String title;
        public final String detail;
        public final String code;

        private Item(
                long atEpochMs,
                Source source,
                String title,
                String detail,
                String code) {
            this.atEpochMs = atEpochMs;
            this.source = source;
            this.title = title;
            this.detail = detail;
            this.code = code;
        }
    }

    public static final class Snapshot {
        public final String contractId;
        public final List<Item> items;

        private Snapshot(String contractId, List<Item> items) {
            this.contractId = contractId;
            this.items = Collections.unmodifiableList(
                new ArrayList<>(items));
        }
    }

    private LaboratoryAiActionTimeline() {}

    public static Snapshot inspect(
            File filesDir,
            String projectId,
            String contractId,
            String scenarioId) throws IOException {
        if (filesDir == null
                || contractId == null
                || contractId.isEmpty()) {
            throw new IllegalArgumentException(
                "action timeline input missing");
        }

        String safeProjectId = projectId == null ? "" : projectId;
        LaboratoryAiTaskContractStore contracts =
            new LaboratoryAiTaskContractStore(
                filesDir, safeProjectId);
        LaboratoryAiTaskContractStore.Contract contract =
            contracts.read(contractId);

        List<Item> items = new ArrayList<>();
        items.add(new Item(
            contract.createdAtEpochMs,
            Source.GOAL_LOCK,
            "Goal Lock criado",
            contract.mode.name()
                + " • " + contract.allowedToolIds.size()
                + " ferramenta(s) • orçamento "
                + contract.maxInvocations + " chamada(s), "
                + contract.maxTotalInputBytes + " bytes, "
                + contract.maxSessionMs + " ms",
            "GOAL_LOCK_CREATED"));

        if (contract.claimed) {
            try {
                LaboratoryAiTaskContractStore.Claim claim =
                    contracts.readClaim(contractId);
                items.add(new Item(
                    claim.claimedAtEpochMs,
                    Source.GOAL_LOCK,
                    "Goal Lock consumido",
                    "Admissão de execução de uso único registrada.",
                    "GOAL_LOCK_CLAIMED"));
            } catch (IOException ignored) {
                // The contract integrity check still owns authoritative state.
            }
        }

        if (contract.resultRecorded) {
            try {
                LaboratoryAiTaskContractStore.Result result =
                    contracts.readResult(contractId);
                items.add(new Item(
                    result.recordedAtEpochMs,
                    Source.RESULT,
                    "Resultado do contrato registrado",
                    result.status
                        + (result.reason == null
                            || result.reason.isEmpty()
                                ? ""
                                : " • " + result.reason),
                    "CONTRACT_RESULT"));
            } catch (IOException ignored) {
                // Other audit sources may still explain the action.
            }
        }

        addPlannerTimeline(
            filesDir,
            safeProjectId,
            contractId,
            items);
        addScenarioTimeline(
            filesDir,
            safeProjectId,
            scenarioId,
            items);
        addTestAgentTimeline(
            filesDir,
            safeProjectId,
            contractId,
            items);

        items.sort(Comparator
            .comparingLong((Item item) -> item.atEpochMs)
            .thenComparing(item -> item.source.name())
            .thenComparing(item -> item.code));

        return new Snapshot(contractId, items);
    }

    private static void addPlannerTimeline(
            File filesDir,
            String projectId,
            String contractId,
            List<Item> items) throws IOException {
        LaboratoryAiExecutionHistoryStore history =
            new LaboratoryAiExecutionHistoryStore(
                filesDir, projectId);
        boolean hasHistory = false;
        for (LaboratoryAiExecutionHistoryStore.Summary summary :
                history.list()) {
            if (!contractId.equals(summary.contractId)) continue;
            hasHistory = true;
            for (LaboratoryAiExecutionHistoryStore.Event event :
                    history.readEvents(summary.executionId)) {
                items.add(new Item(
                    event.updatedAtEpochMs,
                    Source.PLANNER,
                    plannerTitle(event),
                    plannerDetail(event),
                    "PLANNER_" + event.state.name()
                        + "_" + event.phase.name()));
            }
        }

        if (!hasHistory) {
            LaboratoryAiPlannerCheckpointStore.Checkpoint checkpoint =
                new LaboratoryAiPlannerCheckpointStore(
                    filesDir, projectId)
                    .read(contractId);
            if (checkpoint != null) {
                StringBuilder detail = new StringBuilder()
                    .append("Último checkpoint • ")
                    .append(checkpoint.detail)
                    .append(" • ")
                    .append(checkpoint.elapsedMs)
                    .append(" ms");
                if (checkpoint.promptTokens > 0) {
                    detail.append(" • prompt ")
                        .append(checkpoint.promptTokensProcessed)
                        .append("/")
                        .append(checkpoint.promptTokens);
                }
                if (checkpoint.maxGeneratedTokens > 0) {
                    detail.append(" • saída ")
                        .append(checkpoint.generatedTokens)
                        .append("/")
                        .append(checkpoint.maxGeneratedTokens);
                }
                items.add(new Item(
                    checkpoint.updatedAtEpochMs,
                    Source.PLANNER,
                    "Checkpoint do planejador",
                    detail.toString(),
                    "PLANNER_CHECKPOINT_"
                        + checkpoint.phase.name()));
            }
        }
    }

    private static String plannerTitle(
            LaboratoryAiExecutionHistoryStore.Event event) {
        switch (event.state) {
            case COMPLETED:
                return "Planejamento concluído";
            case FAILED:
                return "Planejamento falhou";
            case CANCELLED:
                return "Planejamento cancelado";
            case RUNNING:
            default:
                return "Planejador • " + event.phase.name();
        }
    }

    private static String plannerDetail(
            LaboratoryAiExecutionHistoryStore.Event event) {
        StringBuilder detail = new StringBuilder()
            .append(event.detail)
            .append(" • ")
            .append(event.elapsedMs)
            .append(" ms");
        if (event.attempt > 0 && event.maxAttempts > 0) {
            detail.append(" • tentativa ")
                .append(event.attempt)
                .append("/")
                .append(event.maxAttempts);
        }
        if (event.promptTokens > 0) {
            detail.append(" • prompt ")
                .append(event.promptTokensProcessed)
                .append("/")
                .append(event.promptTokens);
        }
        if (event.maxGeneratedTokens > 0) {
            detail.append(" • saída ")
                .append(event.generatedTokens)
                .append("/")
                .append(event.maxGeneratedTokens);
        }
        if (event.terminalReason != null
                && !event.terminalReason.isEmpty()) {
            detail.append(" • ")
                .append(event.terminalReason);
        }
        return detail.toString();
    }

    private static void addScenarioTimeline(
            File filesDir,
            String projectId,
            String scenarioId,
            List<Item> items) {
        if (scenarioId == null || scenarioId.isEmpty()) return;
        try {
            LaboratoryAiTestScenarioStore.Scenario scenario =
                new LaboratoryAiTestScenarioStore(
                    filesDir, projectId)
                    .read(scenarioId);
            items.add(new Item(
                scenario.createdAtEpochMs,
                Source.SCENARIO,
                "Cenário da Testadora preparado",
                scenario.stepCount + " passo(s) • stop on failure: "
                    + (scenario.stopOnFailure ? "SIM" : "NÃO"),
                "TEST_SCENARIO_PREPARED"));
        } catch (Exception ignored) {
            // Scenario is optional context, never required for the timeline.
        }
    }

    private static void addTestAgentTimeline(
            File filesDir,
            String projectId,
            String contractId,
            List<Item> items) throws IOException {
        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(filesDir, projectId);
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(filesDir, projectId);

        for (LaboratoryAiTeamRegistry.Binding binding :
                team.listBindings()) {
            if (!contractId.equals(binding.contractId)
                    || !"test-agent".equals(binding.agentId)) {
                continue;
            }

            items.add(new Item(
                binding.boundAtEpochMs,
                Source.TEST_AGENT,
                "Testadora ligada à ação",
                "Sessão " + shortId(binding.sessionId)
                    + " atribuída ao Goal Lock.",
                "TEST_AGENT_BOUND"));

            List<LaboratoryAiSessionStore.Event> events;
            try {
                events = sessions.readEvents(binding.sessionId);
            } catch (IOException missing) {
                continue;
            }

            for (LaboratoryAiSessionStore.Event event : events) {
                items.add(new Item(
                    event.createdAtEpochMs,
                    Source.TEST_AGENT,
                    sessionTitle(event),
                    sessionDetail(event),
                    "SESSION_" + event.type));
            }
        }

        for (LaboratoryAiTestAgentReportStore.Entry report :
                new LaboratoryAiTestAgentReportStore(
                    filesDir, projectId)
                    .list()) {
            if (!contractId.equals(report.contractId)) continue;
            long at = report.startedAtEpochMs;
            try {
                JSONObject raw = new JSONObject(report.reportText);
                at += Math.max(0L, raw.optLong("durationMs", 0L));
            } catch (Exception ignored) {
                // Start time is still valid ordering information.
            }
            items.add(new Item(
                at,
                Source.RESULT,
                "Relatório da Testadora",
                report.status + " • "
                    + report.executedSteps + "/"
                    + report.plannedSteps + " passo(s) • "
                    + report.passed + " passou/passaram • "
                    + report.failed + " falhou/falharam",
                "TEST_AGENT_REPORT"));
        }
    }

    private static String sessionTitle(
            LaboratoryAiSessionStore.Event event) {
        switch (event.type) {
            case LaboratoryAiSessionStore.START:
                return "Sessão da Testadora iniciada";
            case LaboratoryAiSessionStore.INVOKE_REQUEST:
                return "Ferramenta solicitada";
            case LaboratoryAiSessionStore.INVOKE_RESULT:
                return "Ferramenta finalizada";
            case LaboratoryAiSessionStore.PAUSE:
                return "Testadora pausada";
            case LaboratoryAiSessionStore.RESUME:
                return "Testadora retomada";
            case LaboratoryAiSessionStore.CANCEL:
                return "Testadora cancelada";
            case LaboratoryAiSessionStore.FINISH:
                return "Sessão da Testadora finalizada";
            case LaboratoryAiSessionStore.INTERRUPT:
                return "Sessão da Testadora interrompida";
            case LaboratoryAiSessionStore.RECOVERY_REQUEST:
                return "Retomada solicitada";
            case LaboratoryAiSessionStore.RECOVERY_CLOSE:
                return "Sessão interrompida encerrada";
            default:
                return "Evento da Testadora";
        }
    }

    private static String sessionDetail(
            LaboratoryAiSessionStore.Event event) {
        StringBuilder detail = new StringBuilder();
        if (event.toolId != null && !event.toolId.isEmpty()) {
            detail.append(event.toolId);
        }
        if (event.outcome != null && !event.outcome.isEmpty()) {
            if (detail.length() > 0) detail.append(" • ");
            detail.append(event.outcome);
        }
        if (detail.length() > 0) detail.append(" • ");
        detail.append(event.invocationsUsed)
            .append(" chamada(s) usada(s) • ")
            .append(event.inputBytesUsed)
            .append(" bytes usados");
        return detail.toString();
    }

    private static String shortId(String value) {
        if (value == null) return "";
        return value.length() <= 8
            ? value
            : value.substring(0, 8);
    }
}
