package com.cafeina.executor;

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
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Stream;

/**
 * Append-only activation history for tools previously approved by the user.
 *
 * An ACTIVATE event makes one approved version eligible for future AI use.
 * A DEACTIVATE event removes the active version. Re-activating an older
 * approved version is the rollback mechanism; old tool records are never
 * overwritten or deleted.
 *
 * This store never executes tools and never mutates projects, scripts or the
 * runtime. Every state-changing method requires a fresh device-auth timestamp
 * supplied by a private UI after Android returned RESULT_OK.
 */
public final class LaboratoryStableActivationStore {
    private static final String MAGIC = "CAFEINA_LAB_STABLE_EVENT";
    private static final String FORMAT = "1";
    private static final String GENESIS = "GENESIS";
    private static final String AUTH_METHOD = "ANDROID_DEVICE_CREDENTIAL";
    private static final int MAX_TOOLS = 32;
    private static final int MAX_EVENTS_PER_TOOL = 128;
    private static final int MAX_RECORD_BYTES = 2048;

    public enum Type { ACTIVATE, DEACTIVATE }

    public static final class Event {
        public final String eventId;
        public final Type type;
        public final String toolId;
        public final String version;
        public final String manifestSha256;
        public final String sourceSha256;
        public final String snapshotId;
        public final String evidenceRunId;
        public final String approvalReceiptSha256;
        public final long authenticatedAtEpochMs;
        public final String previousEventSha256;
        public final String eventSha256;

        private Event(String eventId, Type type, String toolId, String version,
                String manifestSha, String sourceSha, String snapshotId,
                String evidenceRunId, String approvalReceiptSha, long authenticatedAt,
                String previousHash, String eventHash) {
            this.eventId = eventId;
            this.type = type;
            this.toolId = toolId;
            this.version = version;
            this.manifestSha256 = manifestSha;
            this.sourceSha256 = sourceSha;
            this.snapshotId = snapshotId;
            this.evidenceRunId = evidenceRunId;
            this.approvalReceiptSha256 = approvalReceiptSha;
            this.authenticatedAtEpochMs = authenticatedAt;
            this.previousEventSha256 = previousHash;
            this.eventSha256 = eventHash;
        }
    }

    public static final class Active {
        public final String toolId;
        public final String version;
        public final String manifestSha256;
        public final String sourceSha256;
        public final String snapshotId;
        public final String evidenceRunId;
        public final String approvalReceiptSha256;
        public final String activationEventSha256;

        private Active(Event event) {
            toolId = event.toolId;
            version = event.version;
            manifestSha256 = event.manifestSha256;
            sourceSha256 = event.sourceSha256;
            snapshotId = event.snapshotId;
            evidenceRunId = event.evidenceRunId;
            approvalReceiptSha256 = event.approvalReceiptSha256;
            activationEventSha256 = event.eventSha256;
        }
    }

    private final Path labRoot;
    private final Path projectRoot;
    private final Path stableRoot;
    private final LaboratoryToolRegistry registry;
    private final LaboratoryHumanApprovalStore approvals;

    public LaboratoryStableActivationStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid stable-tool project");
        }
        Path app = appFilesDirectory.toPath().toAbsolutePath().normalize();
        labRoot = app.resolve("laboratory");
        projectRoot = labRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        stableRoot = projectRoot.resolve("stable-tool-events");
        registry = new LaboratoryToolRegistry(appFilesDirectory, projectId);
        approvals = new LaboratoryHumanApprovalStore(appFilesDirectory, projectId);
    }

    public synchronized Event activateApproved(String toolId, String version,
            long authenticatedAtEpochMs) throws IOException {
        requireFreshAuthentication(authenticatedAtEpochMs);
        validateToolId(toolId);
        validateVersion(version);

        LaboratoryToolRegistry.Tool tool = registry.read(toolId, version);
        if (tool.state != LaboratoryToolRegistry.State.CANDIDATE) {
            throw new IOException("only a reviewed candidate can become eligible for stable use");
        }
        LaboratoryHumanApprovalStore.Approval approval = approvals.read(toolId, version);
        verifyApprovalMatches(tool, approval);

        List<Event> history = listHistory(toolId);
        if (history.size() >= MAX_EVENTS_PER_TOOL) {
            throw new IOException("stable activation history limit reached");
        }
        Event previous = history.isEmpty() ? null : history.get(history.size() - 1);
        if (previous != null && previous.type == Type.ACTIVATE
                && previous.version.equals(version)) {
            throw new IOException("this tool version is already active");
        }

        ensureToolVault(toolId);
        return append(Type.ACTIVATE, tool, approval, authenticatedAtEpochMs,
            previous == null ? GENESIS : previous.eventSha256);
    }

    public synchronized Event deactivate(String toolId,
            long authenticatedAtEpochMs) throws IOException {
        requireFreshAuthentication(authenticatedAtEpochMs);
        validateToolId(toolId);
        List<Event> history = listHistory(toolId);
        if (history.isEmpty() || history.get(history.size() - 1).type != Type.ACTIVATE) {
            throw new IOException("tool is not currently active");
        }
        Event active = history.get(history.size() - 1);
        LaboratoryToolRegistry.Tool tool = registry.read(toolId, active.version);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.read(toolId, active.version);
        verifyApprovalMatches(tool, approval);
        if (!active.manifestSha256.equals(tool.manifestSha256)
                || !active.sourceSha256.equals(tool.sourceSha256)
                || !active.snapshotId.equals(tool.snapshotId)
                || !active.approvalReceiptSha256.equals(approval.receiptSha256)) {
            throw new IOException("active tool evidence changed before deactivation");
        }
        if (history.size() >= MAX_EVENTS_PER_TOOL) {
            throw new IOException("stable activation history limit reached");
        }
        ensureToolVault(toolId);
        return append(Type.DEACTIVATE, tool, approval, authenticatedAtEpochMs,
            active.eventSha256);
    }

    /** Returns null when no version is active; validates the full event chain. */
    public synchronized Active current(String toolId) throws IOException {
        validateToolId(toolId);
        List<Event> history = listHistory(toolId);
        if (history.isEmpty()) return null;
        Event latest = history.get(history.size() - 1);
        return latest.type == Type.ACTIVATE ? new Active(latest) : null;
    }

    public synchronized boolean isActive(String toolId, String version) throws IOException {
        validateVersion(version);
        Active active = current(toolId);
        return active != null && active.version.equals(version);
    }

    /**
     * Ordered, fully verified history. A fork, missing parent, duplicate event,
     * changed approval or changed tool evidence fails closed.
     */
    public synchronized List<Event> listHistory(String toolId) throws IOException {
        validateToolId(toolId);
        Path toolRoot = toolRoot(toolId);
        if (!Files.exists(stableRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(toolRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireSafeDirectory(stableRoot);
        requireSafeDirectory(toolRoot);

        List<Event> events = new ArrayList<>();
        try (Stream<Path> stream = Files.list(toolRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_EVENTS_PER_TOOL) {
                throw new IOException("stable activation history exceeds limit");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".event")) {
                    throw new IOException("unexpected stable activation entry");
                }
                events.add(readEvent(path));
            }
        }
        if (events.isEmpty()) return Collections.emptyList();

        Map<String, Event> byHash = new HashMap<>();
        Map<String, List<Event>> children = new HashMap<>();
        Event genesis = null;
        for (Event event : events) {
            if (!toolId.equals(event.toolId)) {
                throw new IOException("stable event belongs to another tool");
            }
            if (byHash.put(event.eventSha256, event) != null) {
                throw new IOException("duplicate stable activation event hash");
            }
            children.computeIfAbsent(event.previousEventSha256,
                ignored -> new ArrayList<>()).add(event);
            if (GENESIS.equals(event.previousEventSha256)) {
                if (genesis != null) throw new IOException("stable activation history forked");
                genesis = event;
            }
        }
        if (genesis == null) throw new IOException("stable activation history has no genesis");

        List<Event> ordered = new ArrayList<>();
        Set<String> visited = new HashSet<>();
        Event current = genesis;
        Event previous = null;
        while (current != null) {
            if (!visited.add(current.eventSha256)) {
                throw new IOException("stable activation history contains a cycle");
            }
            validateEventAgainstCurrentEvidence(current);
            if (previous == null) {
                if (!GENESIS.equals(current.previousEventSha256)) {
                    throw new IOException("invalid stable genesis");
                }
            } else {
                if (!previous.eventSha256.equals(current.previousEventSha256)) {
                    throw new IOException("stable activation chain is broken");
                }
                if (current.type == Type.DEACTIVATE
                        && (previous.type != Type.ACTIVATE
                            || !previous.version.equals(current.version))) {
                    throw new IOException("deactivation is not bound to active version");
                }
            }
            ordered.add(current);
            List<Event> next = children.get(current.eventSha256);
            if (next == null || next.isEmpty()) {
                current = null;
            } else {
                if (next.size() != 1) throw new IOException("stable activation history forked");
                current = next.get(0);
            }
            previous = ordered.get(ordered.size() - 1);
        }
        if (visited.size() != events.size()) {
            throw new IOException("orphan stable activation event detected");
        }
        return Collections.unmodifiableList(ordered);
    }

    /** Lists current active selections without executing anything. */
    public synchronized List<Active> listActive() throws IOException {
        if (!Files.exists(stableRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireSafeDirectory(stableRoot);
        List<Active> active = new ArrayList<>();
        try (Stream<Path> stream = Files.list(stableRoot)) {
            List<Path> dirs = new ArrayList<>();
            stream.forEach(dirs::add);
            if (dirs.size() > MAX_TOOLS) {
                throw new IOException("too many stable tool directories");
            }
            for (Path dir : dirs) {
                if (!Files.isDirectory(dir, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(dir)) {
                    throw new IOException("unsafe stable tool directory");
                }
                String toolId = dir.getFileName().toString();
                validateToolId(toolId);
                Active selection = current(toolId);
                if (selection != null) active.add(selection);
            }
        }
        active.sort((a, b) -> a.toolId.compareTo(b.toolId));
        return Collections.unmodifiableList(active);
    }

    private Event append(Type type, LaboratoryToolRegistry.Tool tool,
            LaboratoryHumanApprovalStore.Approval approval, long authenticatedAt,
            String previousHash) throws IOException {
        String id = UUID.randomUUID().toString();
        String payload = lines(MAGIC, FORMAT, id, type.name(), tool.id, tool.version,
            tool.manifestSha256, tool.sourceSha256, tool.snapshotId,
            tool.evidenceRunId, approval.receiptSha256,
            Long.toString(authenticatedAt), AUTH_METHOD, previousHash);
        String eventHash = sha256(payload);
        Path target = toolRoot(tool.id).resolve(id + ".event");
        writeNew(target, payload + eventHash + "\n");
        return readEvent(target);
    }

    private void validateEventAgainstCurrentEvidence(Event event) throws IOException {
        LaboratoryToolRegistry.Tool tool = registry.read(event.toolId, event.version);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.read(event.toolId, event.version);
        verifyApprovalMatches(tool, approval);
        if (!event.manifestSha256.equals(tool.manifestSha256)
                || !event.sourceSha256.equals(tool.sourceSha256)
                || !event.snapshotId.equals(tool.snapshotId)
                || !event.evidenceRunId.equals(tool.evidenceRunId)
                || !event.approvalReceiptSha256.equals(approval.receiptSha256)) {
            throw new IOException("stable activation event no longer matches tool evidence");
        }
    }

    private static void verifyApprovalMatches(LaboratoryToolRegistry.Tool tool,
            LaboratoryHumanApprovalStore.Approval approval) throws IOException {
        if (!tool.id.equals(approval.toolId)
                || !tool.version.equals(approval.version)
                || !tool.manifestSha256.equals(approval.manifestSha256)
                || !tool.sourceSha256.equals(approval.sourceSha256)
                || !tool.evidenceRunId.equals(approval.evidenceRunId)) {
            throw new IOException("human approval does not match the candidate");
        }
    }

    private Event readEvent(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException("stable activation event missing, linked or oversized");
        }
        byte[] raw = Files.readAllBytes(path);
        String text = new String(raw, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(raw, text.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("stable activation event is not valid UTF-8");
        }
        String[] fields = text.split("\n", -1);
        if (fields.length != 16 || !MAGIC.equals(fields[0])
                || !FORMAT.equals(fields[1]) || !fields[15].isEmpty()) {
            throw new IOException("stable activation event format is invalid");
        }
        if (!validUuid(fields[2]) || !fields[6].matches("[0-9a-f]{64}")
                || !fields[7].matches("[0-9a-f]{64}")
                || !LaboratorySnapshotStore.validId(fields[8])
                || !LaboratorySnapshotStore.validId(fields[9])
                || !fields[10].matches("[0-9a-f]{64}")
                || !AUTH_METHOD.equals(fields[12])
                || !(GENESIS.equals(fields[13]) || fields[13].matches("[0-9a-f]{64}"))
                || !fields[14].matches("[0-9a-f]{64}")) {
            throw new IOException("stable activation event fields are invalid");
        }
        validateToolId(fields[4]);
        validateVersion(fields[5]);
        final Type type;
        final long authenticatedAt;
        try {
            type = Type.valueOf(fields[3]);
            authenticatedAt = Long.parseLong(fields[11]);
        } catch (IllegalArgumentException bad) {
            throw new IOException("stable activation event type/timestamp is invalid", bad);
        }
        if (authenticatedAt <= 0
                || authenticatedAt > System.currentTimeMillis() + 10_000L) {
            throw new IOException("stable activation timestamp is invalid");
        }
        String canonical = text.substring(0, text.length() - fields[14].length() - 1);
        if (!sha256(canonical).equals(fields[14])) {
            throw new IOException("stable activation event integrity check failed");
        }
        return new Event(fields[2], type, fields[4], fields[5], fields[6], fields[7],
            fields[8], fields[9], fields[10], authenticatedAt, fields[13], fields[14]);
    }

    private void ensureToolVault(String toolId) throws IOException {
        ensureSafeDirectory(labRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(stableRoot);
        if (!Files.exists(toolRoot(toolId), LinkOption.NOFOLLOW_LINKS)) {
            int count;
            try (Stream<Path> stream = Files.list(stableRoot)) {
                count = (int) stream.limit(MAX_TOOLS + 1).count();
            }
            if (count >= MAX_TOOLS) throw new IOException("stable tool limit reached");
        }
        ensureSafeDirectory(toolRoot(toolId));
    }

    private Path toolRoot(String toolId) {
        return stableRoot.resolve(toolId);
    }

    private static void requireFreshAuthentication(long authenticatedAt) throws IOException {
        long now = System.currentTimeMillis();
        if (authenticatedAt <= 0 || authenticatedAt > now + 10_000L
                || now - authenticatedAt > 60_000L) {
            throw new IOException("device authentication is missing or stale");
        }
    }

    private static void validateToolId(String id) {
        if (id == null || !id.matches("[a-z][a-z0-9-]{2,47}")) {
            throw new IllegalArgumentException("invalid stable tool id");
        }
    }

    private static void validateVersion(String version) {
        if (version == null
                || !version.matches(
                    "(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})")) {
            throw new IllegalArgumentException("invalid stable tool version");
        }
    }

    private static boolean validUuid(String id) {
        try {
            return id != null && UUID.fromString(id).toString().equals(id);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException raced) {
                // Revalidate below.
            }
        }
        requireSafeDirectory(path);
    }

    private static void requireSafeDirectory(Path path) throws IOException {
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe stable activation directory");
        }
    }

    private static void writeNew(Path destination, String content) throws IOException {
        byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("stable activation event exceeds size budget");
        }
        try (FileChannel output = FileChannel.open(destination,
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer data = ByteBuffer.wrap(bytes);
            while (data.hasRemaining()) output.write(data);
            output.force(true);
        }
    }

    private static String lines(String... fields) {
        StringBuilder out = new StringBuilder();
        for (String field : fields) out.append(field).append('\n');
        return out.toString();
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) out.append(String.format(Locale.ROOT, "%02x", b & 255));
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
