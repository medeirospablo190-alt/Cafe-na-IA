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
 * Append-only persistence for deterministic baseline-vs-candidate comparisons.
 * The source code of either tool is never stored here; only existing laboratory
 * run identifiers, hashes, metrics and verdict evidence are recorded.
 */
public final class LaboratoryRegressionStore {
    public static final int MAX_COMPARISONS = 256;
    public static final int MAX_COMPARISON_BYTES = 32 * 1024;

    public static final class Record {
        public final String comparisonId;
        public final long createdAtEpochMs;
        public final String verdict;
        public final String baselineRunId;
        public final String candidateRunId;
        public final String toolId;
        public final String toolVersion;
        public final long seed;
        public final String environmentSha256;
        public final String baselineBatchSha256;
        public final String candidateBatchSha256;
        public final String baselineInputSha256;
        public final String candidateInputSha256;
        public final long baselineDurationMs;
        public final long candidateDurationMs;
        public final long allowedDurationMs;
        public final long durationDeltaMs;
        public final int maxSlowdownPercent;
        public final long graceMs;
        public final boolean requireSameEnvironment;
        public final List<String> coveredTests;
        public final List<String> reasons;

        private Record(String comparisonId, long createdAtEpochMs, String verdict,
                String baselineRunId, String candidateRunId, String toolId,
                String toolVersion, long seed, String environmentSha256,
                String baselineBatchSha256, String candidateBatchSha256,
                String baselineInputSha256, String candidateInputSha256,
                long baselineDurationMs, long candidateDurationMs,
                long allowedDurationMs, long durationDeltaMs,
                int maxSlowdownPercent, long graceMs, boolean requireSameEnvironment,
                List<String> coveredTests, List<String> reasons) {
            this.comparisonId = comparisonId;
            this.createdAtEpochMs = createdAtEpochMs;
            this.verdict = verdict;
            this.baselineRunId = baselineRunId;
            this.candidateRunId = candidateRunId;
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.seed = seed;
            this.environmentSha256 = environmentSha256;
            this.baselineBatchSha256 = baselineBatchSha256;
            this.candidateBatchSha256 = candidateBatchSha256;
            this.baselineInputSha256 = baselineInputSha256;
            this.candidateInputSha256 = candidateInputSha256;
            this.baselineDurationMs = baselineDurationMs;
            this.candidateDurationMs = candidateDurationMs;
            this.allowedDurationMs = allowedDurationMs;
            this.durationDeltaMs = durationDeltaMs;
            this.maxSlowdownPercent = maxSlowdownPercent;
            this.graceMs = graceMs;
            this.requireSameEnvironment = requireSameEnvironment;
            this.coveredTests = Collections.unmodifiableList(
                new ArrayList<>(coveredTests));
            this.reasons = Collections.unmodifiableList(new ArrayList<>(reasons));
        }
    }

    private final File appFilesDirectory;
    private final String projectId;
    private final Path regressionDirectory;

    public LaboratoryRegressionStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null) throw new IllegalArgumentException("app directory missing");
        if (projectId == null || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid laboratory project id");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path laboratoryRoot = appRoot.resolve("laboratory");
        Path projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        this.regressionDirectory = projectRoot.resolve("regressions");
    }

    public synchronized Record compareAndSave(String baselineRunId, String candidateRunId,
            LaboratoryRegressionEngine.Policy policy) throws IOException {
        if (!validUuid(baselineRunId) || !validUuid(candidateRunId)
                || baselineRunId.equals(candidateRunId)) {
            throw new IOException("invalid regression run pair");
        }
        if (policy == null) throw new IllegalArgumentException("regression policy missing");
        ensureWritable();

        LaboratoryReportStore reports =
            new LaboratoryReportStore(appFilesDirectory, projectId);
        LaboratoryRegressionEngine.RunEvidence baseline =
            parseRun(reports.read(baselineRunId));
        LaboratoryRegressionEngine.RunEvidence candidate =
            parseRun(reports.read(candidateRunId));
        if (!baselineRunId.equals(baseline.runId)
                || !candidateRunId.equals(candidate.runId)) {
            throw new IOException("regression run identity mismatch");
        }

        LaboratoryRegressionEngine.Result result =
            LaboratoryRegressionEngine.evaluate(baseline, candidate, policy);
        String comparisonId = UUID.randomUUID().toString();
        long created = System.currentTimeMillis();
        try {
            JSONObject json = toJson(comparisonId, created, result, policy);
            writeNew(comparisonId, json);
            return parseRecord(json.toString());
        } catch (JSONException error) {
            throw new IOException("could not encode regression comparison", error);
        }
    }

    public synchronized Record read(String comparisonId) throws IOException {
        if (!validUuid(comparisonId)) throw new IOException("invalid regression comparison id");
        if (!Files.exists(regressionDirectory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("regression comparison not found");
        }
        prepareDirectory();
        try {
            return parseRecord(readSafe(regressionDirectory.resolve(comparisonId + ".json")));
        } catch (JSONException error) {
            throw new IOException("invalid regression comparison", error);
        }
    }

    public synchronized List<Record> list() throws IOException {
        if (!Files.exists(regressionDirectory, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        prepareDirectory();
        List<Record> records = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(regressionDirectory)) {
            stream.filter(path -> validFileName(path.getFileName().toString()))
                .limit(MAX_COMPARISONS + 1L)
                .forEach(path -> {
                    try {
                        records.add(parseRecord(readSafe(path)));
                    } catch (Exception error) {
                        throw new RecordReadFailure(error);
                    }
                });
        } catch (RecordReadFailure wrapped) {
            throw new IOException("could not read regression history", wrapped.getCause());
        }
        if (records.size() > MAX_COMPARISONS) {
            throw new IOException("regression history exceeds limit");
        }
        records.sort(Comparator
            .comparingLong((Record record) -> record.createdAtEpochMs)
            .reversed()
            .thenComparing(record -> record.comparisonId));
        return Collections.unmodifiableList(records);
    }

    public synchronized void ensureWritable() throws IOException {
        prepareDirectory();
        try (java.util.stream.Stream<Path> stream = Files.list(regressionDirectory)) {
            long count = stream.filter(path ->
                validFileName(path.getFileName().toString()))
                .limit(MAX_COMPARISONS + 1L)
                .count();
            if (count >= MAX_COMPARISONS) {
                throw new IOException(
                    "regression comparison limit reached; existing evidence was preserved");
            }
        }
    }

    private LaboratoryRegressionEngine.RunEvidence parseRun(String raw) throws IOException {
        try {
            JSONObject report = new JSONObject(raw);
            JSONArray array = report.getJSONArray("checks");
            List<LaboratoryRegressionEngine.CheckEvidence> checks = new ArrayList<>();
            for (int i = 0; i < array.length(); i++) {
                JSONObject check = array.getJSONObject(i);
                checks.add(new LaboratoryRegressionEngine.CheckEvidence(
                    check.getString("name"),
                    check.getBoolean("passed"),
                    check.getString("expectedOutput"),
                    check.getString("actualOutput"),
                    check.getString("inputSha256")));
            }
            return new LaboratoryRegressionEngine.RunEvidence(
                report.getString("runId"),
                report.getString("toolId"),
                report.getString("toolVersion"),
                report.getString("status"),
                report.getLong("seed"),
                report.getLong("durationMs"),
                report.getString("candidateBatchSha256"),
                report.optString("environmentSha256"),
                checks);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid laboratory run for regression", error);
        }
    }

    private static JSONObject toJson(String comparisonId, long created,
            LaboratoryRegressionEngine.Result result,
            LaboratoryRegressionEngine.Policy policy) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("schemaVersion", 1);
        json.put("comparisonId", comparisonId);
        json.put("createdAtEpochMs", created);
        json.put("verdict", result.verdict.name());
        json.put("baselineRunId", result.baselineRunId);
        json.put("candidateRunId", result.candidateRunId);
        json.put("toolId", result.toolId);
        json.put("toolVersion", result.toolVersion);
        json.put("seed", result.seed);
        if (!result.environmentSha256.isEmpty()) {
            json.put("environmentSha256", result.environmentSha256);
        }
        json.put("baselineBatchSha256", result.baselineBatchSha256);
        json.put("candidateBatchSha256", result.candidateBatchSha256);
        if (!result.baselineInputSha256.isEmpty()) {
            json.put("baselineInputSha256", result.baselineInputSha256);
        }
        if (!result.candidateInputSha256.isEmpty()) {
            json.put("candidateInputSha256", result.candidateInputSha256);
        }
        json.put("baselineDurationMs", result.baselineDurationMs);
        json.put("candidateDurationMs", result.candidateDurationMs);
        json.put("allowedDurationMs", result.allowedDurationMs);
        json.put("durationDeltaMs", result.durationDeltaMs);
        json.put("maxSlowdownPercent", policy.maxSlowdownPercent);
        json.put("graceMs", policy.graceMs);
        json.put("requireSameEnvironment", policy.requireSameEnvironment);
        json.put("coveredTests", new JSONArray(result.coveredTests));
        json.put("reasons", new JSONArray(result.reasons));
        return json;
    }

    private static Record parseRecord(String raw) throws JSONException {
        JSONObject json = new JSONObject(raw);
        String id = json.getString("comparisonId");
        if (!validUuid(id)) throw new JSONException("invalid comparison id");
        return new Record(
            id,
            json.getLong("createdAtEpochMs"),
            json.getString("verdict"),
            json.getString("baselineRunId"),
            json.getString("candidateRunId"),
            json.getString("toolId"),
            json.getString("toolVersion"),
            json.getLong("seed"),
            json.optString("environmentSha256"),
            json.getString("baselineBatchSha256"),
            json.getString("candidateBatchSha256"),
            json.optString("baselineInputSha256"),
            json.optString("candidateInputSha256"),
            json.getLong("baselineDurationMs"),
            json.getLong("candidateDurationMs"),
            json.getLong("allowedDurationMs"),
            json.getLong("durationDeltaMs"),
            json.getInt("maxSlowdownPercent"),
            json.getLong("graceMs"),
            json.getBoolean("requireSameEnvironment"),
            strings(json.getJSONArray("coveredTests")),
            strings(json.getJSONArray("reasons")));
    }

    private void writeNew(String comparisonId, JSONObject json)
            throws IOException, JSONException {
        Path destination = regressionDirectory.resolve(comparisonId + ".json");
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("regression comparison already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_COMPARISON_BYTES) {
            throw new IOException("regression comparison exceeds size budget");
        }
        Path temporary = regressionDirectory.resolve(
            "." + comparisonId + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("regression comparison already exists");
            }
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temporary, destination);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private String readSafe(Path path) throws IOException {
        if (!regressionDirectory.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) > MAX_COMPARISON_BYTES) {
            throw new IOException("regression record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private void prepareDirectory() throws IOException {
        Path projectRoot = regressionDirectory.getParent();
        Path laboratoryRoot = projectRoot.getParent();
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(regressionDirectory);
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
            throw new IOException("unsafe regression directory");
        }
    }

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) values.add(array.getString(i));
        return values;
    }

    private static boolean validUuid(String value) {
        if (value == null) return false;
        try {
            return UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static boolean validFileName(String name) {
        return name != null && name.endsWith(".json")
            && validUuid(name.substring(0, name.length() - 5));
    }

    private static final class RecordReadFailure extends RuntimeException {
        RecordReadFailure(Throwable cause) { super(cause); }
    }
}
