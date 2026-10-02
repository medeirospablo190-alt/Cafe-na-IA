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

        public final String explanation;
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
                String explanation,
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
            this.explanation = explanation;
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
            explanation,
            nextCheck);
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
