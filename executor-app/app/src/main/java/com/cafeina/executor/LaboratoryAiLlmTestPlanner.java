package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Planning-only boundary for a future local language model.
 *
 * The model receives the locked goal, only the tools already allowed by the
 * task contract, bounded sanitized test memory, and safe validation feedback.
 * It can only return a JSON draft. This class never admits a task, executes a
 * tool, mutates permissions, or consumes the one-use Goal Lock.
 */
public final class LaboratoryAiLlmTestPlanner {
    public static final int MAX_ATTEMPTS = 2;
    public static final int MEMORY_LIMIT = 8;

    public interface ModelGateway {
        String propose(Request request) throws IOException;
    }

    public static final class ToolView {
        public final String toolId;
        public final String version;
        public final List<String> capabilities;
        public final int maxRuntimeMs;
        public final int maxInputBytes;

        private ToolView(LaboratoryAiToolController.Tool tool) {
            this.toolId = tool.toolId;
            this.version = tool.version;
            this.capabilities = Collections.unmodifiableList(
                new ArrayList<>(tool.capabilities));
            this.maxRuntimeMs = tool.maxRuntimeMs;
            this.maxInputBytes = tool.maxInputBytes;
        }
    }

    public static final class MemoryStep {
        public final String toolId;
        public final String toolVersion;
        public final boolean passed;
        public final String reason;

        private MemoryStep(LaboratoryAiTestMemory.Step step) {
            this.toolId = step.toolId;
            this.toolVersion = step.toolVersion;
            this.passed = step.passed;
            this.reason = step.reason;
        }
    }

    public static final class MemoryHint {
        public final boolean sameGoal;
        public final String status;
        public final String terminalReason;
        public final List<MemoryStep> steps;

        private MemoryHint(boolean sameGoal,
                LaboratoryAiTestMemory.Record record,
                List<MemoryStep> steps) {
            this.sameGoal = sameGoal;
            this.status = record.status;
            this.terminalReason = record.terminalReason;
            this.steps = Collections.unmodifiableList(
                new ArrayList<>(steps));
        }
    }

    public static final class IssueHint {
        public final String code;
        public final int stepIndex;
        public final String field;

        private IssueHint(LaboratoryAiTestPlanContract.Issue issue) {
            this.code = issue.code;
            this.stepIndex = issue.stepIndex;
            this.field = issue.field;
        }
    }

    /**
     * Immutable model-facing planning context.
     *
     * There is deliberately no execution handle in this object.
     */
    public static final class Request {
        public final int schemaVersion;
        public final int attempt;
        public final String mode;
        public final String goal;
        public final int maxInvocations;
        public final int maxTotalInputBytes;
        public final long maxSessionMs;
        public final List<ToolView> tools;
        public final List<MemoryHint> memory;
        public final List<IssueHint> previousIssues;

        private Request(int attempt,
                LaboratoryAiTaskContractStore.Contract contract,
                List<ToolView> tools,
                List<MemoryHint> memory,
                List<IssueHint> previousIssues) {
            this.schemaVersion = LaboratoryAiTestPlanContract.SCHEMA_VERSION;
            this.attempt = attempt;
            this.mode = contract.mode.name();
            this.goal = contract.goalText;
            this.maxInvocations = contract.maxInvocations;
            this.maxTotalInputBytes = contract.maxTotalInputBytes;
            this.maxSessionMs = contract.maxSessionMs;
            this.tools = Collections.unmodifiableList(new ArrayList<>(tools));
            this.memory = Collections.unmodifiableList(new ArrayList<>(memory));
            this.previousIssues = Collections.unmodifiableList(
                new ArrayList<>(previousIssues));
        }
    }

    public static final class Result {
        public final boolean accepted;
        public final int attempts;
        public final LaboratoryAiTestAgent.Plan plan;
        public final List<LaboratoryAiTestPlanContract.Issue> issues;

        private Result(int attempts,
                LaboratoryAiTestPlanContract.Validation validation) {
            this.accepted = validation.accepted;
            this.attempts = attempts;
            this.plan = validation.plan;
            this.issues = Collections.unmodifiableList(
                new ArrayList<>(validation.issues));
        }
    }

    private LaboratoryAiLlmTestPlanner() {}

    /**
     * Ask a planning-only model gateway for a bounded JSON test plan.
     *
     * Invalid drafts may receive one correction attempt containing only safe
     * issue codes/locations. Raw rejected drafts are neither persisted nor
     * echoed back through the result.
     */
    public static Result plan(Context context, String projectId,
            String contractId, ModelGateway model) throws IOException {
        if (context == null || model == null) {
            throw new IllegalArgumentException(
                "LLM test planner context or model missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "LLM test planner must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(app.getFilesDir(), projectId);
        LaboratoryAiTaskContractStore.Contract contract =
            store.read(contractId);
        requireUnused(contract);

        List<ToolView> tools = allowedTools(app, projectId, contract);
        List<MemoryHint> memory = memoryHints(app, projectId, contract);
        List<LaboratoryAiTestPlanContract.Issue> previous =
            Collections.emptyList();
        LaboratoryAiTestPlanContract.Validation validation = null;

        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            Request request = new Request(
                attempt,
                contract,
                tools,
                memory,
                issueHints(previous));

            String draft = model.propose(request);
            validation = LaboratoryAiTestPlanContract.validateDraft(
                contract, draft);
            if (validation.accepted) {
                requireStillUnused(store.read(contractId));
                return new Result(attempt, validation);
            }
            previous = validation.issues;
        }

        if (validation == null) {
            throw new IllegalStateException(
                "LLM test planner produced no validation result");
        }
        requireStillUnused(store.read(contractId));
        return new Result(MAX_ATTEMPTS, validation);
    }

    private static List<ToolView> allowedTools(Context app, String projectId,
            LaboratoryAiTaskContractStore.Contract contract)
            throws IOException {
        Map<String, LaboratoryAiToolController.Tool> available =
            new HashMap<>();
        for (LaboratoryAiToolController.Tool tool :
                LaboratoryAiToolController.listAvailable(app, projectId)) {
            available.put(tool.toolId, tool);
        }

        List<ToolView> result = new ArrayList<>();
        for (String toolId : contract.allowedToolIds) {
            LaboratoryAiToolController.Tool tool = available.get(toolId);
            if (tool == null) {
                throw new SecurityException(
                    "task contract tool is no longer available to the planner");
            }
            result.add(new ToolView(tool));
        }
        return Collections.unmodifiableList(result);
    }

    private static List<MemoryHint> memoryHints(Context app, String projectId,
            LaboratoryAiTaskContractStore.Contract contract)
            throws IOException {
        LaboratoryAiTestMemory memory =
            new LaboratoryAiTestMemory(app.getFilesDir(), projectId);
        List<MemoryHint> result = new ArrayList<>();

        for (LaboratoryAiTestMemory.Record record :
                memory.recent(MEMORY_LIMIT)) {
            List<MemoryStep> relevantSteps = new ArrayList<>();
            for (LaboratoryAiTestMemory.Step step : record.steps) {
                if (contract.allowedToolIds.contains(step.toolId)) {
                    relevantSteps.add(new MemoryStep(step));
                }
            }
            if (relevantSteps.isEmpty()) continue;
            result.add(new MemoryHint(
                contract.goalSha256.equals(record.goalSha256),
                record,
                relevantSteps));
        }
        return Collections.unmodifiableList(result);
    }

    private static List<IssueHint> issueHints(
            List<LaboratoryAiTestPlanContract.Issue> issues) {
        List<IssueHint> result = new ArrayList<>();
        for (LaboratoryAiTestPlanContract.Issue issue : issues) {
            result.add(new IssueHint(issue));
        }
        return Collections.unmodifiableList(result);
    }

    private static void requireUnused(
            LaboratoryAiTaskContractStore.Contract contract) {
        if (contract.claimed || contract.resultRecorded) {
            throw new IllegalStateException(
                "LLM test planner requires an unused task contract");
        }
    }

    private static void requireStillUnused(
            LaboratoryAiTaskContractStore.Contract contract) {
        if (contract.claimed || contract.resultRecorded) {
            throw new IllegalStateException(
                "task contract changed while the LLM plan was being prepared");
        }
    }
}
