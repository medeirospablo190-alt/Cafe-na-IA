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
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

/**
 * Create-only human approval receipts for STABLE activation and rollback.
 *
 * Recording a receipt does not change tool state. A receipt is bound to the
 * exact transition, descriptor fingerprint, artifact hash, verified snapshot,
 * test evidence and regression evidence that the user reviewed.
 *
 * Device credential verification itself belongs to LaboratoryApprovalActivity.
 * This store receives only a recent authenticated timestamp and therefore is an
 * application policy boundary, not a root-resistant proof of identity.
 */
public final class LaboratoryHumanApprovalStore {
    public static final String ACTIVATE_STABLE = "ACTIVATE_STABLE";
    public static final String ROLLBACK_STABLE = "ROLLBACK_STABLE";
    public static final String AUTH_METHOD = "ANDROID_DEVICE_CREDENTIAL";
    public static final int MAX_RECEIPTS = 128;
    public static final int MAX_RECEIPT_BYTES = 24 * 1024;
    private static final long AUTH_FRESHNESS_MS = 60_000L;

    public static final class Preview {
        public final String action;
        public final String toolId;
        public final String fromVersion;
        public final String toVersion;
        public final String descriptorSha256;
        public final String artifactSha256;
        public final String snapshotId;
        public final List<String> evidenceRunIds;
        public final List<String> regressionComparisonIds;

        private Preview(String action, String toolId, String fromVersion,
                String toVersion, String descriptorSha256, String artifactSha256,
                String snapshotId, List<String> evidenceRunIds,
                List<String> regressionComparisonIds) {
            this.action = action;
            this.toolId = toolId;
            this.fromVersion = fromVersion;
            this.toVersion = toVersion;
            this.descriptorSha256 = descriptorSha256;
            this.artifactSha256 = artifactSha256;
            this.snapshotId = snapshotId;
            this.evidenceRunIds = immutable(evidenceRunIds);
            this.regressionComparisonIds = immutable(regressionComparisonIds);
        }
    }

    public static final class Approval {
        public final String receiptId;
        public final String action;
        public final String toolId;
        public final String fromVersion;
        public final String toVersion;
        public final String descriptorSha256;
        public final String artifactSha256;
        public final String snapshotId;
        public final List<String> evidenceRunIds;
        public final List<String> regressionComparisonIds;
        public final long approvedAtEpochMs;
        public final String authenticationMethod;
        public final String receiptSha256;
        public final boolean consumed;

        private Approval(String receiptId, String action, String toolId,
                String fromVersion, String toVersion, String descriptorSha256,
                String artifactSha256, String snapshotId, List<String> evidenceRunIds,
                List<String> regressionComparisonIds, long approvedAtEpochMs,
                String authenticationMethod, String receiptSha256, boolean consumed) {
            this.receiptId = receiptId;
            this.action = action;
            this.toolId = toolId;
            this.fromVersion = fromVersion;
            this.toVersion = toVersion;
            this.descriptorSha256 = descriptorSha256;
            this.artifactSha256 = artifactSha256;
            this.snapshotId = snapshotId;
            this.evidenceRunIds = immutable(evidenceRunIds);
            this.regressionComparisonIds = immutable(regressionComparisonIds);
            this.approvedAtEpochMs = approvedAtEpochMs;
            this.authenticationMethod = authenticationMethod;
            this.receiptSha256 = receiptSha256;
            this.consumed = consumed;
        }
    }

    private final File appFilesDirectory;
    private final String projectId;
    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path approvalRoot;
    private final Path consumedRoot;
    private final LaboratoryToolRegistry registry;
    private final LaboratoryToolArtifactStore artifacts;

    public LaboratoryHumanApprovalStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid human approval project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        this.laboratoryRoot = appRoot.resolve("laboratory");
        this.projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        this.approvalRoot = projectRoot.resolve("human-approvals");
        this.consumedRoot = approvalRoot.resolve("consumed");
        this.registry = new LaboratoryToolRegistry(appFilesDirectory, projectId);
        this.artifacts = new LaboratoryToolArtifactStore(appFilesDirectory, projectId);
    }

    public synchronized Preview previewActivation(String toolId, String version)
            throws IOException {
        LaboratoryToolRegistry.Descriptor candidate =
            registry.readDescriptor(toolId, version);
        if (registry.stage(toolId, version) != LaboratoryToolRegistry.Stage.CANDIDATE) {
            throw new IOException("only a CANDIDATE tool can be approved for STABLE");
        }
        LaboratoryToolArtifactStore.Binding binding =
            artifacts.readVerified(toolId, version);
        if (!candidate.artifactSha256.equals(binding.artifactSha256)) {
            throw new IOException("candidate artifact binding does not match descriptor");
        }

        List<String> evidence = candidateEvidence(toolId, version);
        LaboratoryToolRegistry.Descriptor current = registry.activeStable(toolId);
        String fromVersion = current == null ? "" : current.version;
        List<String> regressions = current == null
            ? Collections.emptyList()
            : selectRegressionEvidence(current, candidate, evidence);

        return new Preview(ACTIVATE_STABLE, toolId, fromVersion, version,
            descriptorSha256(candidate), candidate.artifactSha256,
            binding.snapshotId, evidence, regressions);
    }

    public synchronized Preview previewRollback(String toolId, String targetVersion)
            throws IOException {
        LaboratoryToolRegistry.Descriptor current = registry.activeStable(toolId);
        if (current == null) throw new IOException("no active STABLE version");
        if (current.version.equals(targetVersion)) {
            throw new IOException("rollback target is already active");
        }
        LaboratoryToolRegistry.Descriptor target =
            registry.readDescriptor(toolId, targetVersion);
        if (registry.stage(toolId, targetVersion) != LaboratoryToolRegistry.Stage.STABLE) {
            throw new IOException("rollback target was never STABLE");
        }
        LaboratoryToolArtifactStore.Binding binding =
            artifacts.readVerified(toolId, targetVersion);
        if (!target.artifactSha256.equals(binding.artifactSha256)) {
            throw new IOException("rollback artifact binding does not match descriptor");
        }
        return new Preview(ROLLBACK_STABLE, toolId, current.version, targetVersion,
            descriptorSha256(target), target.artifactSha256, binding.snapshotId,
            Collections.emptyList(), Collections.emptyList());
    }

    /**
     * Call only after the private approval Activity receives RESULT_OK from
     * Android device credential confirmation.
     */
    synchronized Approval recordDeviceCredentialApproval(String action,
            String toolId, String targetVersion, long authenticatedAtEpochMs)
            throws IOException {
        validateFreshAuthentication(authenticatedAtEpochMs);
        Preview preview = ACTIVATE_STABLE.equals(action)
            ? previewActivation(toolId, targetVersion)
            : ROLLBACK_STABLE.equals(action)
                ? previewRollback(toolId, targetVersion)
                : null;
        if (preview == null) throw new IOException("unsupported approval action");

        ensureWritable();
        if (countReceipts() >= MAX_RECEIPTS) {
            throw new IOException("approval limit reached; existing decisions were preserved");
        }

        String receiptId = UUID.randomUUID().toString();
        long approvedAt = System.currentTimeMillis();
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("receiptId", receiptId);
            json.put("action", preview.action);
            json.put("toolId", preview.toolId);
            json.put("fromVersion", preview.fromVersion);
            json.put("toVersion", preview.toVersion);
            json.put("descriptorSha256", preview.descriptorSha256);
            json.put("artifactSha256", preview.artifactSha256);
            json.put("snapshotId", preview.snapshotId);
            json.put("evidenceRunIds", new JSONArray(preview.evidenceRunIds));
            json.put("regressionComparisonIds",
                new JSONArray(preview.regressionComparisonIds));
            json.put("approvedAtEpochMs", approvedAt);
            json.put("authenticationMethod", AUTH_METHOD);
            json.put("receiptSha256", receiptSha(
                receiptId, preview, approvedAt, AUTH_METHOD));
            writeNew(approvalRoot.resolve(receiptId + ".json"), json,
                MAX_RECEIPT_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode human approval receipt", error);
        }
        return read(receiptId);
    }

    public synchronized Approval read(String receiptId) throws IOException {
        if (!validUuid(receiptId)) throw new IOException("invalid approval receipt id");
        requireExistingDirectories();
        Path path = approvalRoot.resolve(receiptId + ".json");
        try {
            JSONObject json = new JSONObject(readSafe(path));
            Approval approval = parse(json, isConsumed(receiptId));
            validateStaticBinding(approval);
            return approval;
        } catch (JSONException error) {
            throw new IOException("invalid human approval receipt", error);
        }
    }

    public synchronized List<Approval> list() throws IOException {
        if (!Files.exists(approvalRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireExistingDirectories();
        List<Approval> approvals = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(approvalRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_RECEIPTS + 1) {
                throw new IOException("approval vault exceeds entry budget");
            }
            for (Path path : paths) {
                if (Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) {
                    if (!path.equals(consumedRoot)) {
                        throw new IOException("unexpected approval directory");
                    }
                    continue;
                }
                String name = path.getFileName().toString();
                if (!name.endsWith(".json")
                        || !validUuid(name.substring(0, name.length() - 5))) {
                    throw new IOException("unexpected approval vault entry");
                }
                approvals.add(read(name.substring(0, name.length() - 5)));
            }
        }
        approvals.sort(Comparator
            .comparingLong((Approval approval) -> approval.approvedAtEpochMs)
            .reversed()
            .thenComparing(approval -> approval.receiptId));
        return Collections.unmodifiableList(approvals);
    }

    /**
     * Applies one exact, previously authenticated decision. The receipt is
     * consumed by the ApprovalGate immediately before the registry event is
     * written. If later persistence fails, the receipt remains consumed
     * fail-closed and the user must approve again.
     */
    public synchronized void applyApprovedTransition(String receiptId)
            throws IOException {
        Approval approval = read(receiptId);
        if (approval.consumed) throw new IOException("approval receipt already consumed");

        LaboratoryToolRegistry.ApprovalGate gate =
            (action, toolId, fromVersion, toVersion, approvalId) -> {
                if (!receiptId.equals(approvalId)
                        || !approval.action.equals(action)
                        || !approval.toolId.equals(toolId)
                        || !approval.fromVersion.equals(fromVersion)
                        || !approval.toVersion.equals(toVersion)) {
                    return false;
                }
                try {
                    validateCurrentTransition(approval);
                    consume(approval);
                    return true;
                } catch (IOException invalid) {
                    return false;
                }
            };

        if (ACTIVATE_STABLE.equals(approval.action)) {
            registry.activateStable(approval.toolId, approval.toVersion,
                approval.evidenceRunIds, approval.regressionComparisonIds,
                approval.receiptId, gate);
        } else if (ROLLBACK_STABLE.equals(approval.action)) {
            registry.rollbackStable(approval.toolId, approval.toVersion,
                approval.receiptId, gate);
        } else {
            throw new IOException("unsupported approval action");
        }
    }

    private void validateCurrentTransition(Approval approval) throws IOException {
        validateStaticBinding(approval);
        if (ACTIVATE_STABLE.equals(approval.action)) {
            Preview current = previewActivation(approval.toolId, approval.toVersion);
            if (!samePreview(approval, current)) {
                throw new IOException("approved STABLE transition changed after review");
            }
        } else if (ROLLBACK_STABLE.equals(approval.action)) {
            Preview current = previewRollback(approval.toolId, approval.toVersion);
            if (!samePreview(approval, current)) {
                throw new IOException("approved rollback changed after review");
            }
        } else {
            throw new IOException("unsupported approval action");
        }
    }

    private void validateStaticBinding(Approval approval) throws IOException {
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(approval.toolId, approval.toVersion);
        if (!approval.descriptorSha256.equals(descriptorSha256(descriptor))
                || !approval.artifactSha256.equals(descriptor.artifactSha256)) {
            throw new IOException("approval no longer matches tool descriptor");
        }
        LaboratoryToolArtifactStore.Binding binding =
            artifacts.readVerified(approval.toolId, approval.toVersion);
        if (!approval.snapshotId.equals(binding.snapshotId)
                || !approval.artifactSha256.equals(binding.artifactSha256)) {
            throw new IOException("approval no longer matches executable snapshot");
        }
    }

    private List<String> candidateEvidence(String toolId, String version)
            throws IOException {
        LaboratoryToolRegistry.Event qualification = null;
        for (LaboratoryToolRegistry.Event event : registry.history(toolId)) {
            if ("QUALIFY_CANDIDATE".equals(event.action)
                    && version.equals(event.version)) {
                qualification = event;
            }
        }
        if (qualification == null || qualification.evidenceRunIds.isEmpty()) {
            throw new IOException("candidate qualification evidence is missing");
        }
        return qualification.evidenceRunIds;
    }

    private List<String> selectRegressionEvidence(
            LaboratoryToolRegistry.Descriptor baseline,
            LaboratoryToolRegistry.Descriptor candidate,
            List<String> candidateEvidence) throws IOException {
        LaboratoryRegressionStore store =
            new LaboratoryRegressionStore(appFilesDirectory, projectId);
        List<String> selected = new ArrayList<>();
        Set<String> covered = new HashSet<>();

        for (LaboratoryRegressionStore.Record record : store.list()) {
            if (!"PASS".equals(record.verdict)
                    || !record.requireSameEnvironment
                    || record.maxSlowdownPercent
                        > LaboratoryToolRegistry.STABLE_MAX_SLOWDOWN_PERCENT
                    || record.graceMs > LaboratoryToolRegistry.STABLE_MAX_GRACE_MS
                    || !baseline.artifactSha256.equals(record.baselineInputSha256)
                    || !candidate.artifactSha256.equals(record.candidateInputSha256)
                    || !candidateEvidence.contains(record.candidateRunId)) {
                continue;
            }
            boolean addsCoverage = false;
            for (String test : record.coveredTests) {
                if (candidate.requiredTests.contains(test) && covered.add(test)) {
                    addsCoverage = true;
                }
            }
            if (addsCoverage) {
                selected.add(record.comparisonId);
                if (selected.size() > 32) {
                    throw new IOException("too many regression records for approval");
                }
            }
            if (covered.containsAll(candidate.requiredTests)) break;
        }
        if (!covered.containsAll(candidate.requiredTests)) {
            throw new IOException("candidate lacks complete regression evidence for STABLE");
        }
        return Collections.unmodifiableList(selected);
    }

    private boolean samePreview(Approval approval, Preview preview) {
        return approval.action.equals(preview.action)
            && approval.toolId.equals(preview.toolId)
            && approval.fromVersion.equals(preview.fromVersion)
            && approval.toVersion.equals(preview.toVersion)
            && approval.descriptorSha256.equals(preview.descriptorSha256)
            && approval.artifactSha256.equals(preview.artifactSha256)
            && approval.snapshotId.equals(preview.snapshotId)
            && approval.evidenceRunIds.equals(preview.evidenceRunIds)
            && approval.regressionComparisonIds.equals(preview.regressionComparisonIds);
    }

    private void consume(Approval approval) throws IOException {
        ensureWritable();
        Path marker = consumedRoot.resolve(approval.receiptId + ".used");
        if (Files.exists(marker, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("approval receipt already consumed");
        }
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("receiptId", approval.receiptId);
            json.put("receiptSha256", approval.receiptSha256);
            json.put("action", approval.action);
            json.put("toolId", approval.toolId);
            json.put("fromVersion", approval.fromVersion);
            json.put("toVersion", approval.toVersion);
            json.put("consumedAtEpochMs", System.currentTimeMillis());
            writeNew(marker, json, 4096);
        } catch (JSONException error) {
            throw new IOException("could not encode approval consumption marker", error);
        }
    }

    private boolean isConsumed(String receiptId) throws IOException {
        Path marker = consumedRoot.resolve(receiptId + ".used");
        if (!Files.exists(marker, LinkOption.NOFOLLOW_LINKS)) return false;
        if (!Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(marker) || Files.size(marker) > 4096) {
            throw new IOException("approval consumption marker is unsafe");
        }
        try {
            JSONObject json = new JSONObject(
                new String(Files.readAllBytes(marker), StandardCharsets.UTF_8));
            if (!receiptId.equals(json.getString("receiptId"))
                    || json.getLong("consumedAtEpochMs") <= 0) {
                throw new IOException("approval consumption marker is invalid");
            }
            return true;
        } catch (JSONException error) {
            throw new IOException("invalid approval consumption marker", error);
        }
    }

    private Approval parse(JSONObject json, boolean consumed) throws JSONException {
        if (json.getInt("schemaVersion") != 1) {
            throw new JSONException("unsupported approval receipt version");
        }
        String receiptId = json.getString("receiptId");
        String action = json.getString("action");
        String toolId = json.getString("toolId");
        String fromVersion = json.optString("fromVersion");
        String toVersion = json.getString("toVersion");
        String descriptorSha = json.getString("descriptorSha256");
        String artifactSha = json.getString("artifactSha256");
        String snapshotId = json.getString("snapshotId");
        List<String> evidence = strings(json.getJSONArray("evidenceRunIds"));
        List<String> regressions = strings(json.getJSONArray("regressionComparisonIds"));
        long approvedAt = json.getLong("approvedAtEpochMs");
        String auth = json.getString("authenticationMethod");
        String receiptSha = json.getString("receiptSha256");

        Preview preview = new Preview(action, toolId, fromVersion, toVersion,
            descriptorSha, artifactSha, snapshotId, evidence, regressions);
        if (!validUuid(receiptId)
                || !(ACTIVATE_STABLE.equals(action) || ROLLBACK_STABLE.equals(action))
                || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                || !validVersion(toVersion)
                || (!fromVersion.isEmpty() && !validVersion(fromVersion))
                || !validSha(descriptorSha) || !validSha(artifactSha)
                || !LaboratorySnapshotStore.validId(snapshotId)
                || evidence.size() > 32 || regressions.size() > 32
                || approvedAt <= 0 || !AUTH_METHOD.equals(auth)
                || !validSha(receiptSha)
                || !receiptSha.equals(receiptSha(receiptId, preview, approvedAt, auth))) {
            throw new JSONException("approval receipt failed validation");
        }
        return new Approval(receiptId, action, toolId, fromVersion, toVersion,
            descriptorSha, artifactSha, snapshotId, evidence, regressions,
            approvedAt, auth, receiptSha, consumed);
    }

    private static String descriptorSha256(
            LaboratoryToolRegistry.Descriptor descriptor) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, descriptor.toolId);
        field(canonical, descriptor.version);
        field(canonical, descriptor.artifactSha256);
        field(canonical, descriptor.origin);
        list(canonical, descriptor.capabilities);
        list(canonical, descriptor.requiredTests);
        field(canonical, descriptor.compatibility);
        field(canonical, Integer.toString(descriptor.maxRuntimeMs));
        field(canonical, Integer.toString(descriptor.maxInputBytes));
        return sha256(canonical.toString());
    }

    private static String receiptSha(String receiptId, Preview preview,
            long approvedAt, String authMethod) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, receiptId);
        field(canonical, preview.action);
        field(canonical, preview.toolId);
        field(canonical, preview.fromVersion);
        field(canonical, preview.toVersion);
        field(canonical, preview.descriptorSha256);
        field(canonical, preview.artifactSha256);
        field(canonical, preview.snapshotId);
        list(canonical, preview.evidenceRunIds);
        list(canonical, preview.regressionComparisonIds);
        field(canonical, Long.toString(approvedAt));
        field(canonical, authMethod);
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

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            String value = array.getString(i);
            if (value == null || value.length() > 128 || values.contains(value)) {
                throw new JSONException("invalid approval evidence list");
            }
            values.add(value);
        }
        return values;
    }

    private static List<String> immutable(List<String> values) {
        return Collections.unmodifiableList(new ArrayList<>(values));
    }

    private void validateFreshAuthentication(long authenticatedAtEpochMs)
            throws IOException {
        long now = System.currentTimeMillis();
        if (authenticatedAtEpochMs <= 0
                || authenticatedAtEpochMs > now + 10_000L
                || now - authenticatedAtEpochMs > AUTH_FRESHNESS_MS) {
            throw new IOException("device authentication is missing or stale");
        }
    }

    private void ensureWritable() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(approvalRoot);
        ensureSafeDirectory(consumedRoot);
    }

    private void requireExistingDirectories() throws IOException {
        for (Path path : new Path[]{laboratoryRoot, projectRoot, approvalRoot, consumedRoot}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("approval directory missing or unsafe");
            }
        }
    }

    private int countReceipts() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(approvalRoot)) {
            return (int) stream.filter(path -> {
                String name = path.getFileName().toString();
                return name.endsWith(".json")
                    && validUuid(name.substring(0, name.length() - 5));
            }).limit(MAX_RECEIPTS + 1L).count();
        }
    }

    private String readSafe(Path path) throws IOException {
        if (!approvalRoot.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_RECEIPT_BYTES) {
            throw new IOException("approval receipt missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json, int maxBytes)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("approval record already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > maxBytes) throw new IOException("approval record too large");
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
                throw new IOException("approval record already exists");
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
            throw new IOException("unsafe approval directory");
        }
    }

    private static boolean validUuid(String value) {
        try {
            return value != null && UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static boolean validVersion(String value) {
        return value != null
            && value.matches("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]{1,32})?");
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
