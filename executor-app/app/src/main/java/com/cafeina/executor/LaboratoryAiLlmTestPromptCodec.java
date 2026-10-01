package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;

/**
 * Deterministic JSON protocol between the planning boundary and a local model.
 *
 * This codec serializes data only. It exposes no Android Context, AI handles,
 * executors, permissions, approval APIs, snapshots, or mutable laboratory
 * objects to the model backend.
 */
public final class LaboratoryAiLlmTestPromptCodec {
    public static final String PROTOCOL = "cafeina-lab-test-planner";
    public static final int PROTOCOL_VERSION = 1;
    public static final int MAX_PROMPT_CHARS = 128 * 1024;

    private LaboratoryAiLlmTestPromptCodec() {}

    public static String encode(LaboratoryAiLlmTestPlanner.Request request)
            throws IOException {
        if (request == null) {
            throw new IllegalArgumentException("planner prompt request missing");
        }
        try {
            JSONObject root = new JSONObject();
            root.put("protocol", PROTOCOL);
            root.put("protocolVersion", PROTOCOL_VERSION);

            JSONObject rules = new JSONObject();
            rules.put("role", "planning_only");
            rules.put("output", "exactly_one_json_object_no_markdown");
            rules.put("mayExecuteTools", false);
            rules.put("mayChangePermissions", false);
            rules.put("mayChangeGoalLock", false);
            rules.put("useOnlyListedToolIds", true);
            rules.put("unknownFieldsAllowed", false);
            root.put("rules", rules);

            JSONObject response = new JSONObject();
            response.put(
                "schemaVersion",
                LaboratoryAiTestPlanContract.SCHEMA_VERSION);
            response.put(
                "rootFields",
                new JSONArray()
                    .put("schemaVersion")
                    .put("stopOnFailure")
                    .put("steps"));
            response.put(
                "stepFields",
                new JSONArray()
                    .put("name")
                    .put("toolId")
                    .put("input")
                    .put("expectedFirstReturn"));
            response.put("stepNamesMustBeUnique", true);
            response.put(
                "maxSteps",
                Math.min(
                    request.maxInvocations,
                    LaboratoryAiTestAgent.MAX_STEPS));
            response.put(
                "maxTotalInputBytes",
                request.maxTotalInputBytes);
            root.put("responseContract", response);

            JSONObject task = new JSONObject();
            task.put("attempt", request.attempt);
            task.put("mode", request.mode);
            task.put("goal", request.goal);
            task.put("maxInvocations", request.maxInvocations);
            task.put(
                "maxTotalInputBytes",
                request.maxTotalInputBytes);
            task.put("maxSessionMs", request.maxSessionMs);
            root.put("task", task);

            JSONArray tools = new JSONArray();
            for (LaboratoryAiLlmTestPlanner.ToolView tool :
                    request.tools) {
                JSONObject item = new JSONObject();
                item.put("toolId", tool.toolId);
                item.put("version", tool.version);
                item.put(
                    "capabilities",
                    new JSONArray(tool.capabilities));
                item.put("maxRuntimeMs", tool.maxRuntimeMs);
                item.put("maxInputBytes", tool.maxInputBytes);
                tools.put(item);
            }
            root.put("tools", tools);

            JSONArray memory = new JSONArray();
            for (LaboratoryAiLlmTestPlanner.MemoryHint hint :
                    request.memory) {
                JSONObject item = new JSONObject();
                item.put("sameGoal", hint.sameGoal);
                item.put("status", hint.status);
                item.put("terminalReason", hint.terminalReason);

                JSONArray steps = new JSONArray();
                for (LaboratoryAiLlmTestPlanner.MemoryStep step :
                        hint.steps) {
                    JSONObject remembered = new JSONObject();
                    remembered.put("toolId", step.toolId);
                    remembered.put("toolVersion", step.toolVersion);
                    remembered.put("passed", step.passed);
                    remembered.put("reason", step.reason);
                    steps.put(remembered);
                }
                item.put("steps", steps);
                memory.put(item);
            }
            root.put("sanitizedMemory", memory);

            JSONArray issues = new JSONArray();
            for (LaboratoryAiLlmTestPlanner.IssueHint issue :
                    request.previousIssues) {
                JSONObject item = new JSONObject();
                item.put("code", issue.code);
                item.put("stepIndex", issue.stepIndex);
                item.put("field", issue.field);
                issues.put(item);
            }
            root.put("previousValidationIssues", issues);

            String encoded = root.toString();
            if (encoded.length() > MAX_PROMPT_CHARS) {
                throw new IOException("planner prompt exceeds protocol limit");
            }
            return encoded;
        } catch (JSONException error) {
            throw new IOException("could not encode planner prompt", error);
        }
    }
}
