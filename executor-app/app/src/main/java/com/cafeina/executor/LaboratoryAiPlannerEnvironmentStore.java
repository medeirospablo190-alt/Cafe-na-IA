package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

/**
 * Small, read-only diagnostic record describing the environment used by one
 * local-planner action. It intentionally excludes prompt/goal/model output.
 */
public final class LaboratoryAiPlannerEnvironmentStore {
    public static final int MAX_FILE_BYTES = 24 * 1024;

    public static final class Snapshot {
        public final String contractId;
        public final long capturedAtEpochMs;
        public final long updatedAtEpochMs;

        public final String modelFileName;
        public final long modelSizeBytes;
        public final String preflightStatus;
        public final boolean runtimePackaged;
        public final boolean androidLowMemory;
        public final long totalRamBytes;
        public final long availableRamBytes;
        public final long lowMemoryThresholdBytes;
        public final long appUsableStorageBytes;
        public final int cpuCores;
        public final List<String> signalCodes;

        public final int maxTokens;
        public final int contextTokens;
        public final int threads;
        public final int topK;
        public final float topP;
        public final long maxGenerationMs;

        public final String runtimeVersion;
        public final String modelDescription;

        private Snapshot(
                String contractId,
                long capturedAtEpochMs,
                long updatedAtEpochMs,
                String modelFileName,
                long modelSizeBytes,
                String preflightStatus,
                boolean runtimePackaged,
                boolean androidLowMemory,
                long totalRamBytes,
                long availableRamBytes,
                long lowMemoryThresholdBytes,
                long appUsableStorageBytes,
                int cpuCores,
                List<String> signalCodes,
                int maxTokens,
                int contextTokens,
                int threads,
                int topK,
                float topP,
                long maxGenerationMs,
                String runtimeVersion,
                String modelDescription) {
            this.contractId = contractId;
            this.capturedAtEpochMs = capturedAtEpochMs;
            this.updatedAtEpochMs = updatedAtEpochMs;
            this.modelFileName = modelFileName;
            this.modelSizeBytes = modelSizeBytes;
            this.preflightStatus = preflightStatus;
            this.runtimePackaged = runtimePackaged;
            this.androidLowMemory = androidLowMemory;
            this.totalRamBytes = totalRamBytes;
            this.availableRamBytes = availableRamBytes;
            this.lowMemoryThresholdBytes = lowMemoryThresholdBytes;
            this.appUsableStorageBytes = appUsableStorageBytes;
            this.cpuCores = cpuCores;
            this.signalCodes = Collections.unmodifiableList(
                new ArrayList<>(signalCodes));
            this.maxTokens = maxTokens;
            this.contextTokens = contextTokens;
            this.threads = threads;
            this.topK = topK;
            this.topP = topP;
            this.maxGenerationMs = maxGenerationMs;
            this.runtimeVersion = runtimeVersion;
            this.modelDescription = modelDescription;
        }
    }

    private final Path root;

    public LaboratoryAiPlannerEnvironmentStore(
            File appFilesDirectory,
            String projectId) {
        if (appFilesDirectory == null
                || projectId == null
                || (!projectId.isEmpty()
                    && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException(
                "invalid planner environment project");
        }

        Path appRoot = appFilesDirectory.toPath()
            .toAbsolutePath()
            .normalize();
        Path projectRoot = appRoot
            .resolve("laboratory")
            .resolve(projectId.isEmpty()
                ? "legacy"
                : "project-" + projectId);
        root = projectRoot.resolve("ai-planner-environment");
    }

    public synchronized void writePreflight(
            String contractId,
            LaboratoryAiLocalModelAdmission.AdmittedModel model,
            LaboratoryAiLocalModelPreflight.Report preflight,
            LaboratoryAiLlamaCppBackend.RuntimeConfig config)
            throws IOException {
        validateUuid(contractId);
        if (model == null || preflight == null || config == null) {
            throw new IOException(
                "planner environment preflight input missing");
        }

        long now = System.currentTimeMillis();
        Snapshot existing = read(contractId);
        long captured = existing == null
            ? now
            : existing.capturedAtEpochMs;

        write(new Snapshot(
            contractId,
            captured,
            now,
            model.fileName,
            model.sizeBytes,
            preflight.status,
            preflight.runtimePackaged,
            preflight.androidLowMemory,
            preflight.totalRamBytes,
            preflight.availableRamBytes,
            preflight.lowMemoryThresholdBytes,
            preflight.appUsableStorageBytes,
            preflight.cpuCores,
            preflight.signalCodes,
            config.maxTokens,
            config.contextTokens,
            config.threads,
            config.topK,
            config.topP,
            config.maxGenerationMs,
            existing == null ? "" : existing.runtimeVersion,
            existing == null ? "" : existing.modelDescription));
    }

    public synchronized void updateRuntimeMetadata(
            String contractId,
            String runtimeVersion,
            String modelDescription) throws IOException {
        Snapshot existing = read(contractId);
        if (existing == null) {
            throw new IOException(
                "planner environment preflight snapshot missing");
        }

        write(new Snapshot(
            existing.contractId,
            existing.capturedAtEpochMs,
            System.currentTimeMillis(),
            existing.modelFileName,
            existing.modelSizeBytes,
            existing.preflightStatus,
            existing.runtimePackaged,
            existing.androidLowMemory,
            existing.totalRamBytes,
            existing.availableRamBytes,
            existing.lowMemoryThresholdBytes,
            existing.appUsableStorageBytes,
            existing.cpuCores,
            existing.signalCodes,
            existing.maxTokens,
            existing.contextTokens,
            existing.threads,
            existing.topK,
            existing.topP,
            existing.maxGenerationMs,
            bounded(runtimeVersion, 160),
            bounded(modelDescription, 320)));
    }

    public synchronized Snapshot read(String contractId)
            throws IOException {
        validateUuid(contractId);
        Path target = target(contractId);
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            return null;
        }
        if (Files.isSymbolicLink(target)
                || !Files.isRegularFile(
                    target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(
                "unsafe planner environment entry");
        }
        long size = Files.size(target);
        if (size < 1L || size > MAX_FILE_BYTES) {
            throw new IOException(
                "planner environment has invalid size");
        }
        byte[] bytes = Files.readAllBytes(target);
        if (bytes.length != size || bytes.length > MAX_FILE_BYTES) {
            throw new IOException(
                "planner environment size changed");
        }
        return parse(
            contractId,
            new String(bytes, StandardCharsets.UTF_8));
    }

    private void write(Snapshot snapshot) throws IOException {
        prepareRoot();
        byte[] encoded = encode(snapshot)
            .toString()
            .getBytes(StandardCharsets.UTF_8);
        if (encoded.length < 1 || encoded.length > MAX_FILE_BYTES) {
            throw new IOException(
                "planner environment exceeds size limit");
        }

        Path target = target(snapshot.contractId);
        Path temp = root.resolve(
            snapshot.contractId + ".tmp-" + UUID.randomUUID())
            .normalize();
        if (!root.equals(temp.getParent())) {
            throw new IOException(
                "planner environment temp path escaped root");
        }

        boolean moved = false;
        try {
            Files.write(
                temp,
                encoded,
                StandardOpenOption.CREATE_NEW,
                StandardOpenOption.WRITE);
            try {
                Files.move(
                    temp,
                    target,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException ignored) {
                Files.move(
                    temp,
                    target,
                    StandardCopyOption.REPLACE_EXISTING);
            }
            moved = true;
        } finally {
            if (!moved) Files.deleteIfExists(temp);
        }
    }

    private JSONObject encode(Snapshot snapshot) throws IOException {
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("contractId", snapshot.contractId);
            json.put(
                "capturedAtEpochMs",
                snapshot.capturedAtEpochMs);
            json.put("updatedAtEpochMs", snapshot.updatedAtEpochMs);
            json.put("modelFileName", snapshot.modelFileName);
            json.put("modelSizeBytes", snapshot.modelSizeBytes);
            json.put("preflightStatus", snapshot.preflightStatus);
            json.put(
                "runtimePackaged",
                snapshot.runtimePackaged);
            json.put(
                "androidLowMemory",
                snapshot.androidLowMemory);
            json.put("totalRamBytes", snapshot.totalRamBytes);
            json.put(
                "availableRamBytes",
                snapshot.availableRamBytes);
            json.put(
                "lowMemoryThresholdBytes",
                snapshot.lowMemoryThresholdBytes);
            json.put(
                "appUsableStorageBytes",
                snapshot.appUsableStorageBytes);
            json.put("cpuCores", snapshot.cpuCores);
            JSONArray signals = new JSONArray();
            for (String code : snapshot.signalCodes) {
                signals.put(code);
            }
            json.put("signalCodes", signals);
            json.put("maxTokens", snapshot.maxTokens);
            json.put("contextTokens", snapshot.contextTokens);
            json.put("threads", snapshot.threads);
            json.put("topK", snapshot.topK);
            json.put("topP", snapshot.topP);
            json.put(
                "maxGenerationMs",
                snapshot.maxGenerationMs);
            json.put("runtimeVersion", snapshot.runtimeVersion);
            json.put(
                "modelDescription",
                snapshot.modelDescription);
            return json;
        } catch (JSONException error) {
            throw new IOException(
                "could not encode planner environment",
                error);
        }
    }

    private Snapshot parse(
            String expectedContractId,
            String raw) throws IOException {
        try {
            JSONObject json = new JSONObject(raw);
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException(
                    "unsupported planner environment schema");
            }

            String contractId = json.getString("contractId");
            validateUuid(contractId);
            if (!expectedContractId.equals(contractId)) {
                throw new IOException(
                    "planner environment contract mismatch");
            }

            long captured =
                json.getLong("capturedAtEpochMs");
            long updated =
                json.getLong("updatedAtEpochMs");
            String modelFileName =
                bounded(json.getString("modelFileName"), 160);
            long modelSizeBytes =
                json.getLong("modelSizeBytes");
            String preflightStatus =
                bounded(json.getString("preflightStatus"), 32);
            boolean runtimePackaged =
                json.getBoolean("runtimePackaged");
            boolean androidLowMemory =
                json.getBoolean("androidLowMemory");
            long totalRamBytes =
                json.getLong("totalRamBytes");
            long availableRamBytes =
                json.getLong("availableRamBytes");
            long lowMemoryThresholdBytes =
                json.getLong("lowMemoryThresholdBytes");
            long appUsableStorageBytes =
                json.getLong("appUsableStorageBytes");
            int cpuCores = json.getInt("cpuCores");
            List<String> signals = new ArrayList<>();
            JSONArray signalArray =
                json.optJSONArray("signalCodes");
            if (signalArray != null) {
                for (int i = 0; i < signalArray.length(); i++) {
                    signals.add(
                        bounded(signalArray.getString(i), 80));
                }
            }
            int maxTokens = json.getInt("maxTokens");
            int contextTokens =
                json.getInt("contextTokens");
            int threads = json.getInt("threads");
            int topK = json.getInt("topK");
            float topP = (float) json.getDouble("topP");
            long maxGenerationMs =
                json.getLong("maxGenerationMs");
            String runtimeVersion =
                bounded(json.optString("runtimeVersion"), 160);
            String modelDescription =
                bounded(json.optString("modelDescription"), 320);

            if (captured <= 0L
                    || updated < captured
                    || modelFileName.isEmpty()
                    || modelSizeBytes < 1L
                    || preflightStatus.isEmpty()
                    || totalRamBytes < 0L
                    || availableRamBytes < 0L
                    || lowMemoryThresholdBytes < 0L
                    || appUsableStorageBytes < 0L
                    || cpuCores < 1
                    || cpuCores > 512
                    || signals.size() > 32
                    || maxTokens < 1
                    || contextTokens < 256
                    || threads < 1
                    || topK < 0
                    || Float.isNaN(topP)
                    || topP <= 0.0f
                    || topP > 1.0f
                    || maxGenerationMs < 1_000L) {
                throw new IOException(
                    "invalid planner environment contents");
            }

            return new Snapshot(
                contractId,
                captured,
                updated,
                modelFileName,
                modelSizeBytes,
                preflightStatus,
                runtimePackaged,
                androidLowMemory,
                totalRamBytes,
                availableRamBytes,
                lowMemoryThresholdBytes,
                appUsableStorageBytes,
                cpuCores,
                signals,
                maxTokens,
                contextTokens,
                threads,
                topK,
                topP,
                maxGenerationMs,
                runtimeVersion,
                modelDescription);
        } catch (JSONException error) {
            throw new IOException(
                "could not parse planner environment",
                error);
        }
    }

    private Path target(String contractId) throws IOException {
        validateUuid(contractId);
        Path target = root.resolve(contractId + ".json").normalize();
        if (!root.equals(target.getParent())) {
            throw new IOException(
                "planner environment path escaped root");
        }
        return target;
    }

    private void prepareRoot() throws IOException {
        Files.createDirectories(root);
        if (Files.isSymbolicLink(root)
                || !Files.isDirectory(
                    root, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(
                "planner environment root is unsafe");
        }
    }

    private static void validateUuid(String value)
            throws IOException {
        if (value == null) {
            throw new IOException(
                "planner environment contract id missing");
        }
        try {
            if (!UUID.fromString(value).toString().equals(value)) {
                throw new IOException(
                    "invalid planner environment contract id");
            }
        } catch (IllegalArgumentException error) {
            throw new IOException(
                "invalid planner environment contract id",
                error);
        }
    }

    private static String bounded(String value, int max) {
        if (value == null) return "";
        String clean = value.trim();
        if (clean.length() <= max) return clean;
        return clean.substring(0, max);
    }
}
