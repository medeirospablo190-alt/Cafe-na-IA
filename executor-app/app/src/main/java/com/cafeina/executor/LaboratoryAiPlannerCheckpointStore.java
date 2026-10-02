package com.cafeina.executor;

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
import java.util.UUID;

/**
 * Small overwrite-only crash checkpoint for the active local planner.
 *
 * It stores execution metadata only: no Goal Lock text, prompt, model output,
 * tool input, stdout or executable source. Terminal history remains owned by
 * LaboratoryAiExecutionHistoryStore.
 */
public final class LaboratoryAiPlannerCheckpointStore {
    public static final int MAX_FILE_BYTES = 12 * 1024;

    public static final class Checkpoint {
        public final String executionId;
        public final String contractId;
        public final long startedAtEpochMs;
        public final long updatedAtEpochMs;
        public final long elapsedMs;
        public final LaboratoryAiExecutionStatus.State state;
        public final LaboratoryAiExecutionStatus.Phase phase;
        public final String detail;
        public final int attempt;
        public final int maxAttempts;
        public final int promptTokens;
        public final int promptTokensProcessed;
        public final int generatedTokens;
        public final int maxGeneratedTokens;
        public final long contextSetupMs;
        public final long promptEvalMs;
        public final long tokenGenerationMs;
        public final long generationTimeLimitMs;
        public final long estimatedRemainingMs;

        private Checkpoint(
                String executionId,
                String contractId,
                long startedAtEpochMs,
                long updatedAtEpochMs,
                LaboratoryAiExecutionStatus.State state,
                LaboratoryAiExecutionStatus.Phase phase,
                String detail,
                int attempt,
                int maxAttempts,
                int promptTokens,
                int promptTokensProcessed,
                int generatedTokens,
                int maxGeneratedTokens,
                long contextSetupMs,
                long promptEvalMs,
                long tokenGenerationMs,
                long generationTimeLimitMs,
                long estimatedRemainingMs) {
            this.executionId = executionId;
            this.contractId = contractId;
            this.startedAtEpochMs = startedAtEpochMs;
            this.updatedAtEpochMs = updatedAtEpochMs;
            this.elapsedMs =
                Math.max(0L, updatedAtEpochMs - startedAtEpochMs);
            this.state = state;
            this.phase = phase;
            this.detail = detail;
            this.attempt = attempt;
            this.maxAttempts = maxAttempts;
            this.promptTokens = promptTokens;
            this.promptTokensProcessed = promptTokensProcessed;
            this.generatedTokens = generatedTokens;
            this.maxGeneratedTokens = maxGeneratedTokens;
            this.contextSetupMs = contextSetupMs;
            this.promptEvalMs = promptEvalMs;
            this.tokenGenerationMs = tokenGenerationMs;
            this.generationTimeLimitMs = generationTimeLimitMs;
            this.estimatedRemainingMs = estimatedRemainingMs;
        }
    }

    private final Path root;

    public LaboratoryAiPlannerCheckpointStore(
            File appFilesDirectory,
            String projectId) {
        if (appFilesDirectory == null
                || projectId == null
                || (!projectId.isEmpty()
                    && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException(
                "invalid planner checkpoint project");
        }

        Path appRoot = appFilesDirectory.toPath()
            .toAbsolutePath()
            .normalize();
        Path laboratoryRoot = appRoot.resolve("laboratory");
        Path projectRoot = laboratoryRoot.resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-planner-checkpoints");
    }

    public synchronized void write(
            LaboratoryAiExecutionStatus.Snapshot snapshot)
            throws IOException {
        validateSnapshot(snapshot);
        if (snapshot.terminal()) {
            throw new IOException(
                "terminal planner state does not belong in live checkpoint");
        }
        prepareRoot();

        byte[] encoded = encode(snapshot)
            .toString()
            .getBytes(StandardCharsets.UTF_8);
        if (encoded.length < 1 || encoded.length > MAX_FILE_BYTES) {
            throw new IOException("planner checkpoint exceeds size limit");
        }

        Path target = target(snapshot.contractId);
        Path temp = root.resolve(
            snapshot.contractId + ".tmp-" + UUID.randomUUID()).normalize();
        if (!root.equals(temp.getParent())) {
            throw new IOException("planner checkpoint temp path escaped root");
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
            if (!moved) {
                Files.deleteIfExists(temp);
            }
        }
    }

    public synchronized Checkpoint read(String contractId)
            throws IOException {
        validateUuid(contractId, "contract");
        Path target = target(contractId);
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            return null;
        }
        if (Files.isSymbolicLink(target)
                || !Files.isRegularFile(
                    target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("unsafe planner checkpoint entry");
        }

        long size = Files.size(target);
        if (size < 1L || size > MAX_FILE_BYTES) {
            throw new IOException("planner checkpoint has invalid size");
        }
        byte[] bytes = Files.readAllBytes(target);
        if (bytes.length != size || bytes.length > MAX_FILE_BYTES) {
            throw new IOException("planner checkpoint size changed");
        }
        return parse(
            contractId,
            new String(bytes, StandardCharsets.UTF_8));
    }

    public synchronized void clear(String contractId)
            throws IOException {
        validateUuid(contractId, "contract");
        Path target = target(contractId);
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)
                && (Files.isSymbolicLink(target)
                    || !Files.isRegularFile(
                        target, LinkOption.NOFOLLOW_LINKS))) {
            throw new IOException("unsafe planner checkpoint entry");
        }
        Files.deleteIfExists(target);
    }

    private JSONObject encode(
            LaboratoryAiExecutionStatus.Snapshot snapshot)
            throws IOException {
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("executionId", snapshot.executionId);
            json.put("contractId", snapshot.contractId);
            json.put("startedAtEpochMs", snapshot.startedAtEpochMs);
            json.put("updatedAtEpochMs", snapshot.updatedAtEpochMs);
            json.put("state", snapshot.state.name());
            json.put("phase", snapshot.phase.name());
            json.put("detail", snapshot.detail);
            json.put("attempt", snapshot.attempt);
            json.put("maxAttempts", snapshot.maxAttempts);
            json.put("promptTokens", snapshot.promptTokens);
            json.put(
                "promptTokensProcessed",
                snapshot.promptTokensProcessed);
            json.put("generatedTokens", snapshot.generatedTokens);
            json.put(
                "maxGeneratedTokens",
                snapshot.maxGeneratedTokens);
            json.put("contextSetupMs", snapshot.contextSetupMs);
            json.put("promptEvalMs", snapshot.promptEvalMs);
            json.put(
                "tokenGenerationMs",
                snapshot.tokenGenerationMs);
            json.put(
                "generationTimeLimitMs",
                snapshot.generationTimeLimitMs);
            json.put(
                "estimatedRemainingMs",
                snapshot.estimatedRemainingMs);
            return json;
        } catch (JSONException error) {
            throw new IOException(
                "could not encode planner checkpoint",
                error);
        }
    }

    private Checkpoint parse(
            String expectedContractId,
            String raw) throws IOException {
        try {
            JSONObject json = new JSONObject(raw);
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException(
                    "unsupported planner checkpoint schema");
            }

            String executionId = json.getString("executionId");
            String contractId = json.getString("contractId");
            long started = json.getLong("startedAtEpochMs");
            long updated = json.getLong("updatedAtEpochMs");
            LaboratoryAiExecutionStatus.State state =
                LaboratoryAiExecutionStatus.State.valueOf(
                    json.getString("state"));
            LaboratoryAiExecutionStatus.Phase phase =
                LaboratoryAiExecutionStatus.Phase.valueOf(
                    json.getString("phase"));
            String detail = json.optString("detail");
            int attempt = json.optInt("attempt", 0);
            int maxAttempts = json.optInt("maxAttempts", 0);
            int promptTokens = json.optInt("promptTokens", 0);
            int promptTokensProcessed =
                json.optInt("promptTokensProcessed", 0);
            int generatedTokens =
                json.optInt("generatedTokens", 0);
            int maxGeneratedTokens =
                json.optInt("maxGeneratedTokens", 0);
            long contextSetupMs =
                json.optLong("contextSetupMs", 0L);
            long promptEvalMs =
                json.optLong("promptEvalMs", 0L);
            long tokenGenerationMs =
                json.optLong("tokenGenerationMs", 0L);
            long generationTimeLimitMs =
                json.optLong("generationTimeLimitMs", 0L);
            long estimatedRemainingMs =
                json.optLong("estimatedRemainingMs", 0L);

            validateUuid(executionId, "execution");
            validateUuid(contractId, "contract");
            if (!expectedContractId.equals(contractId)
                    || started <= 0L
                    || updated < started
                    || state
                        != LaboratoryAiExecutionStatus.State.RUNNING
                    || phase
                        == LaboratoryAiExecutionStatus.Phase.COMPLETED
                    || detail.length() > 240
                    || attempt < 0
                    || maxAttempts < 0
                    || attempt > maxAttempts
                    || (attempt > 0 && maxAttempts == 0)
                    || promptTokens < 0
                    || promptTokensProcessed < 0
                    || promptTokensProcessed > promptTokens
                    || generatedTokens < 0
                    || maxGeneratedTokens < 0
                    || generatedTokens > maxGeneratedTokens
                    || contextSetupMs < 0L
                    || promptEvalMs < 0L
                    || tokenGenerationMs < 0L
                    || generationTimeLimitMs < 0L
                    || estimatedRemainingMs < 0L) {
                throw new IOException(
                    "invalid planner checkpoint contents");
            }

            return new Checkpoint(
                executionId,
                contractId,
                started,
                updated,
                state,
                phase,
                detail,
                attempt,
                maxAttempts,
                promptTokens,
                promptTokensProcessed,
                generatedTokens,
                maxGeneratedTokens,
                contextSetupMs,
                promptEvalMs,
                tokenGenerationMs,
                generationTimeLimitMs,
                estimatedRemainingMs);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException(
                "could not parse planner checkpoint",
                error);
        }
    }

    private Path target(String contractId) throws IOException {
        validateUuid(contractId, "contract");
        Path target = root.resolve(contractId + ".json").normalize();
        if (!root.equals(target.getParent())) {
            throw new IOException(
                "planner checkpoint path escaped root");
        }
        return target;
    }

    private void prepareRoot() throws IOException {
        Files.createDirectories(root);
        if (Files.isSymbolicLink(root)
                || !Files.isDirectory(
                    root, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(
                "planner checkpoint root is unsafe");
        }
    }

    private static void validateSnapshot(
            LaboratoryAiExecutionStatus.Snapshot snapshot)
            throws IOException {
        if (snapshot == null) {
            throw new IOException("planner checkpoint snapshot missing");
        }
        validateUuid(snapshot.executionId, "execution");
        validateUuid(snapshot.contractId, "contract");
        if (snapshot.startedAtEpochMs <= 0L
                || snapshot.updatedAtEpochMs
                    < snapshot.startedAtEpochMs
                || snapshot.detail == null
                || snapshot.detail.length() > 240
                || snapshot.attempt < 0
                || snapshot.maxAttempts < 0
                || snapshot.attempt > snapshot.maxAttempts
                || (snapshot.attempt > 0
                    && snapshot.maxAttempts == 0)
                || snapshot.promptTokens < 0
                || snapshot.promptTokensProcessed < 0
                || snapshot.promptTokensProcessed
                    > snapshot.promptTokens
                || snapshot.generatedTokens < 0
                || snapshot.maxGeneratedTokens < 0
                || snapshot.generatedTokens
                    > snapshot.maxGeneratedTokens
                || snapshot.contextSetupMs < 0L
                || snapshot.promptEvalMs < 0L
                || snapshot.tokenGenerationMs < 0L
                || snapshot.generationTimeLimitMs < 0L
                || snapshot.estimatedRemainingMs < 0L) {
            throw new IOException(
                "invalid planner checkpoint snapshot");
        }
    }

    private static void validateUuid(
            String value,
            String label) throws IOException {
        if (value == null) {
            throw new IOException(
                "planner checkpoint " + label + " id missing");
        }
        try {
            if (!UUID.fromString(value).toString().equals(value)) {
                throw new IOException(
                    "invalid planner checkpoint " + label + " id");
            }
        } catch (IllegalArgumentException error) {
            throw new IOException(
                "invalid planner checkpoint " + label + " id",
                error);
        }
    }
}
