package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Read-only readiness check immediately before TestAgent execution.
 *
 * It does not claim the Goal Lock, create a session, execute tools or mutate
 * permissions. The authoritative gates still revalidate everything at use.
 */
public final class LaboratoryAiExecutionPreflight {
    public enum Level {
        PASS,
        WARNING,
        BLOCK
    }

    public static final class Check {
        public final Level level;
        public final String code;
        public final String title;
        public final String detail;

        private Check(
                Level level,
                String code,
                String title,
                String detail) {
            this.level = level;
            this.code = code;
            this.title = title;
            this.detail = detail;
        }
    }

    public static final class Result {
        public final boolean ready;
        public final LaboratoryAiValidatedPlanExecutionGate.Prepared prepared;
        public final List<Check> checks;
        public final int stepCount;
        public final int totalInputBytes;
        public final long worstCaseToolRuntimeMs;

        private Result(
                LaboratoryAiValidatedPlanExecutionGate.Prepared prepared,
                List<Check> checks,
                int stepCount,
                int totalInputBytes,
                long worstCaseToolRuntimeMs) {
            this.prepared = prepared;
            this.checks = Collections.unmodifiableList(
                new ArrayList<>(checks));
            boolean blocked = false;
            for (Check check : checks) {
                if (check.level == Level.BLOCK) {
                    blocked = true;
                    break;
                }
            }
            this.ready = !blocked;
            this.stepCount = stepCount;
            this.totalInputBytes = totalInputBytes;
            this.worstCaseToolRuntimeMs = worstCaseToolRuntimeMs;
        }
    }

    private LaboratoryAiExecutionPreflight() {}

    public static Result inspect(
            Context context,
            String projectId,
            String contractId,
            String scenarioId) throws IOException {
        if (context == null
                || contractId == null
                || contractId.isEmpty()
                || scenarioId == null
                || scenarioId.isEmpty()) {
            throw new IllegalArgumentException(
                "execution preflight input missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "execution preflight must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        String safeProjectId = projectId == null ? "" : projectId;
        List<Check> checks = new ArrayList<>();

        final LaboratoryAiValidatedPlanExecutionGate.Prepared prepared;
        try {
            prepared =
                LaboratoryAiValidatedPlanExecutionGate.restorePrepared(
                    app,
                    safeProjectId,
                    contractId,
                    scenarioId);
            pass(
                checks,
                "CONTRACT_SCENARIO_INTEGRITY",
                "Goal Lock e cenário íntegros",
                "Contrato não consumido e cenário preparado revalidado.");
        } catch (IOException | RuntimeException failure) {
            block(
                checks,
                "CONTRACT_SCENARIO_INVALID",
                "Goal Lock ou cenário não está pronto",
                safeReason(failure));
            return new Result(
                null,
                checks,
                0,
                0,
                0L);
        }

        LaboratoryAiTaskContractStore.Contract contract =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), safeProjectId)
                .read(contractId);
        LaboratoryAiTestScenarioStore.Scenario scenario =
            new LaboratoryAiTestScenarioStore(
                app.getFilesDir(), safeProjectId)
                .read(scenarioId);

        LaboratoryAiTestPlanContract.Validation validation =
            LaboratoryAiTestPlanContract.validate(
                contract,
                scenario.plan);
        if (validation.accepted) {
            pass(
                checks,
                "PLAN_CONTRACT_VALID",
                "Plano dentro do Goal Lock",
                scenario.stepCount
                    + " passo(s) dentro do orçamento do contrato.");
        } else {
            block(
                checks,
                "PLAN_CONTRACT_INVALID",
                "Plano não atende mais ao Goal Lock",
                validation.issues.size()
                    + " problema(s) estrutural(is) detectado(s).");
        }

        List<LaboratoryAiToolController.Tool> available =
            LaboratoryAiToolController.listAvailable(
                app,
                safeProjectId);
        Map<String, LaboratoryAiToolController.Tool> byId =
            new HashMap<>();
        for (LaboratoryAiToolController.Tool tool : available) {
            byId.put(tool.toolId, tool);
        }

        boolean allowlistReady = true;
        for (String allowed : contract.allowedToolIds) {
            if (!byId.containsKey(allowed)) {
                allowlistReady = false;
                block(
                    checks,
                    "ALLOWLIST_TOOL_NOT_AVAILABLE",
                    "Ferramenta autorizada não está mais disponível",
                    allowed
                        + " perdeu permissão, STABLE ativo ou vínculo válido.");
            }
        }
        if (allowlistReady) {
            pass(
                checks,
                "ALLOWLIST_AVAILABLE",
                "Allowlist ainda disponível",
                contract.allowedToolIds.size()
                    + " ferramenta(s) continuam autorizadas e STABLE.");
        }

        int totalInputBytes = 0;
        long worstCaseRuntime = 0L;
        Set<String> checkedTools = new HashSet<>();
        for (int i = 0; i < scenario.plan.steps.size(); i++) {
            LaboratoryAiTestAgent.Step step =
                scenario.plan.steps.get(i);
            int inputBytes =
                step.input.getBytes(StandardCharsets.UTF_8).length;
            totalInputBytes += inputBytes;

            LaboratoryAiToolController.Tool tool =
                byId.get(step.toolId);
            if (tool == null) {
                continue;
            }

            if (checkedTools.add(tool.toolId)) {
                if (!tool.capabilities.contains(
                        LaboratoryStableToolExecutor.REQUIRED_CAPABILITY)) {
                    block(
                        checks,
                        "TOOL_ISOLATION_CAPABILITY_MISSING",
                        "Ferramenta não está apta para execução isolada",
                        tool.toolId);
                } else {
                    pass(
                        checks,
                        "TOOL_ISOLATION_CAPABILITY_OK",
                        "Execução isolada disponível",
                        tool.toolId + " • " + tool.version);
                }
            }

            if (inputBytes > tool.maxInputBytes) {
                block(
                    checks,
                    "STEP_TOOL_INPUT_LIMIT_EXCEEDED",
                    "Entrada maior que o limite da ferramenta",
                    "Passo " + (i + 1)
                        + " • " + step.toolId
                        + " • " + inputBytes
                        + "/" + tool.maxInputBytes + " bytes");
            }

            worstCaseRuntime += Math.max(
                0L,
                Math.min(
                    tool.maxRuntimeMs,
                    LaboratorySandboxService.MAX_TIMEOUT_MS));
        }

        if (totalInputBytes <= contract.maxTotalInputBytes) {
            pass(
                checks,
                "SESSION_INPUT_BUDGET_OK",
                "Orçamento de entrada suficiente",
                totalInputBytes + "/"
                    + contract.maxTotalInputBytes + " bytes");
        } else {
            block(
                checks,
                "SESSION_INPUT_BUDGET_EXCEEDED",
                "Plano excede o orçamento de entrada",
                totalInputBytes + "/"
                    + contract.maxTotalInputBytes + " bytes");
        }

        if (scenario.stepCount <= contract.maxInvocations) {
            pass(
                checks,
                "SESSION_INVOCATION_BUDGET_OK",
                "Orçamento de chamadas suficiente",
                scenario.stepCount + "/"
                    + contract.maxInvocations + " chamada(s)");
        } else {
            block(
                checks,
                "SESSION_INVOCATION_BUDGET_EXCEEDED",
                "Plano excede o orçamento de chamadas",
                scenario.stepCount + "/"
                    + contract.maxInvocations + " chamada(s)");
        }

        if (worstCaseRuntime > contract.maxSessionMs) {
            warning(
                checks,
                "WORST_CASE_RUNTIME_EXCEEDS_SESSION",
                "Tempo máximo teórico ultrapassa a sessão",
                worstCaseRuntime + " ms teóricos para "
                    + contract.maxSessionMs
                    + " ms de sessão. Isso não impede o teste, mas ele pode "
                    + "expirar se as ferramentas chegarem perto dos limites.");
        } else {
            pass(
                checks,
                "SESSION_TIME_BUDGET_OK",
                "Orçamento temporal compatível",
                worstCaseRuntime + " ms teóricos dentro de "
                    + contract.maxSessionMs + " ms");
        }

        checkAuditCapacity(
            app,
            safeProjectId,
            scenario.stepCount,
            checks);

        return new Result(
            prepared,
            checks,
            scenario.stepCount,
            totalInputBytes,
            worstCaseRuntime);
    }

    private static void checkAuditCapacity(
            Context app,
            String projectId,
            int plannedSteps,
            List<Check> checks) throws IOException {
        int sessions =
            new LaboratoryAiSessionStore(
                app.getFilesDir(), projectId)
                .list().size();
        if (sessions >= LaboratoryAiSessionStore.MAX_SESSIONS) {
            block(
                checks,
                "SESSION_AUDIT_CAPACITY_EXHAUSTED",
                "Auditoria de sessões está cheia",
                sessions + "/"
                    + LaboratoryAiSessionStore.MAX_SESSIONS
                    + " sessões.");
        } else {
            pass(
                checks,
                "SESSION_AUDIT_CAPACITY_OK",
                "Há espaço para auditar a sessão",
                sessions + "/"
                    + LaboratoryAiSessionStore.MAX_SESSIONS
                    + " sessões usadas.");
        }

        int reports =
            new LaboratoryAiTestAgentReportStore(
                app.getFilesDir(), projectId)
                .list().size();
        if (reports >= LaboratoryAiTestAgentReportStore.MAX_REPORTS) {
            block(
                checks,
                "REPORT_CAPACITY_EXHAUSTED",
                "Armazenamento de relatórios está cheio",
                reports + "/"
                    + LaboratoryAiTestAgentReportStore.MAX_REPORTS
                    + " relatórios.");
        } else {
            pass(
                checks,
                "REPORT_CAPACITY_OK",
                "Há espaço para o relatório final",
                reports + "/"
                    + LaboratoryAiTestAgentReportStore.MAX_REPORTS
                    + " relatórios usados.");
        }

        int uses =
            new LaboratoryStableUseStore(
                app.getFilesDir(), projectId)
                .list().size();
        int stableUseRemaining =
            LaboratoryStableUseStore.MAX_USES - uses;
        if (stableUseRemaining < plannedSteps) {
            block(
                checks,
                "STABLE_USE_AUDIT_CAPACITY_INSUFFICIENT",
                "Não há espaço para auditar todas as ferramentas",
                stableUseRemaining
                    + " recibo(s) restante(s) para "
                    + plannedSteps + " passo(s).");
        } else {
            pass(
                checks,
                "STABLE_USE_AUDIT_CAPACITY_OK",
                "Há espaço para os recibos das ferramentas",
                stableUseRemaining
                    + " recibo(s) disponível(is).");
        }

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(
                app.getFilesDir(), projectId);
        List<LaboratoryAiTeamRegistry.Member> members =
            team.listMembers();
        boolean testerExists = false;
        for (LaboratoryAiTeamRegistry.Member member : members) {
            if ("test-agent".equals(member.agentId)
                    && LaboratoryAiTeamRegistry.ROLE_TESTER.equals(
                        member.role)) {
                testerExists = true;
                break;
            }
        }
        if (!testerExists
                && members.size()
                    >= LaboratoryAiTeamRegistry.MAX_MEMBERS) {
            block(
                checks,
                "AI_TEAM_MEMBER_CAPACITY_EXHAUSTED",
                "Não há espaço para registrar a Testadora",
                members.size() + "/"
                    + LaboratoryAiTeamRegistry.MAX_MEMBERS
                    + " identidades.");
        }

        int bindings = team.listBindings().size();
        if (bindings >= LaboratoryAiTeamRegistry.MAX_BINDINGS) {
            block(
                checks,
                "AI_TEAM_BINDING_CAPACITY_EXHAUSTED",
                "Auditoria de atribuição de sessões está cheia",
                bindings + "/"
                    + LaboratoryAiTeamRegistry.MAX_BINDINGS
                    + " vínculos.");
        } else {
            pass(
                checks,
                "AI_TEAM_BINDING_CAPACITY_OK",
                "Há espaço para atribuir a sessão à Testadora",
                bindings + "/"
                    + LaboratoryAiTeamRegistry.MAX_BINDINGS
                    + " vínculos usados.");
        }
    }

    private static void pass(
            List<Check> checks,
            String code,
            String title,
            String detail) {
        checks.add(new Check(
            Level.PASS, code, title, detail));
    }

    private static void warning(
            List<Check> checks,
            String code,
            String title,
            String detail) {
        checks.add(new Check(
            Level.WARNING, code, title, detail));
    }

    private static void block(
            List<Check> checks,
            String code,
            String title,
            String detail) {
        checks.add(new Check(
            Level.BLOCK, code, title, detail));
    }

    private static String safeReason(Throwable failure) {
        if (failure == null) return "Falha desconhecida.";
        String name = failure.getClass().getSimpleName();
        String message = failure.getMessage();
        if (message == null || message.trim().isEmpty()) {
            return name;
        }
        String clean = message
            .replace('\n', ' ')
            .replace('\r', ' ')
            .trim();
        if (clean.length() > 240) {
            clean = clean.substring(0, 240);
        }
        return name + ": " + clean;
    }
}
