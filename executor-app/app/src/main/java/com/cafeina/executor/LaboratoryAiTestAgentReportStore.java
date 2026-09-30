package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/**
 * Create-only reports for the deterministic laboratory test agent.
 * Raw tool inputs, outputs, returns and runtime error strings are not stored.
 */
public final class LaboratoryAiTestAgentReportStore {
    public static final int MAX_REPORTS = 128;
    public static final int MAX_REPORT_BYTES = 64 * 1024;

    public static final class Entry {
        public final String reportId;
        public final String contractId;
        public final String sessionId;
        public final String status;
        public final long startedAtEpochMs;
        public final int plannedSteps;
        public final int executedSteps;
        public final int passed;
        public final int failed;
        public final String reportText;

        private Entry(String reportId, String contractId, String sessionId,
                String status, long startedAtEpochMs, int plannedSteps,
                int executedSteps, int passed, int failed, String reportText) {
            this.reportId = reportId;
            this.contractId = contractId;
            this.sessionId = sessionId;
            this.status = status;
            this.startedAtEpochMs = startedAtEpochMs;
            this.plannedSteps = plannedSteps;
            this.executedSteps = executedSteps;
            this.passed = passed;
            this.failed = failed;
            this.reportText = reportText;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path reportRoot;

    public LaboratoryAiTestAgentReportStore(
            File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid test-agent report project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        reportRoot = projectRoot.resolve("ai-test-agent-reports");
    }

    public synchronized void ensureWritable() throws IOException {
        prepareDirectory();
        if (countReports() >= MAX_REPORTS) {
            throw new IOException(
                "test-agent report limit reached; existing reports preserved");
        }
    }

    public synchronized void save(LaboratoryAiTestAgent.Report report)
            throws IOException {
        if (report == null || !validUuid(report.reportId)) {
            throw new IOException("invalid test-agent report");
        }
        try {
            writeNew(report.reportId, toJson(report));
        } catch (JSONException error) {
            throw new IOException("could not encode test-agent report", error);
        }
    }

    public synchronized List<Entry> list() throws IOException {
        if (!Files.exists(reportRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        prepareDirectory();
        List<Entry> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(reportRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_REPORTS) {
                throw new IOException("test-agent report directory exceeds limit");
            }
            paths.sort(Comparator.comparing(
                path -> path.getFileName().toString(), Comparator.reverseOrder()));
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".json")
                        || !validUuid(name.substring(0, name.length() - 5))) {
                    throw new IOException("unexpected test-agent report entry");
                }
                String reportId = name.substring(0, name.length() - 5);
                result.add(parse(reportId, readSafe(path)));
            }
        }
        result.sort(Comparator
            .comparingLong((Entry entry) -> entry.startedAtEpochMs)
            .reversed()
            .thenComparing(entry -> entry.reportId));
        return Collections.unmodifiableList(result);
    }

    public synchronized String read(String reportId) throws IOException {
        if (!validUuid(reportId)) throw new IOException("invalid test-agent report id");
        prepareDirectory();
        return readSafe(reportRoot.resolve(reportId + ".json"));
    }

    private JSONObject toJson(LaboratoryAiTestAgent.Report report)
            throws JSONException {
        JSONObject json = new JSONObject();
        json.put("schemaVersion", 1);
        json.put("reportId", report.reportId);
        json.put("contractId", report.contractId);
        json.put("goalSha256", report.goalSha256);
        json.put("mode", report.mode);
        json.put("sessionId", report.sessionId);
        json.put("status", report.status);
        json.put("terminalReason", report.terminalReason);
        json.put("startedAtEpochMs", report.startedAtEpochMs);
        json.put("durationMs", report.durationMs);
        json.put("plannedSteps", report.plannedSteps);
        json.put("executedSteps", report.executedSteps);
        json.put("passed", report.passed);
        json.put("failed", report.failed);
        json.put("stopOnFailure", report.stopOnFailure);

        JSONArray steps = new JSONArray();
        for (LaboratoryAiTestAgent.StepEvidence evidence : report.steps) {
            JSONObject item = new JSONObject();
            item.put("name", evidence.name);
            item.put("toolId", evidence.toolId);
            item.put("toolVersion", evidence.toolVersion);
            item.put("runId", evidence.runId);
            item.put("passed", evidence.passed);
            item.put("reason", evidence.reason);
            item.put("inputSha256", evidence.inputSha256);
            item.put("expectedReturnSha256", evidence.expectedReturnSha256);
            item.put("actualReturnSha256", evidence.actualReturnSha256);
            item.put("outputSha256", evidence.outputSha256);
            item.put("durationMs", evidence.durationMs);
            steps.put(item);
        }
        json.put("steps", steps);
        return json;
    }

    private Entry parse(String reportId, String raw) throws IOException {
        try {
            JSONObject json = new JSONObject(raw);
            int planned = json.getInt("plannedSteps");
            int executed = json.getInt("executedSteps");
            int passed = json.getInt("passed");
            int failed = json.getInt("failed");
            String terminalReason = json.optString("terminalReason");
            if (json.getInt("schemaVersion") != 1
                    || !reportId.equals(json.getString("reportId"))
                    || !validUuid(json.getString("contractId"))
                    || !json.getString("goalSha256").matches("[0-9a-f]{64}")
                    || !("CREATION".equals(json.getString("mode"))
                        || "LEARNING".equals(json.getString("mode")))
                    || (!json.optString("sessionId").isEmpty()
                        && !validUuid(json.optString("sessionId")))
                    || !validStatus(json.getString("status"))
                    || terminalReason.length() > 64
                    || (!terminalReason.isEmpty()
                        && !terminalReason.matches("[A-Za-z0-9_-]{1,64}"))
                    || json.getLong("startedAtEpochMs") <= 0
                    || json.getLong("durationMs") < 0
                    || planned < 1 || planned > LaboratoryAiTestAgent.MAX_STEPS
                    || executed < 0 || executed > planned
                    || passed < 0 || failed < 0
                    || passed + failed != executed) {
                throw new IOException("test-agent report failed validation");
            }
            JSONArray steps = json.getJSONArray("steps");
            if (steps.length() != executed
                    || steps.length() > LaboratoryAiTestAgent.MAX_STEPS) {
                throw new IOException("test-agent report step count mismatch");
            }
            int countedPassed = 0;
            int countedFailed = 0;
            for (int i = 0; i < steps.length(); i++) {
                JSONObject step = steps.getJSONObject(i);
                String runId = step.optString("runId");
                String version = step.optString("toolVersion");
                if (!step.getString("name").matches("[a-zA-Z0-9_-]{1,64}")
                        || !step.getString("toolId")
                            .matches("[a-z0-9][a-z0-9._-]{0,63}")
                        || version.length() > 64
                        || (!version.isEmpty()
                            && !version.matches("[0-9A-Za-z._-]{1,64}"))
                        || (!runId.isEmpty() && !validUuid(runId))
                        || !step.getString("reason")
                            .matches("[A-Za-z0-9_-]{1,64}")
                        || !step.getString("inputSha256").matches("[0-9a-f]{64}")
                        || !step.getString("expectedReturnSha256")
                            .matches("[0-9a-f]{64}")
                        || !step.getString("actualReturnSha256")
                            .matches("[0-9a-f]{64}")
                        || !step.getString("outputSha256")
                            .matches("[0-9a-f]{64}")
                        || step.getLong("durationMs") < 0) {
                    throw new IOException("invalid test-agent step evidence");
                }
                if (step.getBoolean("passed")) countedPassed++;
                else countedFailed++;
            }
            if (countedPassed != passed || countedFailed != failed) {
                throw new IOException("test-agent pass/fail counters do not match steps");
            }
            return new Entry(
                reportId,
                json.getString("contractId"),
                json.optString("sessionId"),
                json.getString("status"),
                json.getLong("startedAtEpochMs"),
                planned,
                executed,
                passed,
                failed,
                raw);
        } catch (JSONException error) {
            throw new IOException("invalid test-agent report", error);
        }
    }

    private void writeNew(String reportId, JSONObject json)
            throws IOException, JSONException {
        ensureWritable();
        Path destination = reportRoot.resolve(reportId + ".json");
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("test-agent report already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_REPORT_BYTES) {
            throw new IOException("test-agent report exceeds size budget");
        }

        Path temporary = reportRoot.resolve(
            "." + reportId + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(
                    temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("test-agent report already exists");
            }
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unavailable) {
                Files.move(temporary, destination);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private String readSafe(Path path) throws IOException {
        if (!reportRoot.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_REPORT_BYTES) {
            throw new IOException("test-agent report missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private int countReports() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(reportRoot)) {
            return (int) stream
                .filter(path -> {
                    String name = path.getFileName().toString();
                    return name.endsWith(".json")
                        && validUuid(name.substring(0, name.length() - 5));
                })
                .limit(MAX_REPORTS + 1L)
                .count();
        }
    }

    private void prepareDirectory() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(reportRoot);
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe test-agent report directory");
        }
    }

    private static boolean validStatus(String value) {
        return "PASS".equals(value) || "FAIL".equals(value)
            || "PAUSED".equals(value) || "CANCELLED".equals(value)
            || "ADMISSION_FAILED".equals(value);
    }

    private static boolean validUuid(String value) {
        try {
            return value != null && UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }
}
