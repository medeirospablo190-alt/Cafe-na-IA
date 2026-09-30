package com.cafeina.executor;

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
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Create-only audit receipts for actual executions through the verified STABLE gate.
 * Raw source, tool input, stdout, return values and runtime errors are never persisted.
 */
public final class LaboratoryStableUseStore {
    public static final int MAX_USES = 256;
    public static final int MAX_USE_BYTES = 12 * 1024;

    public static final class Use {
        public final String runId;
        public final String toolId;
        public final String toolVersion;
        public final String activationEventId;
        public final int activationSequence;
        public final String snapshotId;
        public final String artifactSha256;
        public final String executedSourceSha256;
        public final String inputSha256;
        public final String executedInputSha256;
        public final String outputSha256;
        public final String errorSha256;
        public final String firstReturnSha256;
        public final String workerStatus;
        public final int workerUid;
        public final long startedAtEpochMs;
        public final long durationMs;
        public final boolean selectionVerified;
        public final boolean usable;

        private Use(String runId, String toolId, String toolVersion,
                String activationEventId, int activationSequence,
                String snapshotId, String artifactSha256, String executedSourceSha256,
                String inputSha256, String executedInputSha256,
                String outputSha256, String errorSha256, String firstReturnSha256,
                String workerStatus, int workerUid, long startedAtEpochMs,
                long durationMs, boolean selectionVerified, boolean usable) {
            this.runId = runId;
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.activationEventId = activationEventId;
            this.activationSequence = activationSequence;
            this.snapshotId = snapshotId;
            this.artifactSha256 = artifactSha256;
            this.executedSourceSha256 = executedSourceSha256;
            this.inputSha256 = inputSha256;
            this.executedInputSha256 = executedInputSha256;
            this.outputSha256 = outputSha256;
            this.errorSha256 = errorSha256;
            this.firstReturnSha256 = firstReturnSha256;
            this.workerStatus = workerStatus;
            this.workerUid = workerUid;
            this.startedAtEpochMs = startedAtEpochMs;
            this.durationMs = durationMs;
            this.selectionVerified = selectionVerified;
            this.usable = usable;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path useDirectory;

    public LaboratoryStableUseStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid stable-use project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        useDirectory = projectRoot.resolve("stable-tool-uses");
    }

    public synchronized void ensureWritable() throws IOException {
        prepareDirectory();
        if (countUses() >= MAX_USES) {
            throw new IOException("stable-use audit limit reached; existing receipts were preserved");
        }
    }

    public synchronized Use save(String toolId, String toolVersion,
            String activationEventId, int activationSequence,
            String snapshotId, String artifactSha256, String inputSha256,
            LaboratorySandboxClient.Result result, boolean selectionVerified)
            throws IOException {
        if (!validToolId(toolId) || !validVersion(toolVersion)
                || !validUuid(activationEventId) || activationSequence < 1
                || !LaboratorySnapshotStore.validId(snapshotId)
                || !validSha(artifactSha256) || !validSha(inputSha256)
                || result == null || !validUuid(result.runId)
                || !validSha(result.sourceSha256) || !validSha(result.inputSha256)
                || result.durationMs < 0) {
            throw new IOException("invalid stable-use audit evidence");
        }
        boolean usable = selectionVerified && "EXECUTED".equals(result.status);
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("runId", result.runId);
            json.put("toolId", toolId);
            json.put("toolVersion", toolVersion);
            json.put("activationEventId", activationEventId);
            json.put("activationSequence", activationSequence);
            json.put("snapshotId", snapshotId);
            json.put("artifactSha256", artifactSha256);
            json.put("executedSourceSha256", result.sourceSha256);
            json.put("inputSha256", inputSha256);
            json.put("executedInputSha256", result.inputSha256);
            json.put("outputSha256", sha256(result.output));
            json.put("errorSha256", sha256(result.error));
            json.put("firstReturnSha256", sha256(result.firstReturn));
            json.put("workerStatus", boundedStatus(result.status));
            json.put("workerUid", result.workerUid);
            json.put("startedAtEpochMs", result.startedAtEpochMs);
            json.put("durationMs", result.durationMs);
            json.put("selectionVerified", selectionVerified);
            json.put("usable", usable);
            writeNew(result.runId, json);
            return parse(json.toString());
        } catch (JSONException error) {
            throw new IOException("could not encode stable-use audit receipt", error);
        }
    }

    public synchronized Use read(String runId) throws IOException {
        if (!validUuid(runId)) throw new IOException("invalid stable-use run id");
        if (!Files.exists(useDirectory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("stable-use receipt not found");
        }
        prepareDirectory();
        try {
            Use value = parse(readSafe(useDirectory.resolve(runId + ".json")));
            if (!runId.equals(value.runId)) throw new IOException("stable-use identity mismatch");
            return value;
        } catch (JSONException error) {
            throw new IOException("invalid stable-use receipt", error);
        }
    }

    public synchronized List<Use> list() throws IOException {
        if (!Files.exists(useDirectory, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        prepareDirectory();
        List<Use> values = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(useDirectory)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_USES) throw new IOException("stable-use audit exceeds limit");
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".json")
                        || !validUuid(name.substring(0, name.length() - 5))) {
                    throw new IOException("unexpected stable-use audit entry");
                }
                try {
                    values.add(parse(readSafe(path)));
                } catch (JSONException error) {
                    throw new IOException("invalid stable-use audit receipt", error);
                }
            }
        }
        values.sort(Comparator.comparingLong((Use use) -> use.startedAtEpochMs)
            .reversed().thenComparing(use -> use.runId));
        return Collections.unmodifiableList(values);
    }

    private void writeNew(String runId, JSONObject json) throws IOException, JSONException {
        ensureWritable();
        Path destination = useDirectory.resolve(runId + ".json");
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("stable-use run already audited");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_USE_BYTES) throw new IOException("stable-use receipt too large");
        Path temporary = useDirectory.resolve("." + runId + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("stable-use run already audited");
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

    private int countUses() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(useDirectory)) {
            return (int) stream.filter(path -> {
                String name = path.getFileName().toString();
                return name.endsWith(".json")
                    && validUuid(name.substring(0, name.length() - 5));
            }).limit(MAX_USES + 1L).count();
        }
    }

    private void prepareDirectory() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(useDirectory);
    }

    private String readSafe(Path path) throws IOException {
        if (!useDirectory.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_USE_BYTES) {
            throw new IOException("stable-use receipt missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static Use parse(String raw) throws JSONException {
        JSONObject json = new JSONObject(raw);
        Use value = new Use(
            json.getString("runId"),
            json.getString("toolId"),
            json.getString("toolVersion"),
            json.getString("activationEventId"),
            json.getInt("activationSequence"),
            json.getString("snapshotId"),
            json.getString("artifactSha256"),
            json.getString("executedSourceSha256"),
            json.getString("inputSha256"),
            json.getString("executedInputSha256"),
            json.getString("outputSha256"),
            json.getString("errorSha256"),
            json.getString("firstReturnSha256"),
            json.getString("workerStatus"),
            json.getInt("workerUid"),
            json.getLong("startedAtEpochMs"),
            json.getLong("durationMs"),
            json.getBoolean("selectionVerified"),
            json.getBoolean("usable"));
        if (!validUuid(value.runId) || !validToolId(value.toolId)
                || !validVersion(value.toolVersion)
                || !validUuid(value.activationEventId)
                || value.activationSequence < 1
                || !LaboratorySnapshotStore.validId(value.snapshotId)
                || !validSha(value.artifactSha256)
                || !validSha(value.executedSourceSha256)
                || !validSha(value.inputSha256)
                || !validSha(value.executedInputSha256)
                || !validSha(value.outputSha256) || !validSha(value.errorSha256)
                || !validSha(value.firstReturnSha256)
                || value.startedAtEpochMs <= 0 || value.durationMs < 0) {
            throw new JSONException("stable-use receipt failed validation");
        }
        return value;
    }

    private static String boundedStatus(String status) {
        if (status == null || !status.matches("[A-Z_]{3,32}")) return "WORKER_ERROR";
        return status;
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                (value == null ? "" : value).getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) out.append(String.format(Locale.ROOT, "%02x", b & 0xff));
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static boolean validSha(String value) {
        return value != null && value.matches("[0-9a-f]{64}");
    }

    private static boolean validUuid(String value) {
        try {
            return value != null && UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static boolean validToolId(String value) {
        return value != null && value.matches("[a-z0-9][a-z0-9._-]{0,63}");
    }

    private static boolean validVersion(String value) {
        return value != null
            && value.matches("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]{1,32})?");
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
            throw new IOException("unsafe stable-use audit directory");
        }
    }
}
