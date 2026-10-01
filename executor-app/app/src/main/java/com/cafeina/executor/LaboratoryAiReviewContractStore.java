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
 * One-use review authorization derived from a user-routed improvement proposal.
 *
 * This authorizes analysis only. It does not create a session, expose tools or
 * grant permission to apply a change.
 */
public final class LaboratoryAiReviewContractStore {
    public static final int MAX_CONTRACTS = 128;
    public static final int MAX_RECORD_BYTES = 16 * 1024;

    public static final class Contract {
        public final String reviewContractId;
        public final String proposalId;
        public final String proposalKeySha256;
        public final String targetRole;
        public final String sourceRecommendationCode;
        public final String suggestedActionCode;
        public final long createdAtEpochMs;
        public final String contractSha256;
        public final boolean claimed;

        private Contract(String reviewContractId, String proposalId,
                String proposalKeySha256, String targetRole,
                String sourceRecommendationCode, String suggestedActionCode,
                long createdAtEpochMs, String contractSha256,
                boolean claimed) {
            this.reviewContractId = reviewContractId;
            this.proposalId = proposalId;
            this.proposalKeySha256 = proposalKeySha256;
            this.targetRole = targetRole;
            this.sourceRecommendationCode = sourceRecommendationCode;
            this.suggestedActionCode = suggestedActionCode;
            this.createdAtEpochMs = createdAtEpochMs;
            this.contractSha256 = contractSha256;
            this.claimed = claimed;
        }
    }

    public static final class Claim {
        public final String claimId;
        public final String reviewContractId;
        public final String contractSha256;
        public final String reviewerAgentId;
        public final String reviewerRole;
        public final long claimedAtEpochMs;
        public final String recordSha256;

        private Claim(String claimId, String reviewContractId,
                String contractSha256, String reviewerAgentId,
                String reviewerRole, long claimedAtEpochMs,
                String recordSha256) {
            this.claimId = claimId;
            this.reviewContractId = reviewContractId;
            this.contractSha256 = contractSha256;
            this.reviewerAgentId = reviewerAgentId;
            this.reviewerRole = reviewerRole;
            this.claimedAtEpochMs = claimedAtEpochMs;
            this.recordSha256 = recordSha256;
        }
    }

    private static final Object WRITE_LOCK = new Object();

    private final File appFilesDirectory;
    private final String projectId;
    private final Path root;

    public LaboratoryAiReviewContractStore(
            File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI review contract project");
        }
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path projectRoot = appRoot.resolve("laboratory").resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-review-contracts");
    }

    public Contract createForRoutedProposal(String proposalId)
            throws IOException {
        synchronized (WRITE_LOCK) {
            LaboratoryAiReviewInbox.Item item =
                new LaboratoryAiReviewInbox(
                    appFilesDirectory, projectId).readRouted(proposalId);
            LaboratoryAiImprovementProposalStore.Proposal proposal =
                new LaboratoryAiImprovementProposalStore(
                    appFilesDirectory, projectId).read(proposalId);

            ensureRoot();
            if (countContracts() >= MAX_CONTRACTS) {
                throw new IOException("AI review contract limit reached");
            }

            String reviewContractId = UUID.randomUUID().toString();
            long created = System.currentTimeMillis();
            String contractSha = contractSha(
                reviewContractId,
                proposal.proposalId,
                proposal.proposalKeySha256,
                item.targetRole,
                item.sourceRecommendationCode,
                item.suggestedActionCode,
                created);

            Path directory = root.resolve(reviewContractId);
            Files.createDirectory(directory);
            ensureSafeDirectory(directory);

            try {
                JSONObject json = new JSONObject();
                json.put("schemaVersion", 1);
                json.put("reviewContractId", reviewContractId);
                json.put("proposalId", proposal.proposalId);
                json.put("proposalKeySha256", proposal.proposalKeySha256);
                json.put("targetRole", item.targetRole);
                json.put("sourceRecommendationCode",
                    item.sourceRecommendationCode);
                json.put("suggestedActionCode", item.suggestedActionCode);
                json.put("createdAtEpochMs", created);
                json.put("contractSha256", contractSha);
                writeNew(directory.resolve("contract.json"), json);
            } catch (JSONException error) {
                throw new IOException(
                    "could not encode AI review contract", error);
            }
            return read(reviewContractId);
        }
    }

    public Contract read(String reviewContractId) throws IOException {
        validateUuid(reviewContractId);
        ensureRoot();
        Path directory = requireDirectory(reviewContractId);
        try {
            JSONObject json = new JSONObject(
                readSafe(directory.resolve("contract.json"), directory));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI review contract schema");
            }

            String id = json.getString("reviewContractId");
            String proposalId = json.getString("proposalId");
            String proposalKey = json.getString("proposalKeySha256");
            String targetRole = json.getString("targetRole");
            String recommendation = json.getString("sourceRecommendationCode");
            String action = json.getString("suggestedActionCode");
            long created = json.getLong("createdAtEpochMs");
            String stored = json.getString("contractSha256");

            validateUuid(id);
            validateUuid(proposalId);
            validateRole(targetRole);
            validateCode(recommendation);
            validateCode(action);

            LaboratoryAiImprovementProposalStore.Proposal proposal =
                new LaboratoryAiImprovementProposalStore(
                    appFilesDirectory, projectId).read(proposalId);

            String expected = contractSha(
                id, proposalId, proposalKey, targetRole,
                recommendation, action, created);
            if (!reviewContractId.equals(id)
                    || !validSha(proposalKey)
                    || !proposal.proposalKeySha256.equals(proposalKey)
                    || !proposal.targetRole.equals(targetRole)
                    || !proposal.sourceRecommendationCode.equals(recommendation)
                    || !proposal.suggestedActionCode.equals(action)
                    || created <= 0
                    || !validSha(stored)
                    || !stored.equals(expected)) {
                throw new IOException("AI review contract integrity failed");
            }

            return new Contract(
                id, proposalId, proposalKey, targetRole,
                recommendation, action, created, stored,
                Files.exists(directory.resolve("claim.json"),
                    LinkOption.NOFOLLOW_LINKS));
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI review contract", error);
        }
    }

    public Claim claim(String reviewContractId, String reviewerAgentId)
            throws IOException {
        synchronized (WRITE_LOCK) {
            Contract contract = read(reviewContractId);

            // Authorization may have been withdrawn after contract creation.
            LaboratoryAiReviewInbox.Item current =
                new LaboratoryAiReviewInbox(
                    appFilesDirectory, projectId).readRouted(
                        contract.proposalId);
            if (!contract.proposalKeySha256.equals(
                        new LaboratoryAiImprovementProposalStore(
                            appFilesDirectory, projectId)
                            .read(contract.proposalId).proposalKeySha256)
                    || !contract.targetRole.equals(current.targetRole)) {
                throw new IOException("AI review authorization changed");
            }

            LaboratoryAiTeamRegistry.Member reviewer =
                new LaboratoryAiTeamRegistry(
                    appFilesDirectory, projectId).readMember(reviewerAgentId);
            if (!contract.targetRole.equals(reviewer.role)) {
                throw new IOException(
                    "AI reviewer role does not match routed target role");
            }

            Path directory = requireDirectory(reviewContractId);
            Path claimPath = directory.resolve("claim.json");
            if (contract.claimed
                    || Files.exists(claimPath, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("AI review contract was already claimed");
            }

            String claimId = UUID.randomUUID().toString();
            long claimed = System.currentTimeMillis();
            String hash = claimSha(
                claimId,
                contract.reviewContractId,
                contract.contractSha256,
                reviewer.agentId,
                reviewer.role,
                claimed);

            try {
                JSONObject json = new JSONObject();
                json.put("schemaVersion", 1);
                json.put("claimId", claimId);
                json.put("reviewContractId", contract.reviewContractId);
                json.put("contractSha256", contract.contractSha256);
                json.put("reviewerAgentId", reviewer.agentId);
                json.put("reviewerRole", reviewer.role);
                json.put("claimedAtEpochMs", claimed);
                json.put("recordSha256", hash);
                writeNew(claimPath, json);
            } catch (JSONException error) {
                throw new IOException("could not encode AI review claim", error);
            }
            return readClaim(reviewContractId);
        }
    }

    public Claim readClaim(String reviewContractId) throws IOException {
        Contract contract = read(reviewContractId);
        Path directory = requireDirectory(reviewContractId);
        try {
            JSONObject json = new JSONObject(
                readSafe(directory.resolve("claim.json"), directory));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI review claim schema");
            }
            String claimId = json.getString("claimId");
            String id = json.getString("reviewContractId");
            String contractSha = json.getString("contractSha256");
            String reviewerAgentId = json.getString("reviewerAgentId");
            String reviewerRole = json.getString("reviewerRole");
            long claimed = json.getLong("claimedAtEpochMs");
            String stored = json.getString("recordSha256");

            validateUuid(claimId);
            validateUuid(id);
            validateRole(reviewerRole);
            LaboratoryAiTeamRegistry.Member reviewer =
                new LaboratoryAiTeamRegistry(
                    appFilesDirectory, projectId).readMember(reviewerAgentId);

            String expected = claimSha(
                claimId, id, contractSha,
                reviewerAgentId, reviewerRole, claimed);
            if (!reviewContractId.equals(id)
                    || !contract.contractSha256.equals(contractSha)
                    || !reviewer.agentId.equals(reviewerAgentId)
                    || !reviewer.role.equals(reviewerRole)
                    || !contract.targetRole.equals(reviewerRole)
                    || claimed <= 0
                    || !validSha(stored)
                    || !stored.equals(expected)) {
                throw new IOException("AI review claim integrity failed");
            }
            return new Claim(
                claimId, id, contractSha,
                reviewerAgentId, reviewerRole, claimed, stored);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI review claim", error);
        }
    }

    /**
     * Revalidates that the user's routing decision is still active.
     * This must be checked immediately before any future review execution.
     */
    public Claim requireActiveClaim(String reviewContractId)
            throws IOException {
        Contract contract = read(reviewContractId);
        Claim claim = readClaim(reviewContractId);
        LaboratoryAiReviewInbox.Item current =
            new LaboratoryAiReviewInbox(
                appFilesDirectory, projectId).readRouted(
                    contract.proposalId);
        if (!contract.targetRole.equals(current.targetRole)
                || !contract.proposalKeySha256.equals(
                    new LaboratoryAiImprovementProposalStore(
                        appFilesDirectory, projectId)
                        .read(contract.proposalId).proposalKeySha256)) {
            throw new IOException("AI review authorization is no longer active");
        }
        return claim;
    }

    public List<Contract> list() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Contract> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_CONTRACTS) {
                throw new IOException("AI review contract history exceeds limit");
            }
            for (Path path : paths) {
                if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected AI review contract entry");
                }
                result.add(read(path.getFileName().toString()));
            }
        }
        result.sort(Comparator
            .comparingLong((Contract contract) -> contract.createdAtEpochMs)
            .reversed()
            .thenComparing(contract -> contract.reviewContractId));
        return Collections.unmodifiableList(result);
    }

    private Path requireDirectory(String reviewContractId) throws IOException {
        Path directory = root.resolve(reviewContractId);
        if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(directory)) {
            throw new IOException("AI review contract not found or unsafe");
        }
        return directory;
    }

    private void ensureRoot() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            Path parent = root.getParent();
            if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(parent)) {
                throw new IOException("AI review contract parent missing or unsafe");
            }
            try {
                Files.createDirectory(root);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(root)) {
            throw new IOException("unsafe AI review contract directory");
        }
    }

    private int countContracts() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            return (int) stream
                .filter(path -> Files.isDirectory(
                    path, LinkOption.NOFOLLOW_LINKS))
                .limit(MAX_CONTRACTS + 1L).count();
        }
    }

    private static String readSafe(Path path, Path expectedParent)
            throws IOException {
        if (!expectedParent.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException("AI review record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI review record already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("AI review record exceeds size limit");
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

    private static String contractSha(
            String reviewContractId, String proposalId,
            String proposalKey, String targetRole,
            String recommendation, String action, long created) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, reviewContractId);
        field(canonical, proposalId);
        field(canonical, proposalKey);
        field(canonical, targetRole);
        field(canonical, recommendation);
        field(canonical, action);
        field(canonical, Long.toString(created));
        return sha256(canonical.toString());
    }

    private static String claimSha(
            String claimId, String reviewContractId,
            String contractSha, String reviewerAgentId,
            String reviewerRole, long claimed) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, claimId);
        field(canonical, reviewContractId);
        field(canonical, contractSha);
        field(canonical, reviewerAgentId);
        field(canonical, reviewerRole);
        field(canonical, Long.toString(claimed));
        return sha256(canonical.toString());
    }

    private static void validateCode(String value) {
        if (value == null || !value.matches("[A-Z0-9_]{1,64}")) {
            throw new IllegalArgumentException("invalid AI review code");
        }
    }

    private static void validateRole(String role) {
        if (!(LaboratoryAiTeamRegistry.ROLE_TESTER.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_CREATOR.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_REVIEWER.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_RESEARCHER.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_ORCHESTRATOR.equals(role)
                || LaboratoryAiTeamRegistry.ROLE_SPECIALIST.equals(role))) {
            throw new IllegalArgumentException("invalid AI review role");
        }
    }

    private static void validateUuid(String value) {
        try {
            if (value == null
                    || !UUID.fromString(value).toString().equals(value)) {
                throw new IllegalArgumentException("invalid UUID");
            }
        } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException("invalid UUID", error);
        }
    }

    private static void field(StringBuilder out, String value) {
        String safe = value == null ? "" : value;
        out.append(safe.length()).append(':').append(safe);
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

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe AI review contract directory");
        }
    }
}
