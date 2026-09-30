package com.cafeina.executor;

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
 * Privacy-preserving audit receipts for actual use of a STABLE tool.
 *
 * Raw tool_input, stdout, errors and return values are never persisted here.
 * Each receipt is bound to the exact historical ACTIVATE event that authorized
 * the execution. A later rollback/deactivation does not erase old evidence.
 */
public final class LaboratoryStableUseStore {
    public static final int MAX_USES = 256;
    private static final int MAX_RECORD_BYTES = 8 * 1024;
    private static final int FORMAT = 1;

    public static final class Use {
        public final String runId;
        public final String toolId;
        public final String toolVersion;
        public final String manifestSha256;
        public final String sourceSha256;
        public final String snapshotId;
        public final String activationEventSha256;
        public final String inputSha256;
        public final String firstReturnSha256;
        public final String outputSha256;
        public final String errorSha256;
        public final String workerStatus;
        public final int workerUid;
        public final long startedAtEpochMs;
        public final long durationMs;
        public final boolean selectionVerified;
        public final boolean usable;

        private Use(String runId, String toolId, String version, String manifestSha,
                String sourceSha, String snapshotId, String activationSha,
                String inputSha, String returnSha, String outputSha, String errorSha,
                String status, int workerUid, long started, long duration,
                boolean selectionVerified, boolean usable) {
            this.runId = runId;
            this.toolId = toolId;
            this.toolVersion = version;
            this.manifestSha256 = manifestSha;
            this.sourceSha256 = sourceSha;
            this.snapshotId = snapshotId;
            this.activationEventSha256 = activationSha;
            this.inputSha256 = inputSha;
            this.firstReturnSha256 = returnSha;
            this.outputSha256 = outputSha;
            this.errorSha256 = errorSha;
            this.workerStatus = status;
            this.workerUid = workerUid;
            this.startedAtEpochMs = started;
            this.durationMs = duration;
            this.selectionVerified = selectionVerified;
            this.usable = usable;
        }
    }

    private final Path labRoot;
    private final Path projectRoot;
    private final Path useRoot;
    private final LaboratoryStableActivationStore stable;

    public LaboratoryStableUseStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid stable-use project");
        }
        Path app = appFilesDirectory.toPath().toAbsolutePath().normalize();
        labRoot = app.resolve("laboratory");
        projectRoot = labRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        useRoot = projectRoot.resolve("stable-tool-uses");
        stable = new LaboratoryStableActivationStore(appFilesDirectory, projectId);
    }

    public synchronized void ensureWritable() throws IOException {
        ensureSafeDir(labRoot);
        ensureSafeDir(projectRoot);
        ensureSafeDir(useRoot);
        try (Stream<Path> stream = Files.list(useRoot)) {
            List<Path> items = new ArrayList<>();
            stream.forEach(items::add);
            if (items.size() >= MAX_USES) {
                throw new IOException("stable-use audit limit reached; history was preserved");
            }
            for (Path path : items) {
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)
                        || !path.getFileName().toString().endsWith(".use")) {
                    throw new IOException("unsafe stable-use audit entry");
                }
            }
        }
    }

    public synchronized Use save(LaboratoryStableActivationStore.Active authorization,
            LaboratorySandboxClient.Result result, boolean selectionVerified)
            throws IOException {
        if (authorization == null || result == null
                || !LaboratorySnapshotStore.validId(result.runId)
                || !result.sourceSha256.matches("[0-9a-f]{64}")
                || !result.inputSha256.matches("[0-9a-f]{64}")
                || result.workerUid < 1 || result.startedAtEpochMs <= 0
                || result.durationMs < 0 || !validWorkerStatus(result.status)) {
            throw new IOException("invalid stable-tool execution evidence");
        }
        if (!authorization.sourceSha256.equals(result.sourceSha256)) {
            throw new IOException("stable-tool source does not match isolated execution");
        }
        ensureWritable();
        Path target = useRoot.resolve(result.runId + ".use");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("stable-tool execution was already recorded");
        }

        JSONObject object = new JSONObject();
        try {
            object.put("schemaVersion", FORMAT);
            object.put("runId", result.runId);
            object.put("toolId", authorization.toolId);
            object.put("toolVersion", authorization.version);
            object.put("manifestSha256", authorization.manifestSha256);
            object.put("sourceSha256", authorization.sourceSha256);
            object.put("snapshotId", authorization.snapshotId);
            object.put("evidenceRunId", authorization.evidenceRunId);
            object.put("approvalReceiptSha256", authorization.approvalReceiptSha256);
            object.put("activationEventSha256", authorization.activationEventSha256);
            object.put("inputSha256", result.inputSha256);
            object.put("firstReturnSha256", sha256(result.firstReturn));
            object.put("outputSha256", sha256(result.output));
            object.put("errorSha256", sha256(result.error));
            object.put("workerStatus", result.status);
            object.put("workerUid", result.workerUid);
            object.put("startedAtEpochMs", result.startedAtEpochMs);
            object.put("durationMs", result.durationMs);
            object.put("selectionVerified", selectionVerified);
            object.put("usable", selectionVerified && "EXECUTED".equals(result.status));
        } catch (JSONException malformed) {
            throw new IOException("could not encode stable-tool use receipt", malformed);
        }
        writeNew(target, object.toString());
        return read(result.runId);
    }

    public synchronized Use read(String runId) throws IOException {
        if (!LaboratorySnapshotStore.validId(runId)) {
            throw new IOException("invalid stable-use run id");
        }
        requireVault();
        JSONObject object = readRecord(useRoot.resolve(runId + ".use"));
        try {
            if (object.getInt("schemaVersion") != FORMAT
                    || !runId.equals(object.getString("runId"))
                    || !object.getString("manifestSha256").matches("[0-9a-f]{64}")
                    || !object.getString("sourceSha256").matches("[0-9a-f]{64}")
                    || !LaboratorySnapshotStore.validId(object.getString("snapshotId"))
                    || !LaboratorySnapshotStore.validId(object.getString("evidenceRunId"))
                    || !object.getString("approvalReceiptSha256").matches("[0-9a-f]{64}")
                    || !object.getString("activationEventSha256").matches("[0-9a-f]{64}")
                    || !object.getString("inputSha256").matches("[0-9a-f]{64}")
                    || !object.getString("firstReturnSha256").matches("[0-9a-f]{64}")
                    || !object.getString("outputSha256").matches("[0-9a-f]{64}")
                    || !object.getString("errorSha256").matches("[0-9a-f]{64}")
                    || !validWorkerStatus(object.getString("workerStatus"))
                    || object.getInt("workerUid") < 1
                    || object.getLong("startedAtEpochMs") <= 0
                    || object.getLong("durationMs") < 0
                    || object.getBoolean("usable")
                        != (object.getBoolean("selectionVerified")
                            && "EXECUTED".equals(object.getString("workerStatus")))) {
                throw new IOException("stable-use receipt fields are invalid");
            }
            verifyHistoricalAuthorization(object);
            return new Use(runId, object.getString("toolId"),
                object.getString("toolVersion"), object.getString("manifestSha256"),
                object.getString("sourceSha256"), object.getString("snapshotId"),
                object.getString("activationEventSha256"),
                object.getString("inputSha256"),
                object.getString("firstReturnSha256"),
                object.getString("outputSha256"), object.getString("errorSha256"),
                object.getString("workerStatus"), object.getInt("workerUid"),
                object.getLong("startedAtEpochMs"), object.getLong("durationMs"),
                object.getBoolean("selectionVerified"), object.getBoolean("usable"));
        } catch (JSONException malformed) {
            throw new IOException("stable-use receipt is malformed", malformed);
        }
    }

    public synchronized List<Use> list() throws IOException {
        if (!Files.exists(useRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireVault();
        List<Use> uses = new ArrayList<>();
        try (Stream<Path> stream = Files.list(useRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_USES) {
                throw new IOException("stable-use audit exceeds limit");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".use")) {
                    throw new IOException("unexpected stable-use audit entry");
                }
                String id = name.substring(0, name.length() - 4);
                uses.add(read(id));
            }
        }
        uses.sort(Comparator.comparingLong((Use u) -> u.startedAtEpochMs)
            .reversed().thenComparing(u -> u.runId));
        return Collections.unmodifiableList(uses);
    }

    private void verifyHistoricalAuthorization(JSONObject use)
            throws IOException, JSONException {
        String toolId = use.getString("toolId");
        String version = use.getString("toolVersion");
        String activationHash = use.getString("activationEventSha256");
        LaboratoryStableActivationStore.Event matched = null;
        for (LaboratoryStableActivationStore.Event event : stable.listHistory(toolId)) {
            if (event.eventSha256.equals(activationHash)) {
                matched = event;
                break;
            }
        }
        if (matched == null || matched.type != LaboratoryStableActivationStore.Type.ACTIVATE
                || !version.equals(matched.version)
                || !use.getString("manifestSha256").equals(matched.manifestSha256)
                || !use.getString("sourceSha256").equals(matched.sourceSha256)
                || !use.getString("snapshotId").equals(matched.snapshotId)
                || !use.getString("evidenceRunId").equals(matched.evidenceRunId)
                || !use.getString("approvalReceiptSha256")
                    .equals(matched.approvalReceiptSha256)) {
            throw new IOException("stable-use receipt lacks matching activation history");
        }
    }

    private static boolean validWorkerStatus(String status) {
        return "EXECUTED".equals(status) || "LUAU_ERROR".equals(status)
            || "TIMEOUT".equals(status) || "CANCELLED".equals(status)
            || "WORKER_ERROR".equals(status) || "PROCESS_DIED".equals(status)
            || "BIND_FAILED".equals(status) || "ISOLATION_FAILED".equals(status)
            || "REJECTED".equals(status);
    }

    private void requireVault() throws IOException {
        for (Path path : new Path[]{labRoot, projectRoot, useRoot}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("stable-use audit directory missing or unsafe");
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
            throw new IOException("unsafe stable-use audit directory");
        }
    }

    private static void writeNew(Path target, String raw) throws IOException {
        String text = raw + "\n" + sha256(raw) + "\n";
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("stable-use receipt exceeds size budget");
        }
        try (FileChannel channel = FileChannel.open(target,
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer buffer = ByteBuffer.wrap(bytes);
            while (buffer.hasRemaining()) channel.write(buffer);
            channel.force(true);
        }
    }

    private static JSONObject readRecord(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException("stable-use receipt missing, linked or oversized");
        }
        byte[] binary = Files.readAllBytes(path);
        String text = new String(binary, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(binary, text.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("stable-use receipt is not valid UTF-8");
        }
        String[] lines = text.split("\n", -1);
        if (lines.length != 3 || !lines[2].isEmpty()
                || !lines[1].matches("[0-9a-f]{64}")
                || !sha256(lines[0]).equals(lines[1])) {
            throw new IOException("stable-use receipt integrity check failed");
        }
        try {
            return new JSONObject(lines[0]);
        } catch (JSONException malformed) {
            throw new IOException("stable-use receipt JSON is invalid", malformed);
        }
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                (value == null ? "" : value).getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) out.append(String.format(Locale.ROOT, "%02x", b & 255));
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
