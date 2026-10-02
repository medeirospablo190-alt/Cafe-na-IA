package com.cafeina.executor;

import java.util.Locale;

/**
 * Deterministic, read-only classification of a local planner execution.
 *
 * It consumes only the bounded execution-status contract and never changes
 * model limits, retries, Goal Locks, permissions, or tool state.
 */
public final class LaboratoryAiPlannerExecutionDiagnostic {
    public enum Code {
        RUNNING,
        COMPLETED,
        USER_CANCELLED,
        MODEL_ADMISSION_FAILED,
        PREFLIGHT_FAILED,
        MODEL_OPEN_FAILED,
        CONTEXT_TIMEOUT,
        CONTEXT_FAILED,
        PROMPT_TIMEOUT,
        PROMPT_FAILED,
        TOKEN_TIMEOUT,
        TOKEN_GENERATION_FAILED,
        PLAN_VALIDATION_FAILED,
        PLANNER_FAILED,
        UNKNOWN_FAILURE
    }

    public static final class Result {
        public final Code code;
        public final String explanation;
        public final String nextCheck;

        private Result(
                Code code,
                String explanation,
                String nextCheck) {
            this.code = code;
            this.explanation = explanation;
            this.nextCheck = nextCheck;
        }
    }

    private LaboratoryAiPlannerExecutionDiagnostic() {}

    public static Result analyze(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        if (snapshot == null) {
            return result(
                Code.UNKNOWN_FAILURE,
                "Não existe snapshot suficiente para localizar a falha.",
                "CHECK_EXECUTION_STATUS_SOURCE");
        }
        return analyze(
            snapshot.state,
            snapshot.phase,
            snapshot.terminalReason);
    }

    public static Result analyze(
            LaboratoryAiExecutionStatus.State state,
            LaboratoryAiExecutionStatus.Phase phase,
            String terminalReason) {
        if (state == null || phase == null) {
            return result(
                Code.UNKNOWN_FAILURE,
                "O estado da execução está incompleto.",
                "CHECK_EXECUTION_STATUS_SOURCE");
        }

        if (state
                == LaboratoryAiExecutionStatus.State.RUNNING) {
            return result(
                Code.RUNNING,
                "A execução ainda não chegou a um estado terminal.",
                "WAIT_FOR_TERMINAL_STATE");
        }

        if (state
                == LaboratoryAiExecutionStatus.State.COMPLETED) {
            return result(
                Code.COMPLETED,
                "O planejador concluiu o fluxo de geração e validação.",
                "NO_FAILURE_TO_DIAGNOSE");
        }

        if (state
                == LaboratoryAiExecutionStatus.State.CANCELLED) {
            return result(
                Code.USER_CANCELLED,
                "A execução foi cancelada antes da conclusão.",
                "RETRY_ONLY_IF_USER_REQUESTS");
        }

        String reason = terminalReason == null
            ? ""
            : terminalReason.toLowerCase(Locale.ROOT);
        boolean timeout =
            reason.contains("timed out")
                || reason.contains("timeout");

        switch (phase) {
            case MODEL_ADMISSION:
                return result(
                    Code.MODEL_ADMISSION_FAILED,
                    "A falha ocorreu durante a admissão do arquivo do modelo.",
                    "CHECK_MODEL_ADMISSION");
            case PREFLIGHT:
                return result(
                    Code.PREFLIGHT_FAILED,
                    "A falha ocorreu antes de abrir o modelo, durante o preflight do dispositivo.",
                    "CHECK_MEMORY_RUNTIME_AND_MODEL_FIT");
            case MODEL_OPEN:
                return result(
                    Code.MODEL_OPEN_FAILED,
                    "O runtime não conseguiu concluir a abertura do modelo local.",
                    "CHECK_MODEL_LOAD_AND_MEMORY");
            case MODEL_CONTEXT:
                return timeout
                    ? result(
                        Code.CONTEXT_TIMEOUT,
                        "O prazo terminou enquanto o runtime preparava o contexto do modelo.",
                        "MEASURE_CONTEXT_SETUP_AND_MODEL_FIT")
                    : result(
                        Code.CONTEXT_FAILED,
                        "A falha ocorreu enquanto o runtime preparava o contexto do modelo.",
                        "CHECK_CONTEXT_SETUP");
            case MODEL_PROMPT:
                return timeout
                    ? result(
                        Code.PROMPT_TIMEOUT,
                        "O prazo terminou enquanto o modelo processava o prompt, antes da geração normal de tokens.",
                        "MEASURE_PROMPT_TOKENS_AND_PROMPT_EVAL_SPEED")
                    : result(
                        Code.PROMPT_FAILED,
                        "A falha ocorreu enquanto o modelo processava o prompt.",
                        "CHECK_PROMPT_PROCESSING");
            case MODEL_TOKENS:
                return timeout
                    ? result(
                        Code.TOKEN_TIMEOUT,
                        "O prazo terminou durante a geração de tokens da resposta.",
                        "MEASURE_TOKEN_GENERATION_SPEED_AND_OUTPUT_LIMIT")
                    : result(
                        Code.TOKEN_GENERATION_FAILED,
                        "A falha ocorreu durante a geração de tokens da resposta.",
                        "CHECK_TOKEN_GENERATION");
            case VALIDATING:
                return result(
                    Code.PLAN_VALIDATION_FAILED,
                    "A execução chegou à validação determinística e falhou nessa etapa.",
                    "CHECK_PLAN_CONTRACT_VALIDATION");
            case PLANNING:
                return result(
                    Code.PLANNER_FAILED,
                    "A falha ocorreu no fluxo de planejamento antes de uma fase nativa mais específica ser registrada.",
                    "CHECK_PLANNER_GATEWAY_AND_NATIVE_PHASE");
            default:
                return result(
                    Code.UNKNOWN_FAILURE,
                    "A execução falhou, mas a fase registrada não permite uma classificação mais específica.",
                    "CHECK_FULL_EXECUTION_TIMELINE");
        }
    }

    private static Result result(
            Code code,
            String explanation,
            String nextCheck) {
        return new Result(code, explanation, nextCheck);
    }
}
