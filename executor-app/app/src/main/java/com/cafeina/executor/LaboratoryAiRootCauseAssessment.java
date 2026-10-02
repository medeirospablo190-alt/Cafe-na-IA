package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Deterministic evidence correlation for one AI action.
 *
 * It never asks the model to infer a cause. Confirmed findings come from
 * terminal states/audits; supporting findings are explicitly labeled as
 * correlation signals, not proof of causation.
 */
public final class LaboratoryAiRootCauseAssessment {
    public enum Strength {
        CONFIRMED,
        SUPPORTING,
        CONTEXT
    }

    public static final class Finding {
        public final Strength strength;
        public final String code;
        public final String title;
        public final String detail;

        private Finding(
                Strength strength,
                String code,
                String title,
                String detail) {
            this.strength = strength;
            this.code = code;
            this.title = title;
            this.detail = detail;
        }
    }

    public static final class Result {
        public final List<Finding> findings;

        private Result(List<Finding> findings) {
            this.findings = Collections.unmodifiableList(
                new ArrayList<>(findings));
        }

        public boolean hasConfirmedFailure() {
            for (Finding finding : findings) {
                if (finding.strength == Strength.CONFIRMED
                        && !"NO_TERMINAL_FAILURE".equals(finding.code)
                        && !"USER_CANCELLED".equals(finding.code)) {
                    return true;
                }
            }
            return false;
        }
    }

    private LaboratoryAiRootCauseAssessment() {}

    public static Result assess(
            LaboratoryAiActionDiagnostic.Snapshot snapshot) {
        if (snapshot == null) {
            return result(
                finding(
                    Strength.CONTEXT,
                    "DIAGNOSTIC_SNAPSHOT_MISSING",
                    "Diagnóstico indisponível",
                    "Não existe snapshot suficiente para correlacionar evidências."));
        }

        List<Finding> findings = new ArrayList<>();

        addPlannerFailure(snapshot, findings);
        addPlannerTelemetry(snapshot, findings);
        addEnvironmentSignals(snapshot, findings);
        addTestAgentEvidence(snapshot, findings);

        if (findings.isEmpty()) {
            findings.add(finding(
                Strength.CONTEXT,
                "NO_TERMINAL_FAILURE",
                "Nenhuma falha terminal confirmada",
                "Os registros atuais não contêm uma falha terminal para esta ação."));
        }

        return new Result(findings);
    }

    private static void addPlannerFailure(
            LaboratoryAiActionDiagnostic.Snapshot snapshot,
            List<Finding> findings) {
        LaboratoryAiPlannerExecutionDiagnostic.Result diagnosis =
            snapshot.plannerDiagnostic;
        if (diagnosis == null) return;

        switch (diagnosis.code) {
            case RUNNING:
                findings.add(finding(
                    Strength.CONTEXT,
                    "PLANNER_RUNNING",
                    "Planejador ainda sem terminal",
                    diagnosis.explanation));
                return;
            case COMPLETED:
                findings.add(finding(
                    Strength.CONTEXT,
                    "PLANNER_COMPLETED",
                    "Planejador concluiu",
                    diagnosis.explanation));
                return;
            case USER_CANCELLED:
                findings.add(finding(
                    Strength.CONFIRMED,
                    "USER_CANCELLED",
                    "Execução cancelada pelo usuário",
                    diagnosis.explanation));
                return;
            default:
                findings.add(finding(
                    Strength.CONFIRMED,
                    "PLANNER_" + diagnosis.code.name(),
                    "Falha confirmada no planejador",
                    diagnosis.explanation
                        + " Próxima verificação: "
                        + diagnosis.nextCheck));
        }
    }

    private static void addPlannerTelemetry(
            LaboratoryAiActionDiagnostic.Snapshot snapshot,
            List<Finding> findings) {
        LaboratoryAiExecutionHistoryStore.Summary planner =
            snapshot.planner;
        if (planner == null) return;

        if (planner.promptTokensProcessed > 0
                && planner.promptEvalMs > 0L) {
            double rate =
                planner.promptTokensProcessed * 1000.0
                    / planner.promptEvalMs;
            String detail =
                planner.promptTokensProcessed + "/"
                    + planner.promptTokens
                    + " tokens do prompt em "
                    + planner.promptEvalMs
                    + " ms • "
                    + formatRate(rate)
                    + " tok/s observados.";
            if (planner.promptTokens > planner.promptTokensProcessed
                    && rate > 0.0) {
                long remaining =
                    Math.max(
                        0L,
                        Math.round(
                            (planner.promptTokens
                                - planner.promptTokensProcessed)
                                * 1000.0 / rate));
                detail += " No mesmo ritmo, os tokens restantes exigiriam ~"
                    + remaining + " ms.";
            }
            findings.add(finding(
                Strength.SUPPORTING,
                "PROMPT_THROUGHPUT_OBSERVED",
                "Ritmo medido do prompt",
                detail));
        }

        if (planner.generatedTokens > 0
                && planner.tokenGenerationMs > 0L) {
            double rate =
                planner.generatedTokens * 1000.0
                    / planner.tokenGenerationMs;
            findings.add(finding(
                Strength.SUPPORTING,
                "TOKEN_THROUGHPUT_OBSERVED",
                "Ritmo medido da geração",
                planner.generatedTokens + "/"
                    + planner.maxGeneratedTokens
                    + " tokens em "
                    + planner.tokenGenerationMs
                    + " ms • "
                    + formatRate(rate)
                    + " tok/s observados."));
        }
    }

    private static void addEnvironmentSignals(
            LaboratoryAiActionDiagnostic.Snapshot snapshot,
            List<Finding> findings) {
        LaboratoryAiPlannerEnvironmentStore.Snapshot env =
            snapshot.plannerEnvironment;
        if (env == null) return;

        if (env.signalCodes.contains(
                LaboratoryAiLocalModelPreflight.ANDROID_LOW_MEMORY)) {
            findings.add(finding(
                Strength.SUPPORTING,
                "ANDROID_LOW_MEMORY_SIGNAL",
                "Android reportou pressão de memória",
                "O preflight registrou lowMemory=true. Isso aumenta o risco "
                    + "de falha/carga lenta, mas não prova sozinho a causa."));
        }

        if (env.signalCodes.contains(
                LaboratoryAiLocalModelPreflight
                    .MODEL_LARGER_THAN_AVAILABLE_RAM)) {
            findings.add(finding(
                Strength.SUPPORTING,
                "MODEL_RAM_FIT_SIGNAL",
                "Modelo maior que a RAM disponível no preflight",
                "Modelo: " + env.modelSizeBytes
                    + " bytes • RAM disponível: "
                    + env.availableRamBytes
                    + " bytes. É um sinal de pressão, não uma prova isolada."));
        }

        if (env.signalCodes.contains(
                LaboratoryAiLocalModelPreflight.RUNTIME_NOT_PACKAGED)) {
            findings.add(finding(
                Strength.CONFIRMED,
                "RUNTIME_NOT_PACKAGED",
                "Runtime local não estava empacotado",
                "O próprio preflight registrou ausência do runtime nativo."));
        }

        if (env.signalCodes.isEmpty()
                && snapshot.plannerDiagnostic != null
                && snapshot.plannerDiagnostic.code
                    != LaboratoryAiPlannerExecutionDiagnostic.Code.COMPLETED
                && snapshot.plannerDiagnostic.code
                    != LaboratoryAiPlannerExecutionDiagnostic.Code.RUNNING) {
            findings.add(finding(
                Strength.CONTEXT,
                "NO_PREFLIGHT_PRESSURE_SIGNAL",
                "Preflight sem sinal de pressão",
                "Nenhum sinal de low-memory, runtime ausente ou modelo maior "
                    + "que a RAM disponível foi registrado no preflight. "
                    + "Isso não exclui outros gargalos."));
        }

        findings.add(finding(
            Strength.CONTEXT,
            "PLANNER_RUNTIME_CONFIGURATION",
            "Configuração usada pelo planejador",
            env.contextTokens + " tokens de contexto • "
                + env.maxTokens + " tokens máximos de saída • "
                + env.threads + " thread(s) • timeout "
                + env.maxGenerationMs + " ms."));
    }

    private static void addTestAgentEvidence(
            LaboratoryAiActionDiagnostic.Snapshot snapshot,
            List<Finding> findings) {
        if (snapshot.testReport != null) {
            if (snapshot.testReport.failed > 0) {
                findings.add(finding(
                    Strength.CONFIRMED,
                    "TEST_AGENT_STEP_FAILURE",
                    "A Testadora registrou passo(s) com falha",
                    snapshot.testReport.failed + " de "
                        + snapshot.testReport.executedSteps
                        + " passo(s) executado(s) falharam."));
            } else if ("PASS".equals(snapshot.testReport.status)) {
                findings.add(finding(
                    Strength.CONTEXT,
                    "TEST_AGENT_PASS",
                    "Testadora concluiu sem falha",
                    snapshot.testReport.executedSteps + "/"
                        + snapshot.testReport.plannedSteps
                        + " passo(s) concluídos."));
            }
            return;
        }

        LaboratoryAiSessionStore.Summary session =
            snapshot.testSession;
        if (session == null) return;

        boolean live =
            LaboratoryAiSessionController.isLiveSession(
                session.sessionId);
        if (("ACTIVE".equals(session.state)
                || "PAUSED".equals(session.state))
                && !live) {
            findings.add(finding(
                Strength.CONFIRMED,
                "TEST_AGENT_PROCESS_INTERRUPTED",
                "Sessão da Testadora perdeu o processo",
                "O audit persiste estado " + session.state
                    + ", mas a sessão não está viva no processo atual."));
        } else if (!"ACTIVE".equals(session.state)
                && !"PAUSED".equals(session.state)
                && !"FINISHED".equals(session.state)) {
            findings.add(finding(
                Strength.SUPPORTING,
                "TEST_AGENT_NON_TERMINAL_AUDIT",
                "Sessão da Testadora requer recuperação",
                "Estado auditado: " + session.state + "."));
        }
    }

    private static Finding finding(
            Strength strength,
            String code,
            String title,
            String detail) {
        return new Finding(
            strength,
            code,
            title,
            detail == null ? "" : detail);
    }

    private static Result result(Finding finding) {
        List<Finding> findings = new ArrayList<>();
        findings.add(finding);
        return new Result(findings);
    }

    private static String formatRate(double value) {
        if (Double.isNaN(value)
                || Double.isInfinite(value)
                || value <= 0.0) {
            return "0.0";
        }
        return String.format(Locale.ROOT, "%.1f", value);
    }
}
