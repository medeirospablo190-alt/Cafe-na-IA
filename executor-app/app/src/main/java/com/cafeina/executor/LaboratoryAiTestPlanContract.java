package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

/**
 * Structured boundary between a future local LLM planner and the deterministic
 * test agent.
 *
 * The model may propose a JSON draft, but only a draft that satisfies this
 * schema AND the already-issued Goal Lock can become an executable Plan.
 * Validation issues never echo raw goal/input/expected values.
 */
public final class LaboratoryAiTestPlanContract {
    public static final int SCHEMA_VERSION = 1;
    public static final int MAX_DRAFT_CHARS = 96 * 1024;

    public static final String PLAN_MISSING = "PLAN_MISSING";
    public static final String PLAN_JSON_INVALID = "PLAN_JSON_INVALID";
    public static final String PLAN_TOO_LARGE = "PLAN_TOO_LARGE";
    public static final String SCHEMA_UNSUPPORTED = "SCHEMA_UNSUPPORTED";
    public static final String UNKNOWN_FIELD = "UNKNOWN_FIELD";
    public static final String STOP_ON_FAILURE_INVALID =
        "STOP_ON_FAILURE_INVALID";
    public static final String STEPS_INVALID = "STEPS_INVALID";
    public static final String STEP_COUNT_INVALID = "STEP_COUNT_INVALID";
    public static final String PLAN_INVOCATION_BUDGET_EXCEEDED =
        "PLAN_INVOCATION_BUDGET_EXCEEDED";
    public static final String STEP_INVALID = "STEP_INVALID";
    public static final String STEP_NAME_INVALID = "STEP_NAME_INVALID";
    public static final String STEP_NAME_DUPLICATE = "STEP_NAME_DUPLICATE";
    public static final String STEP_TOOL_ID_INVALID = "STEP_TOOL_ID_INVALID";
    public static final String STEP_TOOL_NOT_ALLOWED =
        "STEP_TOOL_NOT_ALLOWED";
    public static final String STEP_INPUT_INVALID = "STEP_INPUT_INVALID";
    public static final String STEP_INPUT_TOO_LARGE =
        "STEP_INPUT_TOO_LARGE";
    public static final String STEP_EXPECTED_INVALID =
        "STEP_EXPECTED_INVALID";
    public static final String STEP_EXPECTED_TOO_LARGE =
        "STEP_EXPECTED_TOO_LARGE";
    public static final String PLAN_INPUT_BUDGET_EXCEEDED =
        "PLAN_INPUT_BUDGET_EXCEEDED";

    public static final class Issue {
        public final String code;
        public final int stepIndex;
        public final String field;

        private Issue(String code, int stepIndex, String field) {
            this.code = code;
            this.stepIndex = stepIndex;
            this.field = field == null ? "" : field;
        }
    }

    public static final class Validation {
        public final boolean accepted;
        public final List<Issue> issues;
        public final LaboratoryAiTestAgent.Plan plan;

        private Validation(List<Issue> issues,
                LaboratoryAiTestAgent.Plan plan) {
            this.issues = Collections.unmodifiableList(
                new ArrayList<>(issues));
            this.accepted = this.issues.isEmpty() && plan != null;
            this.plan = this.accepted ? plan : null;
        }

        public boolean hasCode(String code) {
            for (Issue issue : issues) {
                if (issue.code.equals(code)) return true;
            }
            return false;
        }
    }

    /**
     * Exception used by executable paths. The future planner can instead call
     * validateDraft() and consume the issue list without throwing.
     */
    public static final class RejectedPlanException
            extends IllegalArgumentException {
        public final List<Issue> issues;

        private RejectedPlanException(List<Issue> issues) {
            super("test plan rejected by structured contract");
            this.issues = Collections.unmodifiableList(
                new ArrayList<>(issues));
        }
    }

    private LaboratoryAiTestPlanContract() {}

    /**
     * Parse a planner-produced JSON draft and return all safe structural /
     * Goal Lock problems that can be determined without executing anything.
     */
    public static Validation validateDraft(
            LaboratoryAiTaskContractStore.Contract contract,
            String draftJson) {
        List<Issue> issues = new ArrayList<>();
        if (contract == null) {
            throw new IllegalArgumentException("AI task contract missing");
        }
        if (draftJson == null || draftJson.trim().isEmpty()) {
            issues.add(issue(PLAN_MISSING, -1, "plan"));
            return new Validation(issues, null);
        }
        if (draftJson.length() > MAX_DRAFT_CHARS) {
            issues.add(issue(PLAN_TOO_LARGE, -1, "plan"));
            return new Validation(issues, null);
        }

        final JSONObject root;
        try {
            root = new JSONObject(draftJson);
        } catch (JSONException invalidJson) {
            issues.add(issue(PLAN_JSON_INVALID, -1, "plan"));
            return new Validation(issues, null);
        }

        rejectUnknownFields(
            root,
            setOf("schemaVersion", "stopOnFailure", "steps"),
            -1,
            issues);

        Object schema = root.opt("schemaVersion");
        if (!(schema instanceof Number)
                || ((Number) schema).intValue() != SCHEMA_VERSION) {
            issues.add(issue(SCHEMA_UNSUPPORTED, -1, "schemaVersion"));
        }

        Object stopValue = root.opt("stopOnFailure");
        boolean stopOnFailure = false;
        if (!(stopValue instanceof Boolean)) {
            issues.add(issue(
                STOP_ON_FAILURE_INVALID, -1, "stopOnFailure"));
        } else {
            stopOnFailure = (Boolean) stopValue;
        }

        Object stepsValue = root.opt("steps");
        if (!(stepsValue instanceof JSONArray)) {
            issues.add(issue(STEPS_INVALID, -1, "steps"));
            return new Validation(issues, null);
        }

        JSONArray stepsJson = (JSONArray) stepsValue;
        int stepCount = stepsJson.length();
        if (stepCount < 1 || stepCount > LaboratoryAiTestAgent.MAX_STEPS) {
            issues.add(issue(STEP_COUNT_INVALID, -1, "steps"));
        }
        if (stepCount > contract.maxInvocations) {
            issues.add(issue(
                PLAN_INVOCATION_BUDGET_EXCEEDED, -1, "steps"));
        }

        List<LaboratoryAiTestAgent.Step> steps = new ArrayList<>();
        Set<String> names = new HashSet<>();
        long totalInputBytes = 0L;

        int boundedCount = Math.min(
            stepCount, LaboratoryAiTestAgent.MAX_STEPS);
        for (int i = 0; i < boundedCount; i++) {
            Object rawStep = stepsJson.opt(i);
            if (!(rawStep instanceof JSONObject)) {
                issues.add(issue(STEP_INVALID, i, "step"));
                continue;
            }
            JSONObject step = (JSONObject) rawStep;
            rejectUnknownFields(
                step,
                setOf("name", "toolId", "input", "expectedFirstReturn"),
                i,
                issues);

            String name = stringField(
                step, "name", STEP_NAME_INVALID, i, issues);
            String toolId = stringField(
                step, "toolId", STEP_TOOL_ID_INVALID, i, issues);
            String input = stringField(
                step, "input", STEP_INPUT_INVALID, i, issues);
            String expected = stringField(
                step, "expectedFirstReturn", STEP_EXPECTED_INVALID,
                i, issues);

            boolean validName = name != null
                && name.matches("[a-zA-Z0-9_-]{1,64}");
            if (name != null && !validName) {
                issues.add(issue(STEP_NAME_INVALID, i, "name"));
            }
            if (validName && !names.add(name)) {
                issues.add(issue(STEP_NAME_DUPLICATE, i, "name"));
            }

            boolean validToolId = toolId != null
                && toolId.matches("[a-z0-9][a-z0-9._-]{0,63}");
            if (toolId != null && !validToolId) {
                issues.add(issue(
                    STEP_TOOL_ID_INVALID, i, "toolId"));
            }
            if (validToolId
                    && !contract.allowedToolIds.contains(toolId)) {
                issues.add(issue(
                    STEP_TOOL_NOT_ALLOWED, i, "toolId"));
            }

            if (input != null) {
                if (input.length()
                        > LaboratorySandboxService.MAX_INPUT_CHARS) {
                    issues.add(issue(
                        STEP_INPUT_TOO_LARGE, i, "input"));
                }
                totalInputBytes +=
                    input.getBytes(StandardCharsets.UTF_8).length;
            }
            if (expected != null
                    && expected.length()
                        > LaboratorySandboxService.MAX_RESPONSE_CHARS) {
                issues.add(issue(
                    STEP_EXPECTED_TOO_LARGE,
                    i,
                    "expectedFirstReturn"));
            }

            if (validName && validToolId
                    && input != null
                    && input.length()
                        <= LaboratorySandboxService.MAX_INPUT_CHARS
                    && expected != null
                    && expected.length()
                        <= LaboratorySandboxService.MAX_RESPONSE_CHARS) {
                try {
                    steps.add(new LaboratoryAiTestAgent.Step(
                        name, toolId, input, expected));
                } catch (IllegalArgumentException unexpected) {
                    // Do not expose raw values. The public issue list is the
                    // authoritative explanation for planner correction.
                    issues.add(issue(STEP_INVALID, i, "step"));
                }
            }
        }

        if (totalInputBytes > contract.maxTotalInputBytes) {
            issues.add(issue(
                PLAN_INPUT_BUDGET_EXCEEDED, -1, "steps"));
        }

        if (!issues.isEmpty()
                || steps.size() != stepCount) {
            return new Validation(issues, null);
        }
        try {
            return new Validation(
                issues,
                new LaboratoryAiTestAgent.Plan(
                    steps, stopOnFailure));
        } catch (IllegalArgumentException unexpected) {
            issues.add(issue(STEP_INVALID, -1, "plan"));
            return new Validation(issues, null);
        }
    }

    /**
     * Validate an already-built deterministic plan against the exact Goal Lock.
     * Structural Step/Plan invariants were enforced by their constructors.
     */
    public static Validation validate(
            LaboratoryAiTaskContractStore.Contract contract,
            LaboratoryAiTestAgent.Plan plan) {
        if (contract == null) {
            throw new IllegalArgumentException("AI task contract missing");
        }
        List<Issue> issues = new ArrayList<>();
        if (plan == null) {
            issues.add(issue(PLAN_MISSING, -1, "plan"));
            return new Validation(issues, null);
        }

        if (plan.steps.size() > contract.maxInvocations) {
            issues.add(issue(
                PLAN_INVOCATION_BUDGET_EXCEEDED, -1, "steps"));
        }

        long inputBytes = 0L;
        for (int i = 0; i < plan.steps.size(); i++) {
            LaboratoryAiTestAgent.Step step = plan.steps.get(i);
            if (!contract.allowedToolIds.contains(step.toolId)) {
                issues.add(issue(
                    STEP_TOOL_NOT_ALLOWED, i, "toolId"));
            }
            inputBytes +=
                step.input.getBytes(StandardCharsets.UTF_8).length;
        }
        if (inputBytes > contract.maxTotalInputBytes) {
            issues.add(issue(
                PLAN_INPUT_BUDGET_EXCEEDED, -1, "steps"));
        }
        return new Validation(issues, issues.isEmpty() ? plan : null);
    }

    public static void requireValid(
            LaboratoryAiTaskContractStore.Contract contract,
            LaboratoryAiTestAgent.Plan plan) {
        Validation validation = validate(contract, plan);
        if (!validation.accepted) {
            throw new RejectedPlanException(validation.issues);
        }
    }

    private static String stringField(
            JSONObject object,
            String field,
            String missingCode,
            int stepIndex,
            List<Issue> issues) {
        Object value = object.opt(field);
        if (!(value instanceof String)) {
            issues.add(issue(missingCode, stepIndex, field));
            return null;
        }
        return (String) value;
    }

    private static void rejectUnknownFields(
            JSONObject object,
            Set<String> allowed,
            int stepIndex,
            List<Issue> issues) {
        Iterator<String> keys = object.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            if (!allowed.contains(key)) {
                issues.add(issue(UNKNOWN_FIELD, stepIndex, key));
            }
        }
    }

    private static Set<String> setOf(String... values) {
        Set<String> result = new HashSet<>();
        Collections.addAll(result, values);
        return result;
    }

    private static Issue issue(
            String code, int stepIndex, String field) {
        return new Issue(code, stepIndex, field);
    }
}
