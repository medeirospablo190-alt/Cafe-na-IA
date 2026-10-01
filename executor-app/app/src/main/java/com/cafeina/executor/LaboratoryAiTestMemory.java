package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Minimal read-only test memory derived from create-only test-agent reports.
 *
 * This deliberately does not create another persistence layer. Reports remain
 * the source of truth; this class only exposes bounded, sanitized history that
 * a future Context Builder / local planner may query.
 */
public final class LaboratoryAiTestMemory {
    public static final int MAX_QUERY_RESULTS = 64;

    public static final class Step {
        public final String name;
        public final String toolId;
        public final String toolVersion;
        public final boolean passed;
        public final String reason;
        public final long durationMs;
        public final String inputSha256;
        public final String expectedReturnSha256;
        public final String actualReturnSha256;
        public final String outputSha256;

        private Step(JSONObject json) throws JSONException {
            this.name = json.getString("name");
            this.toolId = json.getString("toolId");
            this.toolVersion = json.optString("toolVersion");
            this.passed = json.getBoolean("passed");
            this.reason = json.getString("reason");
            this.durationMs = json.getLong("durationMs");
            this.inputSha256 = json.getString("inputSha256");
            this.expectedReturnSha256 =
                json.getString("expectedReturnSha256");
            this.actualReturnSha256 =
                json.getString("actualReturnSha256");
            this.outputSha256 = json.getString("outputSha256");
        }
    }

    public static final class Record {
        public final String reportId;
        public final String contractId;
        public final String goalSha256;
        public final String mode;
        public final String sessionId;
        public final String status;
        public final String terminalReason;
        public final long startedAtEpochMs;
        public final long durationMs;
        public final int plannedSteps;
        public final int executedSteps;
        public final int passed;
        public final int failed;
        public final boolean stopOnFailure;
        public final List<Step> steps;

        private Record(JSONObject json) throws JSONException {
            this.reportId = json.getString("reportId");
            this.contractId = json.getString("contractId");
            this.goalSha256 = json.getString("goalSha256");
            this.mode = json.getString("mode");
            this.sessionId = json.optString("sessionId");
            this.status = json.getString("status");
            this.terminalReason = json.optString("terminalReason");
            this.startedAtEpochMs = json.getLong("startedAtEpochMs");
            this.durationMs = json.getLong("durationMs");
            this.plannedSteps = json.getInt("plannedSteps");
            this.executedSteps = json.getInt("executedSteps");
            this.passed = json.getInt("passed");
            this.failed = json.getInt("failed");
            this.stopOnFailure = json.getBoolean("stopOnFailure");

            JSONArray rawSteps = json.getJSONArray("steps");
            List<Step> parsed = new ArrayList<>();
            for (int i = 0; i < rawSteps.length(); i++) {
                parsed.add(new Step(rawSteps.getJSONObject(i)));
            }
            this.steps = Collections.unmodifiableList(parsed);
        }

        public boolean usedTool(String toolId) {
            if (toolId == null) return false;
            for (Step step : steps) {
                if (toolId.equals(step.toolId)) return true;
            }
            return false;
        }
    }

    private final LaboratoryAiTestAgentReportStore reports;

    public LaboratoryAiTestMemory(
            File appFilesDirectory, String projectId) {
        reports = new LaboratoryAiTestAgentReportStore(
            appFilesDirectory, projectId);
    }

    public List<Record> recent(int limit) throws IOException {
        return filter(limit, null, null);
    }

    public List<Record> forGoal(
            String goalSha256, int limit) throws IOException {
        if (goalSha256 == null
                || !goalSha256.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("invalid test-memory goal hash");
        }
        return filter(limit, goalSha256, null);
    }

    public List<Record> forTool(
            String toolId, int limit) throws IOException {
        if (toolId == null
                || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")) {
            throw new IllegalArgumentException("invalid test-memory tool id");
        }
        return filter(limit, null, toolId);
    }

    private List<Record> filter(
            int limit, String goalSha256, String toolId)
            throws IOException {
        if (limit < 1 || limit > MAX_QUERY_RESULTS) {
            throw new IllegalArgumentException(
                "invalid test-memory result limit");
        }

        List<Record> result = new ArrayList<>();
        for (LaboratoryAiTestAgentReportStore.Entry entry
                : reports.list()) {
            final Record record;
            try {
                record = new Record(new JSONObject(entry.reportText));
            } catch (JSONException malformed) {
                // The report store already validates every entry. Treat a
                // second parse failure as an integrity failure, not as missing
                // memory.
                throw new IOException(
                    "validated test report could not be read as memory",
                    malformed);
            }
            if (goalSha256 != null
                    && !goalSha256.equals(record.goalSha256)) {
                continue;
            }
            if (toolId != null && !record.usedTool(toolId)) {
                continue;
            }
            result.add(record);
            if (result.size() >= limit) break;
        }
        return Collections.unmodifiableList(result);
    }
}
