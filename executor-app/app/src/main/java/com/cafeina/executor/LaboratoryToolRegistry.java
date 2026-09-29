package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.StandardOpenOption;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
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
 * Versioned, per-project metadata catalog for internal Luau tool candidates.
 *
 * EXPERIMENTAL manifests and CANDIDATE review requests are create-only.
 * Neither state grants execution capabilities: the existing isolated Luau
 * worker remains the only candidate execution path. There is deliberately
 * NO method/API for STABLE activation, approval, updating runtime permissions,
 * deleting evidence or changing the application's core.
 *
 * Review requests are not user approval. A future UI approval path must be
 * separately designed and proven to be initiated by a real user.
 */
public final class LaboratoryToolRegistry {
    public static final int MAX_VERSIONS = 64;
    private static final int MAX_DIRECTORY_ENTRIES = 128;
    private static final int MAX_RECORD_BYTES = 1024;
    private static final String MANIFEST_MAGIC = "CAFEINA_LAB_TOOL";
    private static final String REVIEW_MAGIC = "CAFEINA_LAB_REVIEW";
    private static final String FORMAT = "1";
    private static final String CAPABILITY = "LUAU_ISOLATED_NO_FILES";

    private final File appFilesDirectory;
    private final String projectId;
    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path toolsRoot;
    private final Path manifests;
    private final Path reviews;
    private final LaboratorySnapshotStore snapshots;
    private final LaboratoryReportStore reports;

    public enum State { EXPERIMENTAL, CANDIDATE }

    public static final class Tool {
        public final String id;
        public final String version;
        public final String sourceSha256;
        public final String snapshotId;
        public final String manifestSha256;
        public final String capability;
        public final int timeoutMs;
        public final long createdAtEpochMs;
        public final State state;
        public final String evidenceRunId;

        private Tool(String id, String version, String sourceSha256, String snapshotId,
                String manifestSha256, int timeoutMs, long created,
                State state, String evidenceRunId) {
            this.id = id;
            this.version = version;
            this.sourceSha256 = sourceSha256;
            this.snapshotId = snapshotId;
            this.manifestSha256 = manifestSha256;
            this.capability = CAPABILITY;
            this.timeoutMs = timeoutMs;
            this.createdAtEpochMs = created;
            this.state = state;
            this.evidenceRunId = evidenceRunId;
        }
    }

    public LaboratoryToolRegistry(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid tool registry project");
        }
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        Path app = appFilesDirectory.toPath().toAbsolutePath().normalize();
        this.laboratoryRoot = app.resolve("laboratory");
        this.projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        this.toolsRoot = projectRoot.resolve("tools");
        this.manifests = toolsRoot.resolve("manifests");
        this.reviews = toolsRoot.resolve("reviews");
        this.snapshots = new LaboratorySnapshotStore(appFilesDirectory, projectId);
        this.reports = new LaboratoryReportStore(appFilesDirectory, projectId);
    }

    /**
     * Fail before starting an expensive candidate run if this immutable tool
     * version already exists or the private registry has reached its budget.
     */
    public synchronized void assertVersionAvailable(String toolId, String version)
            throws IOException {
        checkIdentity(toolId, version);
        ensureWritable();
        if (countManifestFiles() >= MAX_VERSIONS) {
            throw new IOException("tool version limit reached; no existing tools deleted");
        }
        if (Files.exists(manifests.resolve(key(toolId, version) + ".tool"),
                LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("tool version already registered; replacing is forbidden");
        }
    }

    /**
     * Explicitly register an already-snapshotted candidate; never read editor
     * state, grant permissions or auto-execute the candidate.
     */
    public synchronized Tool registerExperimental(String toolId, String version,
            String snapshotId, int timeoutMs) throws IOException {
        checkIdentity(toolId, version);
        if (!LaboratorySnapshotStore.validId(snapshotId)
                || timeoutMs < 1 || timeoutMs > LaboratorySandboxService.MAX_TIMEOUT_MS) {
            throw new IllegalArgumentException("invalid tool snapshot or timeout");
        }
        LaboratorySnapshotStore.Snapshot baseline = snapshots.readCopy(snapshotId);
        if (!"candidate-luau".equals(baseline.label)) {
            throw new IOException("only approved candidate-luau snapshots may be registered");
        }
        byte[] bytes = baseline.contentCopy();
        String source = new String(bytes, StandardCharsets.UTF_8);
        if (bytes.length == 0 || bytes.length > 64 * 1024
                || source.isEmpty() || source.length() > LaboratorySandboxService.MAX_SOURCE_CHARS
                || !java.util.Arrays.equals(bytes, source.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("candidate does not fit the isolated worker source budget");
        }

        assertVersionAvailable(toolId, version);
        String key = key(toolId, version);
        Path destination = manifests.resolve(key + ".tool");
        long created = System.currentTimeMillis();
        String payload = lines(MANIFEST_MAGIC, FORMAT, toolId, version,
            snapshotId, baseline.sha256, Integer.toString(timeoutMs),
            Long.toString(created), CAPABILITY);
        String digest = sha256(payload);
        writeNew(destination, payload + digest + "\n");
        return new Tool(toolId, version, baseline.sha256, snapshotId,
            digest, timeoutMs, created, State.EXPERIMENTAL, "");
    }

    /**
     * Propose a candidate for HUMAN REVIEW, never activate it. The evidence
     * must be a durable PASS report of the same source/snapshot in the
     * isolated worker. A report with mismatched or altered bytes fails closed.
     */
    public synchronized Tool requestCandidateReview(String toolId, String version,
            String evidenceRunId) throws IOException {
        checkIdentity(toolId, version);
        if (!LaboratorySnapshotStore.validId(evidenceRunId)) {
            throw new IllegalArgumentException("invalid candidate evidence ID");
        }
        Tool experimental = read(toolId, version);
        if (experimental.state != State.EXPERIMENTAL) {
            throw new IOException("candidate review already recorded");
        }
        String evidence = passingEvidence(experimental, evidenceRunId);
        String reportSha = sha256(evidence);
        String payload = lines(REVIEW_MAGIC, FORMAT, toolId, version,
            experimental.manifestSha256, evidenceRunId, reportSha,
            Long.toString(System.currentTimeMillis()));
        String digest = sha256(payload);
        ensureWritable();
        writeNew(reviews.resolve(key(toolId, version) + ".review"),
            payload + digest + "\n");
        return read(toolId, version);
    }

    public synchronized Tool read(String toolId, String version) throws IOException {
        checkIdentity(toolId, version);
        requireExistingVault();
        Path file = manifests.resolve(key(toolId, version) + ".tool");
        String[] fields = parseRecord(file, MANIFEST_MAGIC, 11);
        if (!toolId.equals(fields[2]) || !version.equals(fields[3])
                || !LaboratorySnapshotStore.validId(fields[4])
                || !fields[5].matches("[0-9a-f]{64}")
                || !CAPABILITY.equals(fields[8])) {
            throw new IOException("tool manifest has invalid identity or capability");
        }
        final int timeout;
        final long created;
        try {
            timeout = Integer.parseInt(fields[6]);
            created = Long.parseLong(fields[7]);
        } catch (NumberFormatException bad) {
            throw new IOException("tool manifest contains invalid numeric fields", bad);
        }
        if (timeout < 1 || timeout > LaboratorySandboxService.MAX_TIMEOUT_MS
                || created <= 0) {
            throw new IOException("tool manifest exceeds bounded worker limits");
        }
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.readCopy(fields[4]);
        if (!"candidate-luau".equals(snapshot.label)
                || !snapshot.sha256.equals(fields[5])) {
            throw new IOException("tool source snapshot changed or is not approved input");
        }

        Path reviewFile = reviews.resolve(key(toolId, version) + ".review");
        if (!Files.exists(reviewFile, LinkOption.NOFOLLOW_LINKS)) {
            return new Tool(toolId, version, fields[5], fields[4], fields[9],
                timeout, created, State.EXPERIMENTAL, "");
        }
        String[] review = parseRecord(reviewFile, REVIEW_MAGIC, 10);
        if (!toolId.equals(review[2]) || !version.equals(review[3])
                || !fields[9].equals(review[4])
                || !LaboratorySnapshotStore.validId(review[5])
                || !review[6].matches("[0-9a-f]{64}")) {
            throw new IOException("candidate review is not bound to this tool version");
        }
        String savedReport = passingEvidence(
            new Tool(toolId, version, fields[5], fields[4], fields[9],
                timeout, created, State.EXPERIMENTAL, ""), review[5]);
        if (!sha256(savedReport).equals(review[6])) {
            throw new IOException("candidate evidence changed after review request");
        }
        return new Tool(toolId, version, fields[5], fields[4], fields[9],
            timeout, created, State.CANDIDATE, review[5]);
    }

    public synchronized List<Tool> list() throws IOException {
        if (!Files.exists(laboratoryRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(projectRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(toolsRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireExistingVault();
        List<Tool> found = new ArrayList<>();
        try (Stream<Path> stream = Files.list(manifests)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_DIRECTORY_ENTRIES) {
                throw new IOException("tool registry exceeds entry budget");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".tool")) {
                    throw new IOException("unexpected entry in tool registry");
                }
                String key = name.substring(0, name.length() - 5);
                int split = key.lastIndexOf('@');
                if (split <= 0) throw new IOException("invalid tool manifest name");
                String toolId = key.substring(0, split);
                String version = key.substring(split + 1);
                if (!validIdentity(toolId, version)) {
                    throw new IOException("invalid tool manifest filename");
                }
                found.add(read(toolId, version));
            }
        }
        if (found.size() > MAX_VERSIONS) {
            throw new IOException("tool version budget exceeded");
        }
        found.sort(Comparator.comparing((Tool t) -> t.id)
            .thenComparing(t -> t.version));
        return Collections.unmodifiableList(found);
    }

    /** No method exists to promote, execute, overwrite or delete tools here. */

    private String passingEvidence(Tool tool, String reportId) throws IOException {
        final String raw = reports.read(reportId);
        try {
            JSONObject report = new JSONObject(raw);
            JSONArray checks = report.getJSONArray("checks");
            if (report.getInt("schemaVersion") != 2
                    || !reportId.equals(report.getString("runId"))
                    || !"luau-isolated-candidate".equals(report.getString("toolId"))
                    || !"EXPERIMENTAL".equals(report.getString("stage"))
                    || !"PASS".equals(report.getString("status"))
                    || !"EXECUTED".equals(report.getString("workerStatus"))
                    || !report.getBoolean("snapshotVerified")
                    || !tool.snapshotId.equals(report.getString("candidateSnapshotId"))
                    || !tool.sourceSha256.equals(report.getString("candidateBatchSha256"))
                    || report.getInt("workerUid") < 1
                    || report.getInt("passed") != 1 || report.getInt("failed") != 0
                    || checks.length() != 1
                    || !checks.getJSONObject(0).getBoolean("passed")
                    || !tool.sourceSha256.equals(
                        checks.getJSONObject(0).getString("inputSha256"))) {
                throw new IOException("candidate evidence does not prove a passing isolated test");
            }
            return raw;
        } catch (JSONException invalid) {
            throw new IOException("candidate evidence is missing required fields", invalid);
        }
    }

    private static void checkIdentity(String id, String version) {
        if (!validIdentity(id, version)) {
            throw new IllegalArgumentException("invalid tool id or version");
        }
    }

    private static boolean validIdentity(String id, String version) {
        return id != null && id.matches("[a-z][a-z0-9-]{2,47}")
            && version != null
            && version.matches("(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})");
    }

    private static String key(String id, String version) {
        return id + "@" + version;
    }

    private int countManifestFiles() throws IOException {
        try (Stream<Path> stream = Files.list(manifests)) {
            return (int) stream.filter(p -> p.getFileName().toString().endsWith(".tool"))
                .limit(MAX_VERSIONS + 1).count();
        }
    }

    private static String[] parseRecord(Path path, String magic,
            int requiredParts) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException("tool record missing, linked or oversized");
        }
        byte[] raw = Files.readAllBytes(path);
        String serialized = new String(raw, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(raw, serialized.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("tool record is not valid UTF-8");
        }
        String[] parts = serialized.split("\n", -1);
        if (parts.length != requiredParts || !magic.equals(parts[0])
                || !FORMAT.equals(parts[1])
                || !parts[requiredParts - 1].isEmpty()) {
            throw new IOException("tool record format is invalid");
        }
        String providedHash = parts[requiredParts - 2];
        String canonical = serialized.substring(0,
            serialized.length() - providedHash.length() - 1);
        if (!providedHash.matches("[0-9a-f]{64}")
                || !sha256(canonical).equals(providedHash)) {
            throw new IOException("tool record integrity check failed");
        }
        return parts;
    }

    private void ensureWritable() throws IOException {
        ensureSafeDir(laboratoryRoot);
        ensureSafeDir(projectRoot);
        ensureSafeDir(toolsRoot);
        ensureSafeDir(manifests);
        ensureSafeDir(reviews);
        checkEntryBudget(manifests);
        checkEntryBudget(reviews);
    }

    private void requireExistingVault() throws IOException {
        for (Path path : new Path[]{laboratoryRoot, projectRoot, toolsRoot, manifests, reviews}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("tool registry directory missing or unsafe");
            }
        }
    }

    private static void ensureSafeDir(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Validate the existing object below; never follow a symlink.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe tool registry directory");
        }
    }

    private static void checkEntryBudget(Path directory) throws IOException {
        try (Stream<Path> stream = Files.list(directory)) {
            if (stream.limit(MAX_DIRECTORY_ENTRIES + 1).count() > MAX_DIRECTORY_ENTRIES) {
                throw new IOException("tool registry directory entry budget reached");
            }
        }
    }

    private static void writeNew(Path destination, String content) throws IOException {
        byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("tool record exceeds size limit");
        }
        // Hard links are blocked on some Android app data filesystems. CREATE_NEW
        // reserves the destination atomically and never replaces an old version.
        // If the app crashes during this small bounded write, the incomplete
        // record stays visible and fails its digest check; do not auto-delete it.
        try (FileChannel output = FileChannel.open(destination,
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer data = ByteBuffer.wrap(bytes);
            while (data.hasRemaining()) output.write(data);
            output.force(true);
        }
    }

    private static String lines(String... values) {
        StringBuilder out = new StringBuilder();
        for (String value : values) out.append(value).append('\n');
        return out.toString();
    }

    private static String sha256(String text) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(
                text.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte value : bytes) {
                hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
