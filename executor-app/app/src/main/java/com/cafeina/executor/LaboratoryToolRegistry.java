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
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Immutable tool-version catalog plus append-only lifecycle history.
 *
 * Candidate code never receives this object. Stable activation and rollback
 * require an approval gate supplied by trusted host UI code; this class has no
 * permissive/default approval implementation.
 */
public final class LaboratoryToolRegistry {
    public static final int MAX_VERSIONS_PER_TOOL = 64;
    public static final int MAX_EVENTS_PER_TOOL = 256;
    public static final int MAX_DESCRIPTOR_BYTES = 16 * 1024;
    public static final int MAX_EVENT_BYTES = 12 * 1024;

    public enum Stage { EXPERIMENTAL, CANDIDATE, STABLE }

    public interface ApprovalGate {
        boolean isApproved(String action, String toolId, String fromVersion,
                String toVersion, String approvalId);
    }

    public static final class Descriptor {
        public final String toolId;
        public final String version;
        public final String artifactSha256;
        public final String origin;
        public final List<String> capabilities;
        public final List<String> requiredTests;
        public final String compatibility;
        public final int maxRuntimeMs;
        public final int maxInputBytes;

        public Descriptor(String toolId, String version, String artifactSha256,
                String origin, List<String> capabilities, List<String> requiredTests,
                String compatibility, int maxRuntimeMs, int maxInputBytes) {
            validateToolId(toolId);
            validateVersion(version);
            validateSha256(artifactSha256);
            if (origin == null || !origin.matches("[A-Z0-9_-]{1,48}")) {
                throw new IllegalArgumentException("invalid tool origin");
            }
            this.capabilities = safeNames(capabilities, "capability");
            this.requiredTests = safeNames(requiredTests, "required test");
            if (compatibility == null || compatibility.isEmpty()
                    || compatibility.length() > 128) {
                throw new IllegalArgumentException("invalid compatibility");
            }
            if (maxRuntimeMs < 1 || maxRuntimeMs > 60_000) {
                throw new IllegalArgumentException("invalid runtime limit");
            }
            if (maxInputBytes < 1 || maxInputBytes > 4 * 1024 * 1024) {
                throw new IllegalArgumentException("invalid input limit");
            }
            this.toolId = toolId;
            this.version = version;
            this.artifactSha256 = artifactSha256;
            this.origin = origin;
            this.compatibility = compatibility;
            this.maxRuntimeMs = maxRuntimeMs;
            this.maxInputBytes = maxInputBytes;
        }

        private static List<String> safeNames(List<String> input, String label) {
            if (input == null || input.isEmpty() || input.size() > 32) {
                throw new IllegalArgumentException("invalid " + label + " list");
            }
            List<String> copy = new ArrayList<>();
            for (String value : input) {
                if (value == null || !value.matches("[a-zA-Z0-9._-]{1,64}")) {
                    throw new IllegalArgumentException("invalid " + label);
                }
                if (copy.contains(value)) {
                    throw new IllegalArgumentException("duplicate " + label);
                }
                copy.add(value);
            }
            return Collections.unmodifiableList(copy);
        }
    }

    public static final class Event {
        public final String eventId;
        public final int sequence;
        public final long createdAtEpochMs;
        public final String action;
        public final String toolId;
        public final String version;
        public final String fromVersion;
        public final String toVersion;
        public final List<String> evidenceRunIds;
        public final String approvalSha256;

        private Event(String eventId, int sequence, long createdAtEpochMs, String action,
                String toolId, String version, String fromVersion, String toVersion,
                List<String> evidenceRunIds, List<String> regressionComparisonIds,\n                String approvalSha256) {
            this.eventId = eventId;
            this.sequence = sequence;
            this.createdAtEpochMs = createdAtEpochMs;
            this.action = action;
            this.toolId = toolId;
            this.version = version;
            this.fromVersion = fromVersion;
            this.toVersion = toVersion;
            this.evidenceRunIds = Collections.unmodifiableList(
                new ArrayList<>(evidenceRunIds));
            this.approvalSha256 = approvalSha256;
        }
    }

    private final File appFilesDirectory;
    private final String projectId;
    private final Path registryRoot;

    public LaboratoryToolRegistry(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null) throw new IllegalArgumentException("app directory missing");
        if (projectId == null || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid laboratory project id");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path laboratoryRoot = appRoot.resolve("laboratory");
        Path projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        this.registryRoot = projectRoot.resolve("tool-registry");
    }

    public synchronized void registerExperimental(Descriptor descriptor) throws IOException {
        if (descriptor == null) throw new IllegalArgumentException("tool descriptor missing");
        Path toolRoot = prepareTool(descriptor.toolId);
        Path versions = toolRoot.resolve("versions");
        if (countJson(versions) >= MAX_VERSIONS_PER_TOOL) {
            throw new IOException("tool version limit reached; existing versions were preserved");
        }
        Path destination = versions.resolve(descriptor.version + ".json");
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("tool version already registered");
        }
        try {
            JSONObject json = descriptorJson(descriptor);
            json.put("registeredAtEpochMs", System.currentTimeMillis());
            json.put("initialStage", Stage.EXPERIMENTAL.name());
            writeCreateOnly(destination, json, MAX_DESCRIPTOR_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode tool descriptor", error);
        }
    }

    public synchronized void qualifyCandidate(String toolId, String version,
            List<String> evidenceRunIds) throws IOException {
        Descriptor descriptor = readDescriptor(toolId, version);
        Stage stage = stage(toolId, version);
        if (stage != Stage.EXPERIMENTAL) {
            throw new IOException("only an experimental tool can become candidate");
        }
        List<String> evidence = validateEvidence(descriptor, evidenceRunIds);
        writeEvent(toolId, "QUALIFY_CANDIDATE", version, "", version,
            evidence, Collections.emptyList(), "");
    }

    public synchronized void activateStable(String toolId, String version,
            List<String> evidenceRunIds, String approvalId, ApprovalGate gate)
            throws IOException {
        Descriptor descriptor = readDescriptor(toolId, version);
        Stage stage = stage(toolId, version);
        if (stage != Stage.CANDIDATE) {
            throw new IOException("only a candidate tool can be promoted to stable");
        }
        List<String> evidence = validateEvidence(descriptor, evidenceRunIds);
        String current = activeStableVersion(toolId);
        requireApproval(gate, "ACTIVATE_STABLE", toolId, current, version, approvalId);
        writeEvent(toolId, "ACTIVATE_STABLE", version, current, version,
            evidence, Collections.emptyList(), sha256(approvalId));
    }

    public synchronized void rollbackStable(String toolId, String targetVersion,
            String approvalId, ApprovalGate gate) throws IOException {
        Descriptor target = readDescriptor(toolId, targetVersion);
        if (stage(toolId, targetVersion) != Stage.STABLE) {
            throw new IOException("rollback target was never approved as stable");
        }
        String current = activeStableVersion(toolId);
        if (current.isEmpty()) throw new IOException("no active stable version");
        if (current.equals(targetVersion)) throw new IOException("rollback target is already active");
        requireApproval(gate, "ROLLBACK_STABLE", toolId, current, targetVersion, approvalId);
        writeEvent(toolId, "ROLLBACK_STABLE", target.version, current, targetVersion,
            Collections.emptyList(), Collections.emptyList(), sha256(approvalId));
    }

    public synchronized Stage stage(String toolId, String version) throws IOException {
        readDescriptor(toolId, version);
        Stage result = Stage.EXPERIMENTAL;
        for (Event event : history(toolId)) {
            if ("QUALIFY_CANDIDATE".equals(event.action) && version.equals(event.version)) {
                result = Stage.CANDIDATE;
            } else if (("ACTIVATE_STABLE".equals(event.action)
                    || "ROLLBACK_STABLE".equals(event.action))
                    && version.equals(event.toVersion)) {
                result = Stage.STABLE;
            }
        }
        return result;
    }

    public synchronized Descriptor activeStable(String toolId) throws IOException {
        String version = activeStableVersion(toolId);
        return version.isEmpty() ? null : readDescriptor(toolId, version);
    }

    public synchronized List<Event> history(String toolId) throws IOException {
        validateToolId(toolId);
        Path toolRoot = prepareTool(toolId);
        Path history = toolRoot.resolve("history");
        List<Event> events = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(history)) {
            stream.filter(path -> isEventFile(path.getFileName().toString()))
                .limit(MAX_EVENTS_PER_TOOL + 1L)
                .forEach(path -> {
                    try {
                        events.add(parseEvent(readSafe(path, MAX_EVENT_BYTES)));
                    } catch (Exception error) {
                        throw new EventReadFailure(error);
                    }
                });
        } catch (EventReadFailure wrapped) {
            throw new IOException("could not read tool history", wrapped.getCause());
        }
        if (events.size() > MAX_EVENTS_PER_TOOL) {
            throw new IOException("tool history exceeds limit");
        }
        events.sort(Comparator.comparingInt(event -> event.sequence));
        return Collections.unmodifiableList(events);
    }

    public synchronized Descriptor readDescriptor(String toolId, String version)
            throws IOException {
        validateToolId(toolId);
        validateVersion(version);
        Path toolRoot = prepareTool(toolId);
        Path path = toolRoot.resolve("versions").resolve(version + ".json");
        try {
            JSONObject json = new JSONObject(readSafe(path, MAX_DESCRIPTOR_BYTES));
            if (!toolId.equals(json.getString("toolId"))
                    || !version.equals(json.getString("version"))) {
                throw new IOException("tool descriptor identity mismatch");
            }
            return descriptorFromJson(json);
        } catch (JSONException error) {
            throw new IOException("invalid tool descriptor", error);
        }
    }

    private String activeStableVersion(String toolId) throws IOException {
        String active = "";
        for (Event event : history(toolId)) {
            if ("ACTIVATE_STABLE".equals(event.action)
                    || "ROLLBACK_STABLE".equals(event.action)) {
                active = event.toVersion;
            }
        }
        return active;
    }

    private List<String> validateEvidence(Descriptor descriptor, List<String> runIds)
            throws IOException {
        if (runIds == null || runIds.isEmpty() || runIds.size() > 32) {
            throw new IOException("stable lifecycle transition requires test evidence");
        }
        List<String> result = new ArrayList<>();
        List<String> coveredRequiredTests = new ArrayList<>();
        LaboratoryReportStore reports =
            new LaboratoryReportStore(appFilesDirectory, projectId);
        for (String runId : runIds) {
            if (runId == null || result.contains(runId)) {
                throw new IOException("invalid or duplicate evidence run");
            }
            String raw = reports.read(runId);
            try {
                JSONObject report = new JSONObject(raw);
                if (!"PASS".equals(report.getString("status"))) {
                    throw new IOException("evidence run did not pass");
                }
                JSONArray checks = report.getJSONArray("checks");
                boolean artifactCovered = false;
                for (int i = 0; i < checks.length(); i++) {
                    JSONObject check = checks.getJSONObject(i);
                    if (check.optBoolean("passed")
                            && descriptor.artifactSha256.equals(
                                check.optString("inputSha256"))) {
                        artifactCovered = true;
                        String checkName = check.optString("name");
                        if (descriptor.requiredTests.contains(checkName)
                                && !coveredRequiredTests.contains(checkName)) {
                            coveredRequiredTests.add(checkName);
                        }
                    }
                }
                if (!artifactCovered) {
                    throw new IOException("evidence does not cover registered artifact hash");
                }
            } catch (JSONException error) {
                throw new IOException("invalid evidence report", error);
            }
            result.add(runId);
        }
        if (!coveredRequiredTests.containsAll(descriptor.requiredTests)) {
            throw new IOException("required tool tests are missing from evidence");
        }
        return Collections.unmodifiableList(result);
    }

    private void requireApproval(ApprovalGate gate, String action, String toolId,
            String fromVersion, String toVersion, String approvalId) {
        if (gate == null || approvalId == null || approvalId.isEmpty()
                || approvalId.length() > 128
                || !gate.isApproved(action, toolId, fromVersion, toVersion, approvalId)) {
            throw new SecurityException("explicit user approval required");
        }
    }

    private void writeEvent(String toolId, String action, String version,
            String fromVersion, String toVersion, List<String> evidence,
            List<String> regressionComparisonIds, String approvalSha256) throws IOException {
        Path toolRoot = prepareTool(toolId);
        Path history = toolRoot.resolve("history");
        if (countJson(history) >= MAX_EVENTS_PER_TOOL) {
            throw new IOException("tool history limit reached; existing history was preserved");
        }
        int sequence = 1;
        List<Event> existing = history(toolId);
        if (!existing.isEmpty()) {
            sequence = existing.get(existing.size() - 1).sequence + 1;
        }
        if (sequence > MAX_EVENTS_PER_TOOL) {
            throw new IOException("tool history limit reached; existing history was preserved");
        }
        long created = System.currentTimeMillis();
        String eventId = UUID.randomUUID().toString();
        String fileName = String.format(Locale.ROOT, "%06d.json", sequence);
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("eventId", eventId);
            json.put("sequence", sequence);
            json.put("createdAtEpochMs", created);
            json.put("action", action);
            json.put("toolId", toolId);
            json.put("version", version);
            json.put("fromVersion", fromVersion);
            json.put("toVersion", toVersion);
            json.put("evidenceRunIds", new JSONArray(evidence));
            if (!regressionComparisonIds.isEmpty()) {
                json.put("regressionComparisonIds", new JSONArray(regressionComparisonIds));
            }
            if (!approvalSha256.isEmpty()) json.put("approvalSha256", approvalSha256);
            writeCreateOnly(history.resolve(fileName), json, MAX_EVENT_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode tool history event", error);
        }
    }

    private Path prepareTool(String toolId) throws IOException {
        validateToolId(toolId);
        ensureSafeDirectory(registryRoot.getParent().getParent());
        ensureSafeDirectory(registryRoot.getParent());
        ensureSafeDirectory(registryRoot);
        Path toolRoot = registryRoot.resolve(toolId);
        ensureSafeDirectory(toolRoot);
        ensureSafeDirectory(toolRoot.resolve("versions"));
        ensureSafeDirectory(toolRoot.resolve("history"));
        return toolRoot;
    }

    private static JSONObject descriptorJson(Descriptor descriptor) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("schemaVersion", 1);
        json.put("toolId", descriptor.toolId);
        json.put("version", descriptor.version);
        json.put("artifactSha256", descriptor.artifactSha256);
        json.put("origin", descriptor.origin);
        json.put("capabilities", new JSONArray(descriptor.capabilities));
        json.put("requiredTests", new JSONArray(descriptor.requiredTests));
        json.put("compatibility", descriptor.compatibility);
        json.put("maxRuntimeMs", descriptor.maxRuntimeMs);
        json.put("maxInputBytes", descriptor.maxInputBytes);
        return json;
    }

    private static Descriptor descriptorFromJson(JSONObject json) throws JSONException {
        return new Descriptor(
            json.getString("toolId"),
            json.getString("version"),
            json.getString("artifactSha256"),
            json.getString("origin"),
            strings(json.getJSONArray("capabilities")),
            strings(json.getJSONArray("requiredTests")),
            json.getString("compatibility"),
            json.getInt("maxRuntimeMs"),
            json.getInt("maxInputBytes"));
    }

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) values.add(array.getString(i));
        return values;
    }

    private static Event parseEvent(String raw) throws JSONException {
        JSONObject json = new JSONObject(raw);
        return new Event(
            json.getString("eventId"),
            json.getInt("sequence"),
            json.getLong("createdAtEpochMs"),
            json.getString("action"),
            json.getString("toolId"),
            json.getString("version"),
            json.optString("fromVersion"),
            json.optString("toVersion"),
            strings(json.getJSONArray("evidenceRunIds")),
            json.has("regressionComparisonIds")
                ? strings(json.getJSONArray("regressionComparisonIds"))
                : Collections.emptyList(),
            json.optString("approvalSha256"));
    }

    private static void writeCreateOnly(Path destination, JSONObject json, int maxBytes)
            throws IOException, JSONException {
        if (!destination.getParent().equals(destination.toAbsolutePath().normalize().getParent())) {
            throw new IOException("unsafe tool registry path");
        }
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("tool registry record already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > maxBytes) throw new IOException("tool registry record too large");

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
                throw new IOException("tool registry record already exists");
            }
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temporary, destination);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private static String readSafe(Path path, int maxBytes) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path) || Files.size(path) > maxBytes) {
            throw new IOException("tool registry record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static int countJson(Path directory) throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(directory)) {
            return (int) stream.filter(path ->
                path.getFileName().toString().endsWith(".json"))
                .count();
        }
    }

    private static boolean isEventFile(String name) {
        return name != null && name.matches("[0-9]{6}\\.json");
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below; never follow a link created concurrently.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe tool registry directory");
        }
    }

    private static void validateToolId(String toolId) {
        if (toolId == null || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")) {
            throw new IllegalArgumentException("invalid tool id");
        }
    }

    private static void validateVersion(String version) {
        if (version == null
                || !version.matches("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]{1,32})?")) {
            throw new IllegalArgumentException("invalid semantic tool version");
        }
    }

    private static void validateSha256(String sha256) {
        if (sha256 == null || !sha256.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("invalid artifact sha256");
        }
    }

    private static String sha256(String value) {
        try {
            java.security.MessageDigest digest =
                java.security.MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte b : bytes) {
                hex.append(String.format(Locale.ROOT, "%02x", b & 0xff));
            }
            return hex.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static final class EventReadFailure extends RuntimeException {
        EventReadFailure(Throwable cause) { super(cause); }
    }
}
