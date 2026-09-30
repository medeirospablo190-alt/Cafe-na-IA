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
 * Append-only user permission history controlling which verified STABLE tools
 * may be exposed to the future AI controller. Default is deny.
 */
public final class LaboratoryAiPermissionStore {
    public static final String GRANT = "GRANT_AI_USE";
    public static final String REVOKE = "REVOKE_AI_USE";
    public static final int MAX_EVENTS = 512;
    public static final int MAX_EVENT_BYTES = 12 * 1024;
    private static final long AUTH_FRESHNESS_MS = 60_000L;

    public static final class Grant {
        public final String eventId;
        public final int sequence;
        public final long createdAtEpochMs;
        public final String toolId;
        public final String version;
        public final String descriptorSha256;
        public final String artifactSha256;
        public final String snapshotId;
        public final String authenticationMethod;

        private Grant(String eventId, int sequence, long createdAtEpochMs,
                String toolId, String version, String descriptorSha256,
                String artifactSha256, String snapshotId,
                String authenticationMethod) {
            this.eventId = eventId;
            this.sequence = sequence;
            this.createdAtEpochMs = createdAtEpochMs;
            this.toolId = toolId;
            this.version = version;
            this.descriptorSha256 = descriptorSha256;
            this.artifactSha256 = artifactSha256;
            this.snapshotId = snapshotId;
            this.authenticationMethod = authenticationMethod;
        }
    }

    private static final class Event {
        final String eventId;
        final int sequence;
        final long createdAtEpochMs;
        final String action;
        final String toolId;
        final String version;
        final String descriptorSha256;
        final String artifactSha256;
        final String snapshotId;
        final String authenticationMethod;

        Event(String eventId, int sequence, long createdAtEpochMs, String action,
                String toolId, String version, String descriptorSha256,
                String artifactSha256, String snapshotId,
                String authenticationMethod) {
            this.eventId = eventId;
            this.sequence = sequence;
            this.createdAtEpochMs = createdAtEpochMs;
            this.action = action;
            this.toolId = toolId;
            this.version = version;
            this.descriptorSha256 = descriptorSha256;
            this.artifactSha256 = artifactSha256;
            this.snapshotId = snapshotId;
            this.authenticationMethod = authenticationMethod;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path permissionRoot;
    private final LaboratoryToolRegistry registry;
    private final LaboratoryToolArtifactStore artifacts;

    public LaboratoryAiPermissionStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI permission project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        permissionRoot = projectRoot.resolve("ai-tool-permissions");
        registry = new LaboratoryToolRegistry(appFilesDirectory, projectId);
        artifacts = new LaboratoryToolArtifactStore(appFilesDirectory, projectId);
    }

    /**
     * Call only after Android device credential confirmation succeeds.
     */
    synchronized Grant grantAfterDeviceCredential(
            String toolId, long authenticatedAtEpochMs) throws IOException {
        validateFreshAuthentication(authenticatedAtEpochMs);
        LaboratoryToolRegistry.Descriptor active = registry.activeStable(toolId);
        if (active == null) throw new IOException("tool has no active STABLE version");
        if (!active.capabilities.contains(
                LaboratoryStableToolExecutor.REQUIRED_CAPABILITY)) {
            throw new IOException("STABLE tool is not eligible for isolated AI use");
        }
        LaboratoryToolArtifactStore.Binding binding =
            artifacts.readActiveStableVerified(toolId);
        if (!active.version.equals(binding.version)
                || !active.artifactSha256.equals(binding.artifactSha256)) {
            throw new IOException("active STABLE artifact cannot be verified");
        }

        Grant existing = activeGrant(toolId);
        if (existing != null
                && existing.version.equals(active.version)
                && existing.artifactSha256.equals(active.artifactSha256)
                && existing.snapshotId.equals(binding.snapshotId)) {
            throw new IOException("AI use is already granted for this exact STABLE version");
        }

        Event event = append(GRANT, toolId, active.version,
            descriptorSha256(active), active.artifactSha256, binding.snapshotId,
            LaboratoryHumanApprovalStore.AUTH_METHOD);
        return toGrant(event);
    }

    public synchronized void revoke(String toolId) throws IOException {
        Grant grant = activeGrant(toolId);
        if (grant == null) {
            throw new IOException("AI use is not currently granted for this tool");
        }
        append(REVOKE, grant.toolId, grant.version, grant.descriptorSha256,
            grant.artifactSha256, grant.snapshotId, "USER_EXPLICIT_REVOKE");
    }

    /**
     * Returns null unless the latest permission event is GRANT and still
     * matches the current verified STABLE selection exactly.
     */
    public synchronized Grant activeGrant(String toolId) throws IOException {
        Event latest = latestEvent(toolId);
        if (latest == null || !GRANT.equals(latest.action)) return null;

        LaboratoryToolRegistry.Descriptor active = registry.activeStable(toolId);
        if (active == null
                || !latest.version.equals(active.version)
                || !latest.descriptorSha256.equals(descriptorSha256(active))
                || !latest.artifactSha256.equals(active.artifactSha256)) {
            return null;
        }
        LaboratoryToolArtifactStore.Binding binding =
            artifacts.readActiveStableVerified(toolId);
        if (!latest.snapshotId.equals(binding.snapshotId)
                || !latest.artifactSha256.equals(binding.artifactSha256)) {
            return null;
        }
        return toGrant(latest);
    }

    public synchronized List<Grant> listActiveGrants() throws IOException {
        List<String> toolIds = new ArrayList<>();
        for (Event event : history()) {
            if (!toolIds.contains(event.toolId)) toolIds.add(event.toolId);
        }
        Collections.sort(toolIds);
        List<Grant> grants = new ArrayList<>();
        for (String toolId : toolIds) {
            Grant grant = activeGrant(toolId);
            if (grant != null) grants.add(grant);
        }
        return Collections.unmodifiableList(grants);
    }

    public synchronized boolean isGranted(String toolId) throws IOException {
        return activeGrant(toolId) != null;
    }

    private Event append(String action, String toolId, String version,
            String descriptorSha, String artifactSha, String snapshotId,
            String authMethod) throws IOException {
        if (!(GRANT.equals(action) || REVOKE.equals(action))
                || toolId == null
                || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                || !validVersion(version)
                || !validSha(descriptorSha) || !validSha(artifactSha)
                || !LaboratorySnapshotStore.validId(snapshotId)
                || authMethod == null || authMethod.length() > 64) {
            throw new IOException("invalid AI permission event");
        }
        ensureWritable();
        List<Event> existing = history();
        if (existing.size() >= MAX_EVENTS) {
            throw new IOException(
                "AI permission history limit reached; existing history was preserved");
        }
        int sequence = existing.isEmpty()
            ? 1 : existing.get(existing.size() - 1).sequence + 1;
        String eventId = UUID.randomUUID().toString();
        long now = System.currentTimeMillis();
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("eventId", eventId);
            json.put("sequence", sequence);
            json.put("createdAtEpochMs", now);
            json.put("action", action);
            json.put("toolId", toolId);
            json.put("version", version);
            json.put("descriptorSha256", descriptorSha);
            json.put("artifactSha256", artifactSha);
            json.put("snapshotId", snapshotId);
            json.put("authenticationMethod", authMethod);
            json.put("eventSha256", eventSha(
                eventId, sequence, now, action, toolId, version,
                descriptorSha, artifactSha, snapshotId, authMethod));
            String fileName = String.format(Locale.ROOT, "%06d.json", sequence);
            writeNew(permissionRoot.resolve(fileName), json);
            return parse(json.toString());
        } catch (JSONException error) {
            throw new IOException("could not encode AI permission event", error);
        }
    }

    private Event latestEvent(String toolId) throws IOException {
        Event latest = null;
        for (Event event : history()) {
            if (event.toolId.equals(toolId)) latest = event;
        }
        return latest;
    }

    private List<Event> history() throws IOException {
        if (!Files.exists(permissionRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireExistingDirectories();
        List<Event> events = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(permissionRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_EVENTS) {
                throw new IOException("AI permission history exceeds limit");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.matches("[0-9]{6}\\.json")) {
                    throw new IOException("unexpected AI permission record");
                }
                try {
                    events.add(parse(readSafe(path)));
                } catch (JSONException error) {
                    throw new IOException("invalid AI permission record", error);
                }
            }
        }
        events.sort(Comparator.comparingInt(event -> event.sequence));
        for (int i = 0; i < events.size(); i++) {
            if (events.get(i).sequence != i + 1) {
                throw new IOException("AI permission history sequence is incomplete");
            }
        }
        return Collections.unmodifiableList(events);
    }

    private Event parse(String raw) throws JSONException {
        JSONObject json = new JSONObject(raw);
        if (json.getInt("schemaVersion") != 1) {
            throw new JSONException("unsupported AI permission record");
        }
        String eventId = json.getString("eventId");
        int sequence = json.getInt("sequence");
        long created = json.getLong("createdAtEpochMs");
        String action = json.getString("action");
        String toolId = json.getString("toolId");
        String version = json.getString("version");
        String descriptorSha = json.getString("descriptorSha256");
        String artifactSha = json.getString("artifactSha256");
        String snapshotId = json.getString("snapshotId");
        String auth = json.getString("authenticationMethod");
        String eventSha = json.getString("eventSha256");

        if (!validUuid(eventId) || sequence < 1 || sequence > MAX_EVENTS
                || created <= 0
                || !(GRANT.equals(action) || REVOKE.equals(action))
                || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                || !validVersion(version)
                || !validSha(descriptorSha) || !validSha(artifactSha)
                || !LaboratorySnapshotStore.validId(snapshotId)
                || auth.isEmpty() || auth.length() > 64
                || !validSha(eventSha)
                || !eventSha.equals(eventSha(
                    eventId, sequence, created, action, toolId, version,
                    descriptorSha, artifactSha, snapshotId, auth))) {
            throw new JSONException("AI permission record failed validation");
        }
        return new Event(eventId, sequence, created, action, toolId, version,
            descriptorSha, artifactSha, snapshotId, auth);
    }

    private static Grant toGrant(Event event) {
        return new Grant(event.eventId, event.sequence, event.createdAtEpochMs,
            event.toolId, event.version, event.descriptorSha256,
            event.artifactSha256, event.snapshotId, event.authenticationMethod);
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
        ensureSafeDirectory(permissionRoot);
    }

    private void requireExistingDirectories() throws IOException {
        for (Path path : new Path[]{laboratoryRoot, projectRoot, permissionRoot}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("AI permission directory missing or unsafe");
            }
        }
    }

    private String readSafe(Path path) throws IOException {
        if (!permissionRoot.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_EVENT_BYTES) {
            throw new IOException("AI permission record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI permission event already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_EVENT_BYTES) {
            throw new IOException("AI permission event exceeds size budget");
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
                throw new IOException("AI permission event already exists");
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

    private static String eventSha(String eventId, int sequence, long created,
            String action, String toolId, String version, String descriptorSha,
            String artifactSha, String snapshotId, String auth) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, eventId);
        field(canonical, Integer.toString(sequence));
        field(canonical, Long.toString(created));
        field(canonical, action);
        field(canonical, toolId);
        field(canonical, version);
        field(canonical, descriptorSha);
        field(canonical, artifactSha);
        field(canonical, snapshotId);
        field(canonical, auth);
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
            throw new IOException("unsafe AI permission directory");
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
