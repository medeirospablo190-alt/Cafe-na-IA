package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.util.List;

/**
 * Read-only diagnostic snapshot for one user action/Goal Lock.
 *
 * It joins already-persisted contract, planner history and TestAgent report
 * metadata. It never executes tools, changes permissions, consumes a Goal Lock
 * or mutates any task record.
 */
public final class LaboratoryAiActionDiagnostic {
    public enum Stage {
        GOAL_LOCK_READY,
        PLANNER_COMPLETED,
        PLANNER_FAILED,
        TEST_AGENT_RUNNING_OR_INTERRUPTED,
        TEST_AGENT_COMPLETED,
        UNKNOWN
    }

    public static final class Snapshot {
        public final String contractId;
        public final LaboratoryAiTaskContractStore.Mode mode;
        public final int allowedToolCount;
        public final boolean goalLockClaimed;
        public final boolean resultRecorded;
        public final Stage stage;

        public final LaboratoryAiExecutionHistoryStore.Summary planner;
        public final LaboratoryAiPlannerExecutionDiagnostic.Result
            plannerDiagnostic;
        public final LaboratoryAiTestAgentReportStore.Entry testReport;
        public final LaboratoryAiSessionStore.Summary testSession;

        public final String explanation;
        public final String nextStep;
        public final String nextCheck;

        private Snapshot(
                String contractId,
                LaboratoryAiTaskContractStore.Mode mode,
                int allowedToolCount,
                boolean goalLockClaimed,
                boolean resultRecorded,
                Stage stage,
                LaboratoryAiExecutionHistoryStore.Summary planner,
                LaboratoryAiPlannerExecutionDiagnostic.Result
                    plannerDiagnostic,
                LaboratoryAiTestAgentReportStore.Entry testReport,
                LaboratoryAiSessionStore.Summary testSession,
                String explanation,
                String nextStep,
                String nextCheck) {
            this.contractId = contractId;
            this.mode = mode;
            this.allowedToolCount = allowedToolCount;
            this.goalLockClaimed = goalLockClaimed;
            this.resultRecorded = resultRecorded;
            this.stage = stage;
            this.planner = planner;
            this.plannerDiagnostic = plannerDiagnostic;
            this.testReport = testReport;
            this.testSession = testSession;
            this.explanation = explanation;
            this.nextStep = nextStep;
            this.nextCheck = nextCheck;
        }
    }

    private LaboratoryAiActionDiagnostic() {}

    public static Snapshot inspect(
            File filesDir,
            String projectId,
            String contractId) throws IOException {
        if (filesDir == null || contractId == null
                || contractId.isEmpty()) {
            throw new IllegalArgumentException(
                "action diagnostic input missing");
        }

        LaboratoryAiTaskContractStore.Contract contract =
            new LaboratoryAiTaskContractStore(
                filesDir, projectId == null ? "" : projectId)
                .read(contractId);

        LaboratoryAiExecutionHistoryStore.Summary planner =
            latestPlanner(
                filesDir,
                projectId,
                contractId);
        LaboratoryAiPlannerExecutionDiagnostic.Result plannerDiagnosis =
            planner == null
                ? null
                : LaboratoryAiPlannerExecutionDiagnostic.analyze(planner);

        LaboratoryAiTestAgentReportStore.Entry report =
            latestReport(
                filesDir,
                projectId,
                contractId);
        LaboratoryAiSessionStore.Summary testSession =
            report == null || report.sessionId.isEmpty()
                ? null
                : sessionSummary(
                    filesDir,
                    projectId,
                    report.sessionId);

        Stage stage;
        String explanation;
        String nextCheck;

        if (report != null) {
            stage = Stage.TEST_AGENT_COMPLETED;
            explanation =
                "A Testadora já registrou um resultado terminal para esta ação: "
                    + report.status + ".";
            nextCheck = report.failed > 0
                ? "OPEN_TEST_AGENT_REPORT"
                : "NO_FAILURE_TO_DIAGNOSE";
        } else if (contract.claimed && !contract.resultRecorded) {
            stage = Stage.TEST_AGENT_RUNNING_OR_INTERRUPTED;
            explanation =
                "O Goal Lock já foi consumido, mas ainda não existe resultado "
                    + "terminal registrado para esta ação.";
            nextCheck = "OPEN_AI_SESSION_RECOVERY";
        } else if (planner != null
                && planner.state
                    == LaboratoryAiExecutionStatus.State.COMPLETED) {
            stage = Stage.PLANNER_COMPLETED;
            explanation =
                "O planejador concluiu esta ação sem consumir o Goal Lock. "
                    + "A execução prática ainda depende da Testadora.";
            nextCheck = "REVIEW_OR_PREPARE_TEST_AGENT";
        } else if (planner != null) {
            stage = Stage.PLANNER_FAILED;
            explanation = plannerDiagnosis == null
                ? "O planejador possui histórico, mas o diagnóstico não foi classificado."
                : plannerDiagnosis.explanation;
            nextCheck = plannerDiagnosis == null
                ? "OPEN_PLANNER_TIMELINE"
                : plannerDiagnosis.nextCheck;
        } else {
            stage = Stage.GOAL_LOCK_READY;
            explanation =
                "O Goal Lock existe e ainda não há execução do planejador "
                    + "registrada para esta ação.";
            nextCheck = "GENERATE_PLAN_WHEN_USER_REQUESTS";
        }

        return new Snapshot(
            contract.contractId,
            contract.mode,
            contract.allowedToolIds.size(),
            contract.claimed,
            contract.resultRecorded,
            stage,
            planner,
            plannerDiagnosis,
            report,
            testSession,
            explanation,
            userNextStep(nextCheck),
            nextCheck);
    }

    private static String userNextStep(String code) {
        if (code == null || code.isEmpty()) {
            return "Abra a linha do tempo desta ação para localizar o próximo ponto de verificação.";
        }
        switch (code) {
            case "GENERATE_PLAN_WHEN_USER_REQUESTS":
                return "Se quiser continuar, gere o plano. Nenhuma ferramenta será executada nessa etapa.";
            case "REVIEW_OR_PREPARE_TEST_AGENT":
                return "Revise o plano validado e, se estiver correto, prepare a Testadora sem executar ainda.";
            case "OPEN_TEST_AGENT_REPORT":
                return "Abra o relatório da Testadora e veja qual passo ou ferramenta falhou.";
            case "OPEN_AI_SESSION_RECOVERY":
                return "Abra a recuperação da sessão antes de tentar qualquer nova execução.";
            case "NO_FAILURE_TO_DIAGNOSE":
                return "Nenhuma falha foi detectada nesta ação. Você pode revisar o relatório final.";
            case "MEASURE_FIRST_PROMPT_BATCH_LATENCY":
                return "Teste novamente medindo o primeiro batch do prompt; o gargalo aconteceu antes de um batch terminar.";
            case "PROFILE_PROMPT_EVAL_THROUGHPUT":
                return "Compare tamanho do prompt, tokens processados e velocidade para decidir se o limite ou o contexto precisa ser ajustado.";
            case "PROFILE_TOKEN_GENERATION_THROUGHPUT":
                return "Compare a velocidade de geração com o limite de saída e o tempo máximo configurado.";
            case "PROFILE_CONTEXT_SETUP":
            case "MEASURE_CONTEXT_SETUP_AND_MODEL_FIT":
                return "Verifique tempo de criação do contexto e se o modelo/contexto cabem confortavelmente no dispositivo.";
            case "CHECK_MODEL_ADMISSION":
                return "Verifique o arquivo GGUF selecionado e a validação de admissão do modelo.";
            case "CHECK_MEMORY_RUNTIME_AND_MODEL_FIT":
            case "CHECK_MODEL_LOAD_AND_MEMORY":
                return "Verifique memória disponível, tamanho do modelo e configuração do runtime antes de repetir.";
            case "CHECK_PLAN_CONTRACT_VALIDATION":
                return "Abra os erros da validação determinística e ajuste apenas o plano; não execute a Testadora ainda.";
            case "RETRY_ONLY_IF_USER_REQUESTS":
                return "A execução foi cancelada. Só repita se você quiser iniciar outra tentativa.";
            case "OPEN_PLANNER_TIMELINE":
            case "CHECK_FULL_EXECUTION_TIMELINE":
            default:
                return "Abra a linha do tempo do planejador e confira a última fase concluída antes da falha.";
        }
    }

    private static LaboratoryAiExecutionHistoryStore.Summary latestPlanner(
            File filesDir,
            String projectId,
            String contractId) throws IOException {
        List<LaboratoryAiExecutionHistoryStore.Summary> summaries =
            new LaboratoryAiExecutionHistoryStore(
                filesDir, projectId == null ? "" : projectId)
                .list();
        for (LaboratoryAiExecutionHistoryStore.Summary summary : summaries) {
            if (contractId.equals(summary.contractId)) {
                return summary;
            }
        }
        return null;
    }

    private static LaboratoryAiSessionStore.Summary sessionSummary(
            File filesDir,
            String projectId,
            String sessionId) throws IOException {
        List<LaboratoryAiSessionStore.Summary> sessions =
            new LaboratoryAiSessionStore(
                filesDir, projectId == null ? "" : projectId)
                .list();
        for (LaboratoryAiSessionStore.Summary session : sessions) {
            if (sessionId.equals(session.sessionId)) {
                return session;
            }
        }
        return null;
    }

    private static LaboratoryAiTestAgentReportStore.Entry latestReport(
            File filesDir,
            String projectId,
            String contractId) throws IOException {
        List<LaboratoryAiTestAgentReportStore.Entry> reports =
            new LaboratoryAiTestAgentReportStore(
                filesDir, projectId == null ? "" : projectId)
                .list();
        for (LaboratoryAiTestAgentReportStore.Entry report : reports) {
            if (contractId.equals(report.contractId)) {
                return report;
            }
        }
        return null;
    }
}
