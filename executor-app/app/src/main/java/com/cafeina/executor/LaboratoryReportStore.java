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
 * Create-only, private reports separated from projects, scripts and runtime-fs.
 * No delete/overwrite/execute operation is exposed by this class.
 * This is application-level append-only storage, not a tamper-proof audit log
 * against root or other code executing with the application's Android UID.
 */
public final class LaboratoryReportStore {
    public static final int MAX_REPORTS = 256;
    public static final int MAX_REPORT_BYTES = 48 * 1024;

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path reportDirectory;

    public LaboratoryReportStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null) throw new IllegalArgumentException("app directory missing");
        if (projectId == null || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid laboratory project id");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        this.laboratoryRoot = appRoot.resolve("laboratory");
        this.projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        this.reportDirectory = projectRoot.resolve("reports");
    }

    public static final class Entry {
        public final String runId;
        public final String toolId;
        public final String toolVersion;
        public final String status;
        public final long startedAtEpochMs;
        public final int passed;
        public final int failed;
        public final String reportText;

        private Entry(String id, String toolId, String toolVersion, String status,
                long started, int passed, int failed, String reportText) {
            this.runId = id;
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.status = status;
            this.startedAtEpochMs = started;
            this.passed = passed;
            this.failed = failed;
            this.reportText = reportText;
        }
    }

    public synchronized void ensureWritable() throws IOException {
        prepareDirectory();
        if (countReports() >= MAX_REPORTS) {
            throw new IOException("report limit reached; no existing reports were deleted");
        }
    }

    public synchronized void save(LaboratoryEngine.Report report) throws IOException {
        if (report == null || !isValidRunId(report.runId)) {
            throw new IOException("invalid laboratory report");
        }
        try {
            writeNew(report.runId, toJson(report));
        } catch (JSONException error) {
            throw new IOException("could not encode laboratory report", error);
        }
    }

    /**
     * Records a candidate run without persisting its source, stdout, runtime
     * error strings or return values. Execution success is NOT test success:
     * PASS requires an explicit expected first return to match.
     */
    public synchronized void saveSandboxResult(LaboratorySandboxClient.Result result,
            String caseName, String expectedFirstReturn, long seed) throws IOException {
        saveSandboxResult(result, caseName, expectedFirstReturn, seed, null, true);
    }

    /**
     * A snapshot reference is valid only after the recovery core rechecks its
     * bytes and digest. An integrity failure must never be marked PASS even if
     * the sandbox returned the expected value.
     */
    public synchronized void saveSandboxResult(LaboratorySandboxClient.Result result,
            String caseName, String expectedFirstReturn, long seed,
            String snapshotId, boolean snapshotVerified) throws IOException {
        if (snapshotId != null && !LaboratorySnapshotStore.validId(snapshotId)) {
            throw new IOException("invalid candidate snapshot id");
        }
        if (result == null || !isValidRunId(result.runId) || caseName == null
                || !caseName.matches("[a-zA-Z0-9_-]{1,64}")
                || expectedFirstReturn == null || expectedFirstReturn.length() > 256) {
            throw new IOException("invalid isolated test report");
        }
        boolean matched = snapshotVerified && "EXECUTED".equals(result.status)
            && expectedFirstReturn.equals(result.firstReturn);
        String outcome = !snapshotVerified ? "FAIL" : matched ? "PASS" :
            ("TIMEOUT".equals(result.status) || "CANCELLED".equals(result.status)
                ? result.status : "FAIL");
        try {
            JSONObject report = new JSONObject();
            report.put("schemaVersion", 2);
            report.put("runId", result.runId);
            report.put("toolId", "luau-isolated-candidate");
            report.put("toolVersion", "0.1.0");
            report.put("stage", "EXPERIMENTAL");
            report.put("seed", seed);
            report.put("startedAtEpochMs", result.startedAtEpochMs);
            report.put("durationMs", result.durationMs);
            report.put("candidateBatchSha256", result.sourceSha256);
            report.put("toolInputSha256", result.inputSha256);
            if (snapshotId != null) report.put("candidateSnapshotId", snapshotId);
            report.put("snapshotVerified", snapshotVerified);
            report.put("status", outcome);
            report.put("workerStatus", result.status);
            report.put("workerUid", result.workerUid);
            report.put("passed", matched ? 1 : 0);
            report.put("failed", matched || "CANCELLED".equals(outcome)
                || "TIMEOUT".equals(outcome) ? 0 : 1);
            JSONObject check = new JSONObject();
            check.put("name", caseName);
            check.put("passed", matched);
            check.put("expectedOutput",
                LaboratoryEngine.fingerprint(expectedFirstReturn).substring(7, 71));
            check.put("actualOutput",
                LaboratoryEngine.fingerprint(result.firstReturn).substring(7, 71));
            check.put("inputSha256", result.sourceSha256);
            check.put("toolInputSha256", result.inputSha256);
            check.put("reason", !snapshotVerified
                ? "snapshot integrity check failed; test candidate not approved"
                : matched ? "isolated return matched expected value"
                : "worker: " + result.status + "; return mismatch or execution failed");
            report.put("checks", new JSONArray().put(check));
            writeNew(result.runId, report);
        } catch (JSONException error) {
            throw new IOException("could not encode isolated report", error);
        }
    }

    private void writeNew(String runId, JSONObject report) throws IOException, JSONException {
        ensureWritable();
        Path destination = reportDirectory.resolve(runId + ".json");
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("laboratory run already recorded");
        }
        byte[] bytes = report.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_REPORT_BYTES) {
            throw new IOException("laboratory report exceeds size budget");
        }

        // A unique temporary file is synced before the final path is exposed.
        Path temporary = reportDirectory.resolve("." + runId + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("laboratory run already recorded");
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

    public synchronized List<Entry> list() throws IOException {
        if (!Files.exists(laboratoryRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        prepareDirectory();
        List<Entry> items = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(reportDirectory)) {
            stream.filter(path -> isValidFileName(path.getFileName().toString()))
                .sorted(Comparator.comparing((Path p) -> p.getFileName().toString()).reversed())
                .limit(MAX_REPORTS + 1)
                .forEach(path -> {
                    String name = path.getFileName().toString();
                    String id = name.substring(0, name.length() - 5);
                    try {
                        items.add(parse(id, readSafe(path)));
                    } catch (Exception error) {
                        // Corrupted evidence remains visible rather than disappearing.
                        items.add(new Entry(id, "relatorio-indisponivel", "", "CORROMPIDO",
                            0, 0, 0, "Não foi possível ler o relatório: " + error.getMessage()));
                    }
                });
        }
        if (items.size() > MAX_REPORTS) throw new IOException("report directory exceeds limit");
        items.sort((left, right) -> {
            int order = Long.compare(right.startedAtEpochMs, left.startedAtEpochMs);
            return order != 0 ? order : right.runId.compareTo(left.runId);
        });
        return Collections.unmodifiableList(items);
    }

    public synchronized String read(String runId) throws IOException {
        if (!isValidRunId(runId)) throw new IOException("invalid laboratory run id");
        if (!Files.exists(laboratoryRoot, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("laboratory report not found");
        }
        prepareDirectory();
        return readSafe(reportDirectory.resolve(runId + ".json"));
    }

    private int countReports() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(reportDirectory)) {
            return (int) stream.filter(p -> isValidFileName(p.getFileName().toString()))
                .limit(MAX_REPORTS + 1).count();
        }
    }

    private String readSafe(Path path) throws IOException {
        if (!reportDirectory.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.size(path) > MAX_REPORT_BYTES) {
            throw new IOException("report path is missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private void prepareDirectory() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(reportDirectory);
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below; never follow a link created by another writer.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe laboratory directory");
        }
    }

    private static boolean isValidRunId(String id) {
        if (id == null) return false;
        try {
            return UUID.fromString(id).toString().equals(id);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static boolean isValidFileName(String name) {
        return name != null && name.endsWith(".json")
            && isValidRunId(name.substring(0, name.length() - 5));
    }

    private static Entry parse(String id, String raw) throws JSONException {
        JSONObject object = new JSONObject(raw);
        if (!id.equals(object.getString("runId"))) {
            throw new JSONException("report id mismatch");
        }
        return new Entry(id, object.getString("toolId"),
            object.getString("toolVersion"), object.getString("status"),
            object.getLong("startedAtEpochMs"), object.getInt("passed"),
            object.getInt("failed"), raw);
    }

    private static JSONObject toJson(LaboratoryEngine.Report report) throws JSONException {
        JSONObject object = new JSONObject();
        object.put("schemaVersion", 1);
        object.put("runId", report.runId);
        object.put("toolId", report.toolId);
        object.put("toolVersion", report.toolVersion);
        object.put("stage", report.stage);
        object.put("seed", report.seed);
        object.put("startedAtEpochMs", report.startedAtEpochMs);
        object.put("durationMs", report.durationMs);
        object.put("candidateBatchSha256", report.candidateBatchSha256);
        if (!report.environmentSha256.isEmpty()) {
            object.put("environmentSha256", report.environmentSha256);
        }
        object.put("status", report.status.name());
        object.put("passed", report.passed);
        object.put("failed", report.failed);
        JSONArray checks = new JSONArray();
        for (LaboratoryEngine.Check check : report.checks) {
            JSONObject item = new JSONObject();
            item.put("name", check.name);
            item.put("passed", check.passed);
            item.put("actualOutput", check.actualOutput);
            item.put("expectedOutput", check.expectedOutput);
            item.put("inputSha256", check.inputSha256);
            item.put("reason", check.reason);
            checks.put(item);
        }
        object.put("checks", checks);
        return object;
    }
}
