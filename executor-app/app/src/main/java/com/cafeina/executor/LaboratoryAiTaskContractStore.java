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
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Create-only task contracts for future AI sessions.
 *
 * The exact user goal is intentionally persisted in app-private storage because
 * it is task state, not diagnostic logging, and must survive process death.
 * Session audit still stores hashes/state only.
 */
public final class LaboratoryAiTaskContractStore {
    public static final int MAX_CONTRACTS = 128;
    public static final int MAX_GOAL_CHARS = 4096;
    public static final int MAX_CONTRACT_BYTES = 32 * 1024;
    public static final int MAX_MARKER_BYTES = 8 * 1024;

    public enum Mode { CREATION, LEARNING }

    public static final class Contract {
        public final String contractId;
        public final long createdAtEpochMs;
        public final Mode mode;
        public final String goalText;
        public final String goalSha256;
        public final List<String> allowedToolIds;
        public final int maxInvocations;
        public final int maxTotalInputBytes;
        public final long maxSessionMs;
        public final String contractSha256;
        public final boolean claimed;
        public final boolean resultRecorded;

        private Contract(String contractId, long createdAtEpochMs, Mode mode,
                String goalText, String goalSha256, List<String> allowedToolIds,
                int maxInvocations, int maxTotalInputBytes, long maxSessionMs,
                String contractSha256, boolean claimed, boolean resultRecorded) {
            this.contractId = contractId;
            this.createdAtEpochMs = createdAtEpochMs;
            this.mode = mode;
            this.goalText = goalText;
            this.goalSha256 = goalSha256;
            this.allowedToolIds = Collections.unmodifiableList(
                new ArrayList<>(allowedToolIds));
            this.maxInvocations = maxInvocations;
            this.maxTotalInputBytes = maxTotalInputBytes;
            this.maxSessionMs = maxSessionMs;
            this.contractSha256 = contractSha256;
            this.claimed = claimed;
            this.resultRecorded = resultRecorded;
        }

        public LaboratoryAiSessionController.Policy policy() {
            return new LaboratoryAiSessionController.Policy(
                allowedToolIds, maxInvocations, maxTotalInputBytes, maxSessionMs);
        }
    }

    public static final class Claim {
        public final String claimId;
        public final String contractId;
        public final String contractSha256;
        public final long claimedAtEpochMs;

        private Claim(String claimId, String contractId,
                String contractSha256, long claimedAtEpochMs) {
            this.claimId = claimId;
            this.contractId = contractId;
            this.contractSha256 = contractSha256;
            this.claimedAtEpochMs = claimedAtEpochMs;
        }
    }

    public static final class Result {
        public final String contractId;
        public final String claimId;
        public final long recordedAtEpochMs;
        public final String status;
        public final String sessionId;
        public final String reason;

        private Result(String contractId, String claimId,
                long recordedAtEpochMs, String status,
                String sessionId, String reason) {
            this.contractId = contractId;
            this.claimId = claimId;
            this.recordedAtEpochMs = recordedAtEpochMs;
            this.status = status;
            this.sessionId = sessionId;
            this.reason = reason;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path contractRoot;

    public LaboratoryAiTaskContractStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI task contract project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        contractRoot = projectRoot.resolve("ai-task-contracts");
    }

    public synchronized Contract create(Mode mode, String goalText,
            LaboratoryAiSessionController.Policy policy) throws IOException {
        if (mode == null || policy == null) {
            throw new IllegalArgumentException("task mode or policy missing");
        }
        String goal = validateGoal(goalText);
        ensureRoot();
        if (countContracts() >= MAX_CONTRACTS) {
            throw new IOException("AI task contract limit reached; existing contracts preserved");
        }

        String contractId = UUID.randomUUID().toString();
        long created = System.currentTimeMillis();
        String goalSha = sha256(goal);
        String contractSha = contractSha(
            contractId, created, mode, goalSha, policy.allowedToolIds,
            policy.maxInvocations, policy.maxTotalInputBytes, policy.maxSessionMs);

        Path directory = contractRoot.resolve(contractId);
        if (Files.exists(directory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI task contract already exists");
        }

        boolean complete = false;
        try {
            Files.createDirectory(directory);
            ensureSafeDirectory(directory);
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("contractId", contractId);
            json.put("createdAtEpochMs", created);
            json.put("mode", mode.name());
            json.put("goalText", goal);
            json.put("goalSha256", goalSha);
            json.put("allowedToolIds", new JSONArray(policy.allowedToolIds));
            json.put("maxInvocations", policy.maxInvocations);
            json.put("maxTotalInputBytes", policy.maxTotalInputBytes);
            json.put("maxSessionMs", policy.maxSessionMs);
            json.put("contractSha256", contractSha);
            writeNew(directory.resolve("contract.json"), json, MAX_CONTRACT_BYTES);
            complete = true;
        } catch (JSONException error) {
            throw new IOException("could not encode AI task contract", error);
        } finally {
            if (!complete) {
                try {
                    Files.deleteIfExists(directory.resolve("contract.json"));
                    Files.deleteIfExists(directory);
                } catch (IOException ignored) {
                    // Preserve original creation failure.
                }
            }
        }
        return read(contractId);
    }

    public synchronized Contract read(String contractId) throws IOException {
        Path directory = requireContractDirectory(contractId);
        try {
            JSONObject json = new JSONObject(
                readSafe(directory.resolve("contract.json"), MAX_CONTRACT_BYTES));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI task contract version");
            }
            String id = json.getString("contractId");
            long created = json.getLong("createdAtEpochMs");
            Mode mode = Mode.valueOf(json.getString("mode"));
            String goal = validateGoal(json.getString("goalText"));
            String goalSha = json.getString("goalSha256");
            List<String> tools = strings(json.getJSONArray("allowedToolIds"));
            int maxInvocations = json.getInt("maxInvocations");
            int maxInput = json.getInt("maxTotalInputBytes");
            long maxMs = json.getLong("maxSessionMs");
            String storedContractSha = json.getString("contractSha256");

            LaboratoryAiSessionController.Policy policy =
                new LaboratoryAiSessionController.Policy(
                    tools, maxInvocations, maxInput, maxMs);
            String expectedGoalSha = sha256(goal);
            String expectedContractSha = contractSha(
                id, created, mode, expectedGoalSha, policy.allowedToolIds,
                policy.maxInvocations, policy.maxTotalInputBytes, policy.maxSessionMs);

            if (!contractId.equals(id) || created <= 0
                    || !validSha(goalSha) || !goalSha.equals(expectedGoalSha)
                    || !validSha(storedContractSha)
                    || !storedContractSha.equals(expectedContractSha)) {
                throw new IOException("AI task contract integrity failed");
            }

            return new Contract(
                id, created, mode, goal, goalSha, policy.allowedToolIds,
                policy.maxInvocations, policy.maxTotalInputBytes,
                policy.maxSessionMs, storedContractSha,
                Files.exists(directory.resolve("claim.json"), LinkOption.NOFOLLOW_LINKS),
                Files.exists(directory.resolve("result.json"), LinkOption.NOFOLLOW_LINKS));
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI task contract", error);
        }
    }

    public synchronized List<Contract> list() throws IOException {
        if (!Files.exists(contractRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Contract> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(contractRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_CONTRACTS) {
                throw new IOException("AI task contract vault exceeds limit");
            }
            for (Path path : paths) {
                if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)
                        || !validUuid(path.getFileName().toString())) {
                    throw new IOException("unexpected AI task contract entry");
                }
                result.add(read(path.getFileName().toString()));
            }
        }
        result.sort(Comparator
            .comparingLong((Contract contract) -> contract.createdAtEpochMs)
            .reversed()
            .thenComparing(contract -> contract.contractId));
        return Collections.unmodifiableList(result);
    }

    public synchronized Claim claim(String contractId) throws IOException {
        Contract contract = read(contractId);
        Path directory = requireContractDirectory(contractId);
        if (contract.claimed
                || Files.exists(directory.resolve("claim.json"), LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI task contract was already claimed");
        }

        String claimId = UUID.randomUUID().toString();
        long claimedAt = System.currentTimeMillis();
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("claimId", claimId);
            json.put("contractId", contract.contractId);
            json.put("contractSha256", contract.contractSha256);
            json.put("claimedAtEpochMs", claimedAt);
            json.put("claimSha256", claimSha(
                claimId, contract.contractId, contract.contractSha256, claimedAt));
            writeNew(directory.resolve("claim.json"), json, MAX_MARKER_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode AI task claim", error);
        }
        return readClaim(contractId);
    }

    public synchronized Claim readClaim(String contractId) throws IOException {
        Contract contract = read(contractId);
        Path path = requireContractDirectory(contractId).resolve("claim.json");
        try {
            JSONObject json = new JSONObject(readSafe(path, MAX_MARKER_BYTES));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI task claim version");
            }
            String claimId = json.getString("claimId");
            String id = json.getString("contractId");
            String contractSha = json.getString("contractSha256");
            long claimedAt = json.getLong("claimedAtEpochMs");
            String stored = json.getString("claimSha256");
            if (!validUuid(claimId) || !contractId.equals(id)
                    || !contract.contractSha256.equals(contractSha)
                    || claimedAt <= 0 || !validSha(stored)
                    || !stored.equals(claimSha(
                        claimId, id, contractSha, claimedAt))) {
                throw new IOException("AI task claim integrity failed");
            }
            return new Claim(claimId, id, contractSha, claimedAt);
        } catch (JSONException error) {
            throw new IOException("invalid AI task claim", error);
        }
    }

    public synchronized Result recordResult(String contractId, String claimId,
            String status, String sessionId, String reason) throws IOException {
        Contract contract = read(contractId);
        Claim claim = readClaim(contractId);
        if (!claim.claimId.equals(claimId)
                || !contract.contractSha256.equals(claim.contractSha256)) {
            throw new IOException("AI task claim does not match contract");
        }
        if (!("SESSION_CREATED".equals(status) || "SESSION_FAILED".equals(status))) {
            throw new IllegalArgumentException("invalid AI task result status");
        }
        String safeSession = sessionId == null ? "" : sessionId;
        String safeReason = reason == null ? "" : reason;
        if (safeReason.length() > 256
                || ("SESSION_CREATED".equals(status) && !validUuid(safeSession))
                || ("SESSION_FAILED".equals(status) && !safeSession.isEmpty())) {
            throw new IllegalArgumentException("invalid AI task result");
        }
        Path directory = requireContractDirectory(contractId);
        if (Files.exists(directory.resolve("result.json"), LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI task result already recorded");
        }

        long recordedAt = System.currentTimeMillis();
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("contractId", contractId);
            json.put("claimId", claimId);
            json.put("recordedAtEpochMs", recordedAt);
            json.put("status", status);
            json.put("sessionId", safeSession);
            json.put("reason", safeReason);
            json.put("resultSha256", resultSha(
                contractId, claimId, recordedAt, status, safeSession, safeReason));
            writeNew(directory.resolve("result.json"), json, MAX_MARKER_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode AI task result", error);
        }
        return readResult(contractId);
    }

    public synchronized Result readResult(String contractId) throws IOException {
        read(contractId);
        Claim claim = readClaim(contractId);
        Path path = requireContractDirectory(contractId).resolve("result.json");
        try {
            JSONObject json = new JSONObject(readSafe(path, MAX_MARKER_BYTES));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI task result version");
            }
            String id = json.getString("contractId");
            String claimId = json.getString("claimId");
            long recordedAt = json.getLong("recordedAtEpochMs");
            String status = json.getString("status");
            String sessionId = json.optString("sessionId");
            String reason = json.optString("reason");
            String stored = json.getString("resultSha256");
            if (!contractId.equals(id) || !claim.claimId.equals(claimId)
                    || recordedAt <= 0
                    || !("SESSION_CREATED".equals(status)
                        || "SESSION_FAILED".equals(status))
                    || ("SESSION_CREATED".equals(status) && !validUuid(sessionId))
                    || ("SESSION_FAILED".equals(status) && !sessionId.isEmpty())
                    || reason.length() > 256 || !validSha(stored)
                    || !stored.equals(resultSha(
                        id, claimId, recordedAt, status, sessionId, reason))) {
                throw new IOException("AI task result integrity failed");
            }
            return new Result(id, claimId, recordedAt, status, sessionId, reason);
        } catch (JSONException error) {
            throw new IOException("invalid AI task result", error);
        }
    }

    private Path requireContractDirectory(String contractId) throws IOException {
        if (!validUuid(contractId)) {
            throw new IllegalArgumentException("invalid AI task contract id");
        }
        ensureRoot();
        Path directory = contractRoot.resolve(contractId);
        if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(directory)) {
            throw new IOException("AI task contract not found or unsafe");
        }
        return directory;
    }

    private void ensureRoot() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(contractRoot);
    }

    private int countContracts() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(contractRoot)) {
            return (int) stream
                .filter(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS))
                .limit(MAX_CONTRACTS + 1L).count();
        }
    }

    private static String validateGoal(String goalText) {
        if (goalText == null) throw new IllegalArgumentException("task goal missing");
        if (goalText.trim().isEmpty() || goalText.length() > MAX_GOAL_CHARS) {
            throw new IllegalArgumentException("task goal is empty or too large");
        }
        return goalText;
    }

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            String value = array.getString(i);
            if (value == null
                    || !value.matches("[a-z0-9][a-z0-9._-]{0,63}")
                    || values.contains(value)) {
                throw new JSONException("invalid task tool list");
            }
            values.add(value);
        }
        return values;
    }

    private static String contractSha(String contractId, long created,
            Mode mode, String goalSha, List<String> tools,
            int maxInvocations, int maxInput, long maxMs) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, contractId);
        field(canonical, Long.toString(created));
        field(canonical, mode.name());
        field(canonical, goalSha);
        list(canonical, tools);
        field(canonical, Integer.toString(maxInvocations));
        field(canonical, Integer.toString(maxInput));
        field(canonical, Long.toString(maxMs));
        return sha256(canonical.toString());
    }

    private static String claimSha(String claimId, String contractId,
            String contractSha, long claimedAt) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, claimId);
        field(canonical, contractId);
        field(canonical, contractSha);
        field(canonical, Long.toString(claimedAt));
        return sha256(canonical.toString());
    }

    private static String resultSha(String contractId, String claimId,
            long recordedAt, String status, String sessionId, String reason) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, contractId);
        field(canonical, claimId);
        field(canonical, Long.toString(recordedAt));
        field(canonical, status);
        field(canonical, sessionId);
        field(canonical, reason);
        return sha256(canonical.toString());
    }

    private static void field(StringBuilder out, String value) {
        String safe = value == null ? "" : value;
        out.append(safe.length()).append(':').append(safe);
    }

    private static void list(StringBuilder out, List<String> values) {
        out.append(values.size()).append('[');
        for (String value : values) field(out, value);
        out.append(']');
    }

    private static void writeNew(Path destination, JSONObject json, int maxBytes)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI task contract record already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > maxBytes) {
            throw new IOException("AI task contract record exceeds size budget");
        }
        Path temporary = destination.getParent().resolve(
            "." + destination.getFileName() + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("AI task contract record already exists");
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

    private static String readSafe(Path path, int maxBytes) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > maxBytes) {
            throw new IOException("AI task contract record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
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
            throw new IOException("unsafe AI task contract directory");
        }
    }

    private static boolean validUuid(String value) {
        try {
            return value != null && UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static boolean validSha(String value) {
        return value != null && value.matches("[0-9a-f]{64}");
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) {
                out.append(String.format(Locale.ROOT, "%02x", b & 0xff));
            }
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
