package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.stream.Stream;

/**
 * Durable START/END records for multi-case tests of one registered Luau tool.
 *
 * The store never executes a tool or reads editor/project files. It only binds
 * the suite to an existing registry version/snapshot and to privacy-preserving
 * per-case reports produced by the isolated worker.
 */
public final class LaboratoryCandidateSuiteStore {
    public static final int MAX_SUITES = 32;
    public static final int MAX_CASES = 8;
    private static final int MAX_ENTRIES = MAX_SUITES * 2;
    private static final int MAX_RECORD_BYTES = 20 * 1024;
    private static final int FORMAT = 1;

    public enum Status {
        RUNNING_OR_INTERRUPTED, PASS, FAIL, CANCELLED, TIMEOUT, INCOMPLETE
    }

    public static final class Summary {
        public final String suiteId;
        public final String toolId;
        public final String toolVersion;
        public final String manifestSha256;
        public final String sourceSha256;
        public final String snapshotId;
        public final String planSha256;
        public final long startedAtEpochMs;
        public final long completedAtEpochMs;
        public final int requested;
        public final int passed;
        public final int failed;
        public final Status status;
        public final String reason;
        public final List<String> reportIds;

        private Summary(String suiteId, String toolId, String toolVersion,
                String manifestSha, String sourceSha, String snapshotId,
                String planSha, long started, long completed, int requested,
                int passed, int failed, Status status, String reason,
                List<String> reportIds) {
            this.suiteId = suiteId;
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.manifestSha256 = manifestSha;
            this.sourceSha256 = sourceSha;
            this.snapshotId = snapshotId;
            this.planSha256 = planSha;
            this.startedAtEpochMs = started;
            this.completedAtEpochMs = completed;
            this.requested = requested;
            this.passed = passed;
            this.failed = failed;
            this.status = status;
            this.reason = reason;
            this.reportIds = Collections.unmodifiableList(new ArrayList<>(reportIds));
        }
    }

    private final Path labRoot;
    private final Path projectRoot;
    private final Path suiteRoot;
    private final LaboratoryToolRegistry registry;
    private final LaboratoryReportStore reports;

    public LaboratoryCandidateSuiteStore(File appFilesDir, String projectId) {
        if (appFilesDir == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid candidate-suite project");
        }
        Path app = appFilesDir.toPath().toAbsolutePath().normalize();
        labRoot = app.resolve("laboratory");
        projectRoot = labRoot.resolve(projectId.isEmpty() ? "legacy" : "project-" + projectId);
        suiteRoot = projectRoot.resolve("candidate-suites");
        registry = new LaboratoryToolRegistry(appFilesDir, projectId);
        reports = new LaboratoryReportStore(appFilesDir, projectId);
    }

    public synchronized void ensureWritable() throws IOException {
        ensureSafeDir(labRoot);
        ensureSafeDir(projectRoot);
        ensureSafeDir(suiteRoot);
        int starts = 0;
        int entries = 0;
        try (Stream<Path> stream = Files.list(suiteRoot)) {
            List<Path> found = new ArrayList<>();
            stream.forEach(found::add);
            for (Path path : found) {
                entries++;
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unsafe candidate-suite entry");
                }
                String name = path.getFileName().toString();
                boolean start = name.endsWith(".start");
                boolean done = name.endsWith(".done");
                String id = name.substring(0, name.length() - (start ? 6 : done ? 5 : 0));
                if ((!start && !done) || !LaboratorySnapshotStore.validId(id)) {
                    throw new IOException("unexpected candidate-suite entry");
                }
                if (start) starts++;
            }
        }
        if (starts >= MAX_SUITES || entries >= MAX_ENTRIES) {
            throw new IOException("candidate-suite limit reached; history was preserved");
        }
    }

    public synchronized Summary begin(LaboratoryToolRegistry.Tool tool,
            String planSha256, int requested) throws IOException {
        if (tool == null || planSha256 == null
                || !planSha256.matches("[0-9a-f]{64}")
                || requested < 1 || requested > MAX_CASES
                || !(tool.state == LaboratoryToolRegistry.State.EXPERIMENTAL
                    || tool.state == LaboratoryToolRegistry.State.CANDIDATE)) {
            throw new IllegalArgumentException("invalid candidate-suite start");
        }
        // Re-read through the registry so a stale object cannot start a suite.
        LaboratoryToolRegistry.Tool current = registry.read(tool.id, tool.version);
        if (!sameTool(tool, current)) {
            throw new IOException("tool version changed before suite start");
        }
        ensureWritable();

        String id = UUID.randomUUID().toString();
        long started = System.currentTimeMillis();
        JSONObject start = new JSONObject();
        try {
            start.put("schemaVersion", FORMAT);
            start.put("kind", "start");
            start.put("suiteId", id);
            start.put("mode", "CANDIDATE_BATCH");
            start.put("toolId", current.id);
            start.put("toolVersion", current.version);
            start.put("manifestSha256", current.manifestSha256);
            start.put("sourceSha256", current.sourceSha256);
            start.put("snapshotId", current.snapshotId);
            start.put("planSha256", planSha256);
            start.put("requested", requested);
            start.put("startedAtEpochMs", started);
        } catch (JSONException malformed) {
            throw new IOException("could not encode candidate-suite start", malformed);
        }
        writeNew(path(id, ".start"), start.toString());
        return new Summary(id, current.id, current.version, current.manifestSha256,
            current.sourceSha256, current.snapshotId, planSha256, started, 0,
            requested, 0, 0, Status.RUNNING_OR_INTERRUPTED, "START_RECORDED",
            Collections.emptyList());
    }

    public synchronized Summary complete(String suiteId, Status finalStatus,
            List<String> reportIds, int passed, int failed, String reason) throws IOException {
        if (!LaboratorySnapshotStore.validId(suiteId)
                || finalStatus == null || finalStatus == Status.RUNNING_OR_INTERRUPTED
                || reportIds == null || reportIds.size() > MAX_CASES
                || passed < 0 || failed < 0 || passed + failed > MAX_CASES
                || reason == null || !reason.matches("[A-Z_]{3,40}")) {
            throw new IllegalArgumentException("invalid candidate-suite completion");
        }
        Summary start = read(suiteId);
        if (start.status != Status.RUNNING_OR_INTERRUPTED) {
            throw new IOException("candidate suite already completed");
        }
        if ((finalStatus == Status.PASS
                    && (passed != start.requested || failed != 0
                        || reportIds.size() != start.requested
                        || !"ALL_CASES_MATCHED".equals(reason)))
                || (finalStatus == Status.FAIL && failed == 0)) {
            throw new IOException("candidate-suite result does not match completed work");
        }

        JSONArray refs = new JSONArray();
        for (String reportId : reportIds) {
            if (!LaboratorySnapshotStore.validId(reportId)) {
                throw new IllegalArgumentException("invalid candidate-suite report id");
            }
            String raw = reports.read(reportId);
            if (finalStatus == Status.PASS) {
                verifyPassingCandidateReport(raw, start);
            }
            JSONObject ref = new JSONObject();
            try {
                ref.put("id", reportId);
                ref.put("sha256", sha256(raw));
            } catch (JSONException malformed) {
                throw new IOException("could not encode candidate-suite report reference", malformed);
            }
            refs.put(ref);
        }

        JSONObject end = new JSONObject();
        try {
            end.put("schemaVersion", FORMAT);
            end.put("kind", "end");
            end.put("suiteId", suiteId);
            end.put("startSha256", sha256(readRecord(path(suiteId, ".start"))));
            end.put("status", finalStatus.name());
            end.put("reason", reason);
            end.put("completedAtEpochMs", System.currentTimeMillis());
            end.put("passed", passed);
            end.put("failed", failed);
            end.put("reports", refs);
        } catch (JSONException malformed) {
            throw new IOException("could not encode candidate-suite end", malformed);
        }
        writeNew(path(suiteId, ".done"), end.toString());
        return read(suiteId);
    }

    public synchronized Summary read(String suiteId) throws IOException {
        if (!LaboratorySnapshotStore.validId(suiteId)) {
            throw new IOException("invalid candidate-suite id");
        }
        requireExistingVault();
        String rawStart = readRecord(path(suiteId, ".start"));
        try {
            JSONObject start = new JSONObject(rawStart);
            if (start.getInt("schemaVersion") != FORMAT
                    || !"start".equals(start.getString("kind"))
                    || !suiteId.equals(start.getString("suiteId"))
                    || !"CANDIDATE_BATCH".equals(start.getString("mode"))
                    || !start.getString("manifestSha256").matches("[0-9a-f]{64}")
                    || !start.getString("sourceSha256").matches("[0-9a-f]{64}")
                    || !LaboratorySnapshotStore.validId(start.getString("snapshotId"))
                    || !start.getString("planSha256").matches("[0-9a-f]{64}")
                    || start.getInt("requested") < 1 || start.getInt("requested") > MAX_CASES
                    || start.getLong("startedAtEpochMs") <= 0) {
                throw new IOException("candidate-suite start is invalid");
            }

            LaboratoryToolRegistry.Tool tool =
                registry.read(start.getString("toolId"), start.getString("toolVersion"));
            if (!tool.manifestSha256.equals(start.getString("manifestSha256"))
                    || !tool.sourceSha256.equals(start.getString("sourceSha256"))
                    || !tool.snapshotId.equals(start.getString("snapshotId"))) {
                throw new IOException("candidate-suite tool evidence changed");
            }

            if (!Files.exists(path(suiteId, ".done"), LinkOption.NOFOLLOW_LINKS)) {
                return new Summary(suiteId, tool.id, tool.version, tool.manifestSha256,
                    tool.sourceSha256, tool.snapshotId, start.getString("planSha256"),
                    start.getLong("startedAtEpochMs"), 0, start.getInt("requested"),
                    0, 0, Status.RUNNING_OR_INTERRUPTED, "START_RECORDED",
                    Collections.emptyList());
            }

            JSONObject end = new JSONObject(readRecord(path(suiteId, ".done")));
            if (end.getInt("schemaVersion") != FORMAT
                    || !"end".equals(end.getString("kind"))
                    || !suiteId.equals(end.getString("suiteId"))
                    || !sha256(rawStart).equals(end.getString("startSha256"))
                    || end.getLong("completedAtEpochMs") < start.getLong("startedAtEpochMs")) {
                throw new IOException("candidate-suite completion is not bound to start");
            }
            Status status;
            try {
                status = Status.valueOf(end.getString("status"));
            } catch (IllegalArgumentException invalid) {
                throw new IOException("invalid candidate-suite final status", invalid);
            }
            int passed = end.getInt("passed");
            int failed = end.getInt("failed");
            String reason = end.getString("reason");
            JSONArray refs = end.getJSONArray("reports");
            if (status == Status.RUNNING_OR_INTERRUPTED || passed < 0 || failed < 0
                    || passed + failed > start.getInt("requested")
                    || refs.length() > MAX_CASES
                    || !reason.matches("[A-Z_]{3,40}")) {
                throw new IOException("candidate-suite completion is inconsistent");
            }
            if (status == Status.PASS
                    && (passed != start.getInt("requested") || failed != 0
                        || refs.length() != start.getInt("requested")
                        || !"ALL_CASES_MATCHED".equals(reason))) {
                throw new IOException("candidate-suite PASS lacks complete evidence");
            }
            if (status == Status.FAIL && failed == 0) {
                throw new IOException("candidate-suite FAIL lacks failed cases");
            }

            List<String> reportIds = new ArrayList<>();
            Summary expected = new Summary(suiteId, tool.id, tool.version,
                tool.manifestSha256, tool.sourceSha256, tool.snapshotId,
                start.getString("planSha256"), start.getLong("startedAtEpochMs"),
                end.getLong("completedAtEpochMs"), start.getInt("requested"),
                passed, failed, status, reason, Collections.emptyList());
            for (int i = 0; i < refs.length(); i++) {
                JSONObject ref = refs.getJSONObject(i);
                String id = ref.getString("id");
                String digest = ref.getString("sha256");
                if (!LaboratorySnapshotStore.validId(id)
                        || !digest.matches("[0-9a-f]{64}")) {
                    throw new IOException("invalid candidate-suite report reference");
                }
                String raw = reports.read(id);
                if (!digest.equals(sha256(raw))) {
                    throw new IOException("candidate-suite report evidence changed");
                }
                if (status == Status.PASS) verifyPassingCandidateReport(raw, expected);
                reportIds.add(id);
            }
            return new Summary(suiteId, tool.id, tool.version, tool.manifestSha256,
                tool.sourceSha256, tool.snapshotId, start.getString("planSha256"),
                start.getLong("startedAtEpochMs"), end.getLong("completedAtEpochMs"),
                start.getInt("requested"), passed, failed, status, reason, reportIds);
        } catch (JSONException malformed) {
            throw new IOException("candidate-suite metadata is malformed", malformed);
        }
    }

    public synchronized List<Summary> list() throws IOException {
        if (!Files.exists(labRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(projectRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(suiteRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireExistingVault();
        List<String> ids = new ArrayList<>();
        java.util.Set<String> ends = new java.util.HashSet<>();
        try (Stream<Path> stream = Files.list(suiteRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_ENTRIES) {
                throw new IOException("candidate-suite vault exceeds entry budget");
            }
            for (Path path : paths) {
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unsafe candidate-suite record");
                }
                String name = path.getFileName().toString();
                boolean start = name.endsWith(".start");
                boolean done = name.endsWith(".done");
                if (!start && !done) throw new IOException("unexpected candidate-suite record");
                String id = name.substring(0, name.length() - (start ? 6 : 5));
                if (!LaboratorySnapshotStore.validId(id)) {
                    throw new IOException("invalid candidate-suite id in vault");
                }
                if (start) ids.add(id); else ends.add(id);
            }
        }
        for (String id : ends) {
            if (!ids.contains(id)) {
                throw new IOException("candidate-suite completion is missing START");
            }
        }
        if (ids.size() > MAX_SUITES) throw new IOException("too many candidate suites");
        List<Summary> summaries = new ArrayList<>();
        for (String id : ids) summaries.add(read(id));
        summaries.sort(Comparator.comparingLong((Summary s) -> s.startedAtEpochMs)
            .reversed().thenComparing(s -> s.suiteId));
        return Collections.unmodifiableList(summaries);
    }

    private static boolean sameTool(LaboratoryToolRegistry.Tool a,
            LaboratoryToolRegistry.Tool b) {
        return a.id.equals(b.id) && a.version.equals(b.version)
            && a.manifestSha256.equals(b.manifestSha256)
            && a.sourceSha256.equals(b.sourceSha256)
            && a.snapshotId.equals(b.snapshotId)
            && a.timeoutMs == b.timeoutMs && a.capability.equals(b.capability);
    }

    private static void verifyPassingCandidateReport(String raw, Summary suite)
            throws IOException {
        try {
            JSONObject report = new JSONObject(raw);
            JSONArray checks = report.getJSONArray("checks");
            if (report.getInt("schemaVersion") != 2
                    || !"luau-isolated-candidate".equals(report.getString("toolId"))
                    || !"EXPERIMENTAL".equals(report.getString("stage"))
                    || !"PASS".equals(report.getString("status"))
                    || !"EXECUTED".equals(report.getString("workerStatus"))
                    || !report.getBoolean("snapshotVerified")
                    || !suite.snapshotId.equals(report.getString("candidateSnapshotId"))
                    || !suite.sourceSha256.equals(report.getString("candidateBatchSha256"))
                    || !report.getString("toolInputSha256").matches("[0-9a-f]{64}")
                    || report.getInt("workerUid") < 1
                    || report.getInt("passed") != 1 || report.getInt("failed") != 0
                    || checks.length() != 1
                    || !checks.getJSONObject(0).getBoolean("passed")
                    || !suite.sourceSha256.equals(
                        checks.getJSONObject(0).getString("inputSha256"))
                    || !report.getString("toolInputSha256").equals(
                        checks.getJSONObject(0).getString("toolInputSha256"))) {
                throw new IOException("candidate-suite PASS report is not valid evidence");
            }
        } catch (JSONException invalid) {
            throw new IOException("candidate-suite report is malformed", invalid);
        }
    }

    private Path path(String id, String extension) {
        return suiteRoot.resolve(id + extension);
    }

    private void requireExistingVault() throws IOException {
        for (Path path : new Path[]{labRoot, projectRoot, suiteRoot}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("candidate-suite vault is missing or unsafe");
            }
        }
    }

    private static void ensureSafeDir(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException raced) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe candidate-suite directory");
        }
    }

    private static void writeNew(Path path, String raw) throws IOException {
        String text = raw + "\n" + sha256(raw) + "\n";
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("candidate-suite record exceeds size budget");
        }
        try (FileChannel channel = FileChannel.open(path,
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer data = ByteBuffer.wrap(bytes);
            while (data.hasRemaining()) channel.write(data);
            channel.force(true);
        }
    }

    private static String readRecord(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException("candidate-suite record missing, linked or oversized");
        }
        byte[] binary = Files.readAllBytes(path);
        String text = new String(binary, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(binary, text.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("candidate-suite record has invalid UTF-8");
        }
        String[] lines = text.split("\n", -1);
        if (lines.length != 3 || !lines[2].isEmpty()
                || !lines[1].matches("[0-9a-f]{64}")
                || !sha256(lines[0]).equals(lines[1])) {
            throw new IOException("candidate-suite record integrity check failed");
        }
        return lines[0];
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) out.append(String.format(Locale.ROOT, "%02x", b & 255));
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
