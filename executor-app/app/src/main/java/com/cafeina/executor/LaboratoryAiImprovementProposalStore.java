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
 * Create-only, deduplicated improvement proposals produced from sanitized team
 * diagnostics. Proposals never apply changes.
 */
public final class LaboratoryAiImprovementProposalStore {
    public static final int MAX_PROPOSALS = 128;
    public static final int MAX_RECORD_BYTES = 20 * 1024;

    public static final class Proposal {
        public final String proposalId;
        public final String proposalKeySha256;
        public final String agentId;
        public final String agentRole;
        public final String sourceRecommendationCode;
        public final String suggestedActionCode;
        public final String targetRole;
        public final String sourceTrend;
        public final int sourceSessionCount;
        public final int sourceFailureSessions;
        public final int sourceFailedInvocations;
        public final long createdAtEpochMs;
        public final String recordSha256;

        private Proposal(String proposalId, String proposalKeySha256,
                String agentId, String agentRole,
                String sourceRecommendationCode,
                String suggestedActionCode, String targetRole,
                String sourceTrend, int sourceSessionCount,
                int sourceFailureSessions, int sourceFailedInvocations,
                long createdAtEpochMs, String recordSha256) {
            this.proposalId = proposalId;
            this.proposalKeySha256 = proposalKeySha256;
            this.agentId = agentId;
            this.agentRole = agentRole;
            this.sourceRecommendationCode = sourceRecommendationCode;
            this.suggestedActionCode = suggestedActionCode;
            this.targetRole = targetRole;
            this.sourceTrend = sourceTrend;
            this.sourceSessionCount = sourceSessionCount;
            this.sourceFailureSessions = sourceFailureSessions;
            this.sourceFailedInvocations = sourceFailedInvocations;
            this.createdAtEpochMs = createdAtEpochMs;
            this.recordSha256 = recordSha256;
        }
    }

    private final Path root;

    public LaboratoryAiImprovementProposalStore(
            File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException(
                "invalid AI improvement proposal project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path projectRoot = appRoot.resolve("laboratory").resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-improvement-proposals");
    }

    public synchronized Proposal createIfAbsent(
            LaboratoryAiTeamDiagnosticStore.Report source,
            String recommendationCode,
            String suggestedActionCode,
            String targetRole) throws IOException {
        if (source == null) {
            throw new IllegalArgumentException("proposal source missing");
        }
        validateCode(recommendationCode);
        validateCode(suggestedActionCode);
        validateRole(targetRole);
        ensureRoot();

        String key = proposalKey(
            source.agentId,
            recommendationCode,
            suggestedActionCode,
            targetRole,
            source.trend,
            source.sessionCount,
            source.failureSessions,
            source.failedInvocations,
            source.recurrentSignals);

        for (Proposal existing : list()) {
            if (existing.proposalKeySha256.equals(key)) {
                return existing;
            }
        }
        if (countReports() >= MAX_PROPOSALS) {
            throw new IOException(
                "AI improvement proposal limit reached; history preserved");
        }

        String proposalId = UUID.randomUUID().toString();
        long created = System.currentTimeMillis();
        String recordSha = recordSha(
            proposalId, key, source.agentId, source.role,
            recommendationCode, suggestedActionCode, targetRole,
            source.trend, source.sessionCount,
            source.failureSessions, source.failedInvocations, created);

        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("proposalId", proposalId);
            json.put("proposalKeySha256", key);
            json.put("agentId", source.agentId);
            json.put("agentRole", source.role);
            json.put("sourceRecommendationCode", recommendationCode);
            json.put("suggestedActionCode", suggestedActionCode);
            json.put("targetRole", targetRole);
            json.put("sourceTrend", source.trend);
            json.put("sourceSessionCount", source.sessionCount);
            json.put("sourceFailureSessions", source.failureSessions);
            json.put("sourceFailedInvocations", source.failedInvocations);
            json.put("createdAtEpochMs", created);
            json.put("recordSha256", recordSha);
            writeNew(root.resolve(proposalId + ".json"), json);
        } catch (JSONException error) {
            throw new IOException("could not encode AI improvement proposal", error);
        }
        return read(proposalId);
    }

    public synchronized Proposal read(String proposalId) throws IOException {
        validateUuid(proposalId);
        ensureRoot();
        Path path = root.resolve(proposalId + ".json");
        try {
            JSONObject json = new JSONObject(readSafe(path));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI improvement proposal schema");
            }
            Proposal proposal = new Proposal(
                json.getString("proposalId"),
                json.getString("proposalKeySha256"),
                json.getString("agentId"),
                json.getString("agentRole"),
                json.getString("sourceRecommendationCode"),
                json.getString("suggestedActionCode"),
                json.getString("targetRole"),
                json.getString("sourceTrend"),
                json.getInt("sourceSessionCount"),
                json.getInt("sourceFailureSessions"),
                json.getInt("sourceFailedInvocations"),
                json.getLong("createdAtEpochMs"),
                json.getString("recordSha256"));
            validate(proposal);
            if (!proposalId.equals(proposal.proposalId)) {
                throw new IOException("AI improvement proposal identity mismatch");
            }
            String expected = recordSha(
                proposal.proposalId,
                proposal.proposalKeySha256,
                proposal.agentId,
                proposal.agentRole,
                proposal.sourceRecommendationCode,
                proposal.suggestedActionCode,
                proposal.targetRole,
                proposal.sourceTrend,
                proposal.sourceSessionCount,
                proposal.sourceFailureSessions,
                proposal.sourceFailedInvocations,
                proposal.createdAtEpochMs);
            if (!proposal.recordSha256.equals(expected)) {
                throw new IOException("AI improvement proposal integrity failed");
            }
            return proposal;
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI improvement proposal", error);
        }
    }

    public synchronized List<Proposal> list() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Proposal> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_PROPOSALS) {
                throw new IOException("AI improvement proposal history exceeds limit");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.matches("[0-9a-f-]{36}\\.json")
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected AI improvement proposal entry");
                }
                result.add(read(name.substring(0, name.length() - 5)));
            }
        }
        result.sort(Comparator
            .comparingLong((Proposal proposal) -> proposal.createdAtEpochMs)
            .reversed()
            .thenComparing(proposal -> proposal.proposalId));
        return Collections.unmodifiableList(result);
    }

    private static void validate(Proposal proposal) {
        validateUuid(proposal.proposalId);
        if (!validSha(proposal.proposalKeySha256)
                || proposal.agentId == null
                || !proposal.agentId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                || !validRole(proposal.agentRole)
                || !validRole(proposal.targetRole)
                || !validTrend(proposal.sourceTrend)
                || proposal.sourceSessionCount < 0
                || proposal.sourceFailureSessions < 0
                || proposal.sourceFailedInvocations < 0
                || proposal.sourceFailureSessions > proposal.sourceSessionCount
                || proposal.createdAtEpochMs <= 0
                || !validSha(proposal.recordSha256)) {
            throw new IllegalArgumentException("invalid AI improvement proposal");
        }
        validateCode(proposal.sourceRecommendationCode);
        validateCode(proposal.suggestedActionCode);
    }

    private void ensureRoot() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            Path parent = root.getParent();
            if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(parent)) {
                throw new IOException(
                    "AI improvement proposal parent missing or unsafe");
            }
            try {
                Files.createDirectory(root);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(root)) {
            throw new IOException("unsafe AI improvement proposal directory");
        }
    }

    private int countReports() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            return (int) stream
                .filter(path -> path.getFileName().toString().endsWith(".json"))
                .limit(MAX_PROPOSALS + 1L).count();
        }
    }

    private String readSafe(Path path) throws IOException {
        if (!root.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException(
                "AI improvement proposal missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI improvement proposal already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("AI improvement proposal exceeds size limit");
        }
        Path temporary = destination.getParent().resolve(
            "." + destination.getFileName() + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(
                    temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
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

    private static String proposalKey(String agentId, String recommendation,
            String action, String targetRole, String trend,
            int sessions, int failureSessions, int failedInvocations,
            List<String> recurrentSignals) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, agentId);
        field(canonical, recommendation);
        field(canonical, action);
        field(canonical, targetRole);
        field(canonical, trend);
        field(canonical, Integer.toString(sessions));
        field(canonical, Integer.toString(failureSessions));
        field(canonical, Integer.toString(failedInvocations));
        list(canonical, recurrentSignals);
        return sha256(canonical.toString());
    }

    private static String recordSha(String proposalId, String key,
            String agentId, String agentRole, String recommendation,
            String action, String targetRole, String trend,
            int sessions, int failureSessions, int failedInvocations,
            long created) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, proposalId);
        field(canonical, key);
        field(canonical, agentId);
        field(canonical, agentRole);
        field(canonical, recommendation);
        field(canonical, action);
        field(canonical, targetRole);
        field(canonical, trend);
        field(canonical, Integer.toString(sessions));
        field(canonical, Integer.toString(failureSessions));
        field(canonical, Integer.toString(failedInvocations));
        field(canonical, Long.toString(created));
        return sha256(canonical.toString());
    }

    private static void validateCode(String value) {
        if (value == null || !value.matches("[A-Z0-9_]{1,64}")) {
            throw new IllegalArgumentException("invalid proposal code");
        }
    }

    private static boolean validRole(String role) {
        return LaboratoryAiTeamRegistry.ROLE_TESTER.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_CREATOR.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_REVIEWER.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_RESEARCHER.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_ORCHESTRATOR.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_SPECIALIST.equals(role);
    }

    private static boolean validTrend(String trend) {
        return "INSUFFICIENT_DATA".equals(trend)
            || "STABLE".equals(trend)
            || "IMPROVING".equals(trend)
            || "DEGRADING".equals(trend);
    }

    private static void validateUuid(String value) {
        try {
            if (value == null
                    || !UUID.fromString(value).toString().equals(value)) {
                throw new IllegalArgumentException("invalid proposal id");
            }
        } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException("invalid proposal id", error);
        }
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
