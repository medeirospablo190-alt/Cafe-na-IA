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
 * Private, create-only START and END records for bounded laboratory suites.
 * A START with no END is visible as interrupted or in progress, never PASS.
 * Reports are referenced by ID and SHA-256, without copying source text.
 *
 * File hashes detect accidental modification, not hostile code already
 * running under the application's UID. No deletions or STABLE activation.
 */
public final class LaboratorySuiteStore {
    public static final int MAX_SUITES = 64;
    private static final int MAX_ENTRIES = MAX_SUITES * 2;
    private static final int MAX_RECORD_BYTES = 12 * 1024;
    private static final int FORMAT = 1;

    public enum Status {
        RUNNING_OR_INTERRUPTED, PASS, FAIL, CANCELLED, TIMEOUT, INCOMPLETE
    }

    public static final class Summary {
        public final String suiteId;
        public final String mode;
        public final String planSha256;
        public final long startedAtEpochMs;
        public final long completedAtEpochMs;
        public final int requested;
        public final int passed;
        public final int failed;
        public final Status status;
        public final String reason;
        public final List<String> reportIds;

        private Summary(String id, String mode, String hash, long started, long ended,
                int requested, int passed, int failed, Status status, String reason,
                List<String> reports) {
            this.suiteId = id;
            this.mode = mode;
            this.planSha256 = hash;
            this.startedAtEpochMs = started;
            this.completedAtEpochMs = ended;
            this.requested = requested;
            this.passed = passed;
            this.failed = failed;
            this.status = status;
            this.reason = reason;
            this.reportIds = Collections.unmodifiableList(new ArrayList<>(reports));
        }
    }

    private final Path labRoot;
    private final Path projectRoot;
    private final Path suiteRoot;
    private final LaboratoryReportStore reports;

    public LaboratorySuiteStore(File appFilesDir, String projectId) {
        if (appFilesDir == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid suite project");
        }
        Path app = appFilesDir.toPath().toAbsolutePath().normalize();
        labRoot = app.resolve("laboratory");
        projectRoot = labRoot.resolve(projectId.isEmpty() ? "legacy" : "project-" + projectId);
        suiteRoot = projectRoot.resolve("suites");
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
                String name = path.getFileName().toString();
                if (Files.isSymbolicLink(path) || !Files.isRegularFile(path,
                        LinkOption.NOFOLLOW_LINKS)) {
                    throw new IOException("unsafe suite entry");
                }
                boolean start = name.endsWith(".start");
                boolean end = name.endsWith(".done");
                String id = name.substring(0, name.length()
                    - (start ? 6 : end ? 5 : 0));
                if ((!start && !end) || !LaboratorySnapshotStore.validId(id)) {
                    throw new IOException("unexpected suite entry");
                }
                if (start) starts++;
            }
        }
        if (starts >= MAX_SUITES || entries >= MAX_ENTRIES) {
            throw new IOException("suite limit reached; no history was deleted");
        }
    }

    public synchronized Summary begin(String mode, String planSha256, int requested,
            List<String> baselineReportIds) throws IOException {
        if (!("BATCH".equals(mode) || "REPLAY".equals(mode)
                || "REGRESSION".equals(mode))
                || planSha256 == null || !planSha256.matches("[0-9a-f]{64}")
                || requested < 1 || requested > 8 || baselineReportIds == null
                || baselineReportIds.size() > 4
                || ("REGRESSION".equals(mode)
                    != (baselineReportIds.size() == requested))) {
            throw new IllegalArgumentException("invalid suite plan");
        }
        ensureWritable();
        JSONArray baselines = new JSONArray();
        for (String id : baselineReportIds) {
            if (!LaboratorySnapshotStore.validId(id)) {
                throw new IllegalArgumentException("invalid regression baseline id");
            }
            JSONObject reference = new JSONObject();
            try {
                reference.put("id", id);
                reference.put("sha256", sha256(reports.read(id)));
            } catch (JSONException malformed) {
                throw new IOException("could not encode suite baseline", malformed);
            }
            baselines.put(reference);
        }
        String id = UUID.randomUUID().toString();
        long started = System.currentTimeMillis();
        JSONObject start = new JSONObject();
        try {
            start.put("schemaVersion", FORMAT);
            start.put("kind", "start");
            start.put("suiteId", id);
            start.put("mode", mode);
            start.put("planSha256", planSha256);
            start.put("requested", requested);
            start.put("startedAtEpochMs", started);
            start.put("baselines", baselines);
        } catch (JSONException malformed) {
            throw new IOException("could not encode suite start", malformed);
        }
        writeNew(path(id, ".start"), start.toString());
        return new Summary(id, mode, planSha256, started, 0,
            requested, 0, 0, Status.RUNNING_OR_INTERRUPTED, "START_RECORDED",
            Collections.emptyList());
    }

    public synchronized Summary complete(String suiteId, Status finalStatus,
            List<String> reportIds, int passed, int failed, String reason)
            throws IOException {
        if (!LaboratorySnapshotStore.validId(suiteId)
                || finalStatus == null || finalStatus == Status.RUNNING_OR_INTERRUPTED
                || reportIds == null || reportIds.size() > 8 || passed < 0 || failed < 0
                || passed + failed > 8 || reason == null
                || !reason.matches("[A-Z_]{3,40}")) {
            throw new IllegalArgumentException("invalid suite completion");
        }
        Summary started = read(suiteId);
        if (started.status != Status.RUNNING_OR_INTERRUPTED) {
            throw new IOException("suite already has a terminal record");
        }
        int expectedRuns = started.requested * ("REPLAY".equals(started.mode) ? 2 : 1);
        if ((finalStatus == Status.PASS
                    && (passed != started.requested || failed != 0
                        || reportIds.size() != expectedRuns
                        || !"ALL_CASES_MATCHED".equals(reason)))
                || (finalStatus == Status.FAIL && failed == 0)) {
            throw new IOException("suite result does not match the completed work");
        }
        JSONArray references = new JSONArray();
        for (String reportId : reportIds) {
            if (!LaboratorySnapshotStore.validId(reportId)) {
                throw new IllegalArgumentException("invalid suite report id");
            }
            JSONObject item = new JSONObject();
            try {
                item.put("id", reportId);
                String rawReport = reports.read(reportId);
                if (finalStatus == Status.PASS) verifyPassingBuiltInReport(rawReport);
                item.put("sha256", sha256(rawReport));
            } catch (JSONException malformed) {
                throw new IOException("could not encode suite evidence", malformed);
            }
            references.put(item);
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
            end.put("reports", references);
        } catch (JSONException malformed) {
            throw new IOException("could not encode suite completion", malformed);
        }
        writeNew(path(suiteId, ".done"), end.toString());
        return read(suiteId);
    }

    public synchronized Summary read(String suiteId) throws IOException {
        if (!LaboratorySnapshotStore.validId(suiteId)) {
            throw new IOException("invalid suite ID");
        }
        requireExistingVault();
        String rawStart = readRecord(path(suiteId, ".start"));
        try {
            JSONObject start = new JSONObject(rawStart);
            if (start.getInt("schemaVersion") != FORMAT
                    || !"start".equals(start.getString("kind"))
                    || !suiteId.equals(start.getString("suiteId"))
                    || !start.getString("planSha256").matches("[0-9a-f]{64}")
                    || start.getInt("requested") < 1 || start.getInt("requested") > 8
                    || start.getLong("startedAtEpochMs") <= 0) {
                throw new IOException("suite start is invalid");
            }
            JSONArray baselines = start.getJSONArray("baselines");
            for (int i = 0; i < baselines.length(); i++) {
                verifyReference(baselines.getJSONObject(i));
            }
            String mode = start.getString("mode");
            if (!("BATCH".equals(mode) || "REPLAY".equals(mode)
                    || "REGRESSION".equals(mode))) {
                throw new IOException("unknown suite mode");
            }
            if ("REGRESSION".equals(mode)
                    != (baselines.length() == start.getInt("requested"))) {
                throw new IOException("suite baseline count is invalid");
            }
            if (!Files.exists(path(suiteId, ".done"), LinkOption.NOFOLLOW_LINKS)) {
                return new Summary(suiteId, mode,
                    start.getString("planSha256"), start.getLong("startedAtEpochMs"),
                    0, start.getInt("requested"), 0, 0,
                    Status.RUNNING_OR_INTERRUPTED, "START_RECORDED",
                    Collections.emptyList());
            }
            JSONObject end = new JSONObject(readRecord(path(suiteId, ".done")));
            if (end.getInt("schemaVersion") != FORMAT
                    || !"end".equals(end.getString("kind"))
                    || !suiteId.equals(end.getString("suiteId"))
                    || !sha256(rawStart).equals(end.getString("startSha256"))
                    || end.getLong("completedAtEpochMs") < start.getLong("startedAtEpochMs")) {
                throw new IOException("suite completion is not bound to its start");
            }
            Status status;
            try {
                status = Status.valueOf(end.getString("status"));
            } catch (IllegalArgumentException bad) {
                throw new IOException("suite has an invalid final status", bad);
            }
            if (status == Status.RUNNING_OR_INTERRUPTED
                    || end.getInt("passed") < 0 || end.getInt("failed") < 0
                    || end.getInt("passed") + end.getInt("failed")
                        > start.getInt("requested")
                    || !end.getString("reason").matches("[A-Z_]{3,40}")) {
                throw new IOException("suite completion is inconsistent");
            }
            List<String> refs = new ArrayList<>();
            JSONArray records = end.getJSONArray("reports");
            if (records.length() > 8) throw new IOException("too many suite evidence records");
            if (status == Status.PASS
                    && (end.getInt("passed") != start.getInt("requested")
                        || end.getInt("failed") != 0
                        || records.length() != start.getInt("requested")
                            * ("REPLAY".equals(mode) ? 2 : 1)
                        || !"ALL_CASES_MATCHED".equals(end.getString("reason")))) {
                throw new IOException("suite PASS lacks complete evidence");
            }
            if (status == Status.FAIL && end.getInt("failed") == 0) {
                throw new IOException("suite FAIL lacks a failed request");
            }
            for (int i = 0; i < records.length(); i++) {
                JSONObject reference = records.getJSONObject(i);
                JSONObject report = verifyReference(reference);
                if (status == Status.PASS) verifyPassingBuiltInReport(report.toString());
                refs.add(reference.getString("id"));
            }
            return new Summary(suiteId, mode, start.getString("planSha256"),
                start.getLong("startedAtEpochMs"), end.getLong("completedAtEpochMs"),
                start.getInt("requested"), end.getInt("passed"), end.getInt("failed"),
                status, end.getString("reason"), refs);
        } catch (JSONException malformed) {
            throw new IOException("suite metadata is incomplete or malformed", malformed);
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
        java.util.Set<String> completedIds = new java.util.HashSet<>();
        try (Stream<Path> stream = Files.list(suiteRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_ENTRIES) throw new IOException("suite vault exceeds limit");
            for (Path path : paths) {
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unsafe suite record");
                }
                String name = path.getFileName().toString();
                boolean start = name.endsWith(".start");
                boolean done = name.endsWith(".done");
                if (!start && !done) throw new IOException("unexpected suite record");
                String id = name.substring(0, name.length() - (start ? 6 : 5));
                if (!LaboratorySnapshotStore.validId(id)) {
                    throw new IOException("invalid suite ID in vault");
                }
                if (start) ids.add(id);
                else completedIds.add(id);
            }
        }
        for (String id : completedIds) {
            if (!ids.contains(id)) {
                throw new IOException("suite completion is missing its START record");
            }
        }
        if (ids.size() > MAX_SUITES) throw new IOException("too many suite records");
        List<Summary> summaries = new ArrayList<>();
        for (String id : ids) summaries.add(read(id));
        summaries.sort(Comparator.comparingLong((Summary s) -> s.startedAtEpochMs)
            .reversed().thenComparing(s -> s.suiteId));
        return Collections.unmodifiableList(summaries);
    }

    private JSONObject verifyReference(JSONObject reference) throws IOException, JSONException {
        String id = reference.getString("id");
        String digest = reference.getString("sha256");
        if (!LaboratorySnapshotStore.validId(id) || !digest.matches("[0-9a-f]{64}")) {
            throw new IOException("invalid suite report reference");
        }
        String raw = reports.read(id);
        if (!digest.equals(sha256(raw))) {
            throw new IOException("suite report evidence has changed or is outside project");
        }
        return new JSONObject(raw);
    }

    private static void verifyPassingBuiltInReport(String raw) throws IOException {
        try {
            JSONObject report = new JSONObject(raw);
            String tool = report.getString("toolId");
            boolean allowlisted = LaboratoryEngine.FINGERPRINT_TOOL.equals(tool)
                || LaboratoryEngine.WORLD_CONTACT_TOOL.equals(tool);
            if (!allowlisted || report.getInt("schemaVersion") != 1
                    || !"PASS".equals(report.getString("status"))
                    || !"EXPERIMENTAL".equals(report.getString("stage"))
                    || report.getInt("failed") != 0
                    || report.getInt("passed") != report.getJSONArray("checks").length()) {
                throw new IOException("suite PASS refers to non-passing or non-built-in evidence");
            }
        } catch (JSONException invalid) {
            throw new IOException("suite PASS evidence is malformed", invalid);
        }
    }

    private Path path(String id, String extension) {
        return suiteRoot.resolve(id + extension);
    }

    private void requireExistingVault() throws IOException {
        for (Path dir : new Path[]{labRoot, projectRoot, suiteRoot}) {
            if (!Files.isDirectory(dir, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(dir)) {
                throw new IOException("suite vault directory is missing or unsafe");
            }
        }
    }

    private static void ensureSafeDir(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException raced) {
                // Revalidate below; never follow links.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe suite directory");
        }
    }

    private static void writeNew(Path path, String raw) throws IOException {
        String text = raw + "\n" + sha256(raw) + "\n";
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("suite record exceeds size budget");
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
            throw new IOException("suite record missing, linked or oversized");
        }
        byte[] binary = Files.readAllBytes(path);
        String text = new String(binary, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(binary, text.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("suite record has invalid UTF-8");
        }
        String[] lines = text.split("\n", -1);
        if (lines.length != 3 || !lines[2].isEmpty()
                || !lines[1].matches("[0-9a-f]{64}")
                || !sha256(lines[0]).equals(lines[1])) {
            throw new IOException("suite record integrity check failed");
        }
        return lines[0];
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder(64);
            for (byte unit : digest) {
                result.append(String.format(Locale.ROOT, "%02x", unit & 255));
            }
            return result.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
