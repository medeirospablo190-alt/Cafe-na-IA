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
 * Append-only audit for bounded AI sessions.
 * Raw tool_input and tool outputs are never persisted here.
 */
public final class LaboratoryAiSessionStore {
    public static final int MAX_SESSIONS = 64;
    public static final int MAX_EVENTS_PER_SESSION = 256;
    public static final int MAX_MANIFEST_BYTES = 16 * 1024;
    public static final int MAX_EVENT_BYTES = 12 * 1024;

    public static final String START = "START";
    public static final String INVOKE_REQUEST = "INVOKE_REQUEST";
    public static final String INVOKE_RESULT = "INVOKE_RESULT";
    public static final String PAUSE = "PAUSE";
    public static final String RESUME = "RESUME";
    public static final String CANCEL = "CANCEL";
    public static final String FINISH = "FINISH";

    public static final class Event {
        public final int sequence;
        public final long createdAtEpochMs;
        public final String type;
        public final String state;
        public final String toolId;
        public final String inputSha256;
        public final int inputBytes;
        public final String runId;
        public final String outcome;
        public final int invocationsUsed;
        public final int inputBytesUsed;

        private Event(int sequence, long createdAtEpochMs, String type,
                String state, String toolId, String inputSha256, int inputBytes,
                String runId, String outcome, int invocationsUsed,
                int inputBytesUsed) {
            this.sequence = sequence;
            this.createdAtEpochMs = createdAtEpochMs;
            this.type = type;
            this.state = state;
            this.toolId = toolId;
            this.inputSha256 = inputSha256;
            this.inputBytes = inputBytes;
            this.runId = runId;
            this.outcome = outcome;
            this.invocationsUsed = invocationsUsed;
            this.inputBytesUsed = inputBytesUsed;
        }
    }

    public static final class Summary {
        public final String sessionId;
        public final long startedAtEpochMs;
        public final List<String> allowedToolIds;
        public final int maxInvocations;
        public final int maxTotalInputBytes;
        public final long maxSessionMs;
        public final String state;
        public final int invocationsUsed;
        public final int inputBytesUsed;
        public final int eventCount;
        public final long lastEventAtEpochMs;

        private Summary(String sessionId, long startedAtEpochMs,
                List<String> allowedToolIds, int maxInvocations,
                int maxTotalInputBytes, long maxSessionMs, String state,
                int invocationsUsed, int inputBytesUsed, int eventCount,
                long lastEventAtEpochMs) {
            this.sessionId = sessionId;
            this.startedAtEpochMs = startedAtEpochMs;
            this.allowedToolIds = Collections.unmodifiableList(
                new ArrayList<>(allowedToolIds));
            this.maxInvocations = maxInvocations;
            this.maxTotalInputBytes = maxTotalInputBytes;
            this.maxSessionMs = maxSessionMs;
            this.state = state;
            this.invocationsUsed = invocationsUsed;
            this.inputBytesUsed = inputBytesUsed;
            this.eventCount = eventCount;
            this.lastEventAtEpochMs = lastEventAtEpochMs;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path sessionRoot;

    public LaboratoryAiSessionStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI session project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        sessionRoot = projectRoot.resolve("ai-sessions");
    }

    public synchronized void begin(String sessionId, long startedAtEpochMs,
            List<String> allowedToolIds, int maxInvocations,
            int maxTotalInputBytes, long maxSessionMs) throws IOException {
        validateSessionId(sessionId);
        validatePolicy(allowedToolIds, maxInvocations, maxTotalInputBytes, maxSessionMs);
        ensureRoot();
        if (countSessions() >= MAX_SESSIONS) {
            throw new IOException("AI session audit limit reached; history was preserved");
        }

        Path directory = sessionRoot.resolve(sessionId);
        if (Files.exists(directory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI session audit already exists");
        }
        Files.createDirectory(directory);
        ensureSafeDirectory(directory);
        Path events = directory.resolve("events");
        Files.createDirectory(events);
        ensureSafeDirectory(events);

        try {
            JSONObject manifest = new JSONObject();
            manifest.put("schemaVersion", 1);
            manifest.put("sessionId", sessionId);
            manifest.put("startedAtEpochMs", startedAtEpochMs);
            manifest.put("allowedToolIds", new JSONArray(allowedToolIds));
            manifest.put("maxInvocations", maxInvocations);
            manifest.put("maxTotalInputBytes", maxTotalInputBytes);
            manifest.put("maxSessionMs", maxSessionMs);
            manifest.put("manifestSha256", manifestSha(
                sessionId, startedAtEpochMs, allowedToolIds, maxInvocations,
                maxTotalInputBytes, maxSessionMs));
            writeNew(directory.resolve("manifest.json"), manifest, MAX_MANIFEST_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode AI session manifest", error);
        }

        append(sessionId, START, "ACTIVE", "", "", 0, "",
            "SESSION_STARTED", 0, 0);
    }

    public synchronized void append(String sessionId, String type, String state,
            String toolId, String inputSha256, int inputBytes, String runId,
            String outcome, int invocationsUsed, int inputBytesUsed)
            throws IOException {
        validateSessionId(sessionId);
        if (!validType(type) || !validState(state)
                || toolId == null || toolId.length() > 64
                || (!toolId.isEmpty()
                    && !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}"))
                || inputSha256 == null
                || (!inputSha256.isEmpty() && !validSha(inputSha256))
                || inputBytes < 0 || inputBytes > 256 * 1024
                || runId == null
                || (!runId.isEmpty() && !validUuid(runId))
                || outcome == null || outcome.length() > 64
                || invocationsUsed < 0 || invocationsUsed > 64
                || inputBytesUsed < 0 || inputBytesUsed > 256 * 1024) {
            throw new IOException("invalid AI session audit event");
        }

        Path directory = requireSessionDirectory(sessionId);
        Path events = directory.resolve("events");
        List<Event> existing = readEventsInternal(events);
        if (existing.size() >= MAX_EVENTS_PER_SESSION) {
            throw new IOException("AI session event limit reached");
        }
        int sequence = existing.size() + 1;
        long created = System.currentTimeMillis();
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("sequence", sequence);
            json.put("createdAtEpochMs", created);
            json.put("type", type);
            json.put("state", state);
            json.put("toolId", toolId);
            if (!inputSha256.isEmpty()) json.put("inputSha256", inputSha256);
            json.put("inputBytes", inputBytes);
            if (!runId.isEmpty()) json.put("runId", runId);
            json.put("outcome", outcome);
            json.put("invocationsUsed", invocationsUsed);
            json.put("inputBytesUsed", inputBytesUsed);
            json.put("recordSha256", eventSha(
                sequence, created, type, state, toolId, inputSha256,
                inputBytes, runId, outcome, invocationsUsed, inputBytesUsed));
            String fileName = String.format(Locale.ROOT, "%06d.json", sequence);
            writeNew(events.resolve(fileName), json, MAX_EVENT_BYTES);
        } catch (JSONException error) {
            throw new IOException("could not encode AI session event", error);
        }
    }

    public synchronized List<Event> readEvents(String sessionId) throws IOException {
        Path directory = requireSessionDirectory(sessionId);
        return Collections.unmodifiableList(
            new ArrayList<>(readEventsInternal(directory.resolve("events"))));
    }

    public synchronized List<Summary> list() throws IOException {
        if (!Files.exists(sessionRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Summary> summaries = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(sessionRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_SESSIONS) {
                throw new IOException("AI session audit exceeds session limit");
            }
            for (Path path : paths) {
                if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected AI session audit entry");
                }
                String sessionId = path.getFileName().toString();
                validateSessionId(sessionId);
                summaries.add(readSummary(path, sessionId));
            }
        }
        summaries.sort(Comparator
            .comparingLong((Summary summary) -> summary.startedAtEpochMs)
            .reversed()
            .thenComparing(summary -> summary.sessionId));
        return Collections.unmodifiableList(summaries);
    }

    private Summary readSummary(Path directory, String sessionId) throws IOException {
        try {
            JSONObject manifest = new JSONObject(
                readSafe(directory.resolve("manifest.json"), MAX_MANIFEST_BYTES));
            String storedHash = manifest.getString("manifestSha256");
            List<String> tools = strings(manifest.getJSONArray("allowedToolIds"));
            int maxInvocations = manifest.getInt("maxInvocations");
            int maxInput = manifest.getInt("maxTotalInputBytes");
            long maxMs = manifest.getLong("maxSessionMs");
            long started = manifest.getLong("startedAtEpochMs");
            validatePolicy(tools, maxInvocations, maxInput, maxMs);
            if (!validSha(storedHash)
                    || !storedHash.equals(manifestSha(
                        sessionId, started, tools, maxInvocations, maxInput, maxMs))
                    || manifest.getInt("schemaVersion") != 1
                    || !sessionId.equals(manifest.getString("sessionId"))) {
                throw new IOException("AI session manifest integrity failed");
            }

            List<Event> events = readEventsInternal(directory.resolve("events"));
            Event last = events.isEmpty() ? null : events.get(events.size() - 1);
            return new Summary(sessionId, started,
                tools, maxInvocations, maxInput, maxMs,
                last == null ? "UNKNOWN" : last.state,
                last == null ? 0 : last.invocationsUsed,
                last == null ? 0 : last.inputBytesUsed,
                events.size(),
                last == null ? 0 : last.createdAtEpochMs);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI session manifest", error);
        }
    }

    private List<Event> readEventsInternal(Path events) throws IOException {
        if (!Files.isDirectory(events, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(events)) {
            throw new IOException("AI session events directory missing or unsafe");
        }
        List<Event> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(events)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_EVENTS_PER_SESSION) {
                throw new IOException("AI session event history exceeds limit");
            }
            paths.sort(Comparator.comparing(path -> path.getFileName().toString()));
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.matches("[0-9]{6}\\.json")) {
                    throw new IOException("unexpected AI session event record");
                }
                try {
                    JSONObject json = new JSONObject(readSafe(path, MAX_EVENT_BYTES));
                    String storedHash = json.getString("recordSha256");
                    Event event = new Event(
                        json.getInt("sequence"),
                        json.getLong("createdAtEpochMs"),
                        json.getString("type"),
                        json.getString("state"),
                        json.optString("toolId"),
                        json.optString("inputSha256"),
                        json.getInt("inputBytes"),
                        json.optString("runId"),
                        json.getString("outcome"),
                        json.getInt("invocationsUsed"),
                        json.getInt("inputBytesUsed"));
                    if (!validSha(storedHash)
                            || !storedHash.equals(eventSha(
                                event.sequence, event.createdAtEpochMs,
                                event.type, event.state, event.toolId,
                                event.inputSha256, event.inputBytes, event.runId,
                                event.outcome, event.invocationsUsed,
                                event.inputBytesUsed))
                            || json.getInt("schemaVersion") != 1) {
                        throw new IOException("AI session event integrity failed");
                    }
                    if (event.sequence != result.size() + 1
                            || event.createdAtEpochMs <= 0
                            || !validType(event.type)
                            || !validState(event.state)
                            || event.toolId == null || event.toolId.length() > 64
                            || (!event.toolId.isEmpty()
                                && !event.toolId.matches("[a-z0-9][a-z0-9._-]{0,63}"))
                            || event.inputSha256 == null
                            || (!event.inputSha256.isEmpty()
                                && !validSha(event.inputSha256))
                            || event.inputBytes < 0
                            || event.inputBytes > 256 * 1024
                            || event.runId == null
                            || (!event.runId.isEmpty() && !validUuid(event.runId))
                            || event.outcome == null || event.outcome.length() > 64
                            || event.invocationsUsed < 0
                            || event.invocationsUsed > 64
                            || event.inputBytesUsed < 0
                            || event.inputBytesUsed > 256 * 1024) {
                        throw new IOException("AI session event failed validation");
                    }
                    result.add(event);
                } catch (JSONException error) {
                    throw new IOException("invalid AI session event", error);
                }
            }
        }
        return result;
    }

    private Path requireSessionDirectory(String sessionId) throws IOException {
        ensureRoot();
        Path directory = sessionRoot.resolve(sessionId);
        if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(directory)) {
            throw new IOException("AI session audit not found or unsafe");
        }
        Path events = directory.resolve("events");
        if (!Files.isDirectory(events, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(events)) {
            throw new IOException("AI session events directory missing or unsafe");
        }
        return directory;
    }

    private void ensureRoot() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(sessionRoot);
    }

    private int countSessions() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(sessionRoot)) {
            return (int) stream
                .filter(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS))
                .limit(MAX_SESSIONS + 1L).count();
        }
    }

    private static void validatePolicy(List<String> tools, int maxInvocations,
            int maxInput, long maxMs) {
        if (tools == null || tools.isEmpty() || tools.size() > 32
                || maxInvocations < 1 || maxInvocations > 64
                || maxInput < 1 || maxInput > 256 * 1024
                || maxMs < 1_000L || maxMs > 60L * 60L * 1000L) {
            throw new IllegalArgumentException("invalid AI session audit policy");
        }
        List<String> seen = new ArrayList<>();
        for (String tool : tools) {
            if (tool == null || !tool.matches("[a-z0-9][a-z0-9._-]{0,63}")
                    || seen.contains(tool)) {
                throw new IllegalArgumentException("invalid AI session audit tool");
            }
            seen.add(tool);
        }
    }

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) values.add(array.getString(i));
        return values;
    }

    private static String readSafe(Path path, int maxBytes) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > maxBytes) {
            throw new IOException("AI session audit record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json, int maxBytes)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI session audit record already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > maxBytes) {
            throw new IOException("AI session audit record exceeds size budget");
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
            throw new IOException("unsafe AI session audit directory");
        }
    }

    private static String manifestSha(String sessionId, long started,
            List<String> tools, int maxInvocations, int maxInput, long maxMs) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, sessionId);
        field(canonical, Long.toString(started));
        list(canonical, tools);
        field(canonical, Integer.toString(maxInvocations));
        field(canonical, Integer.toString(maxInput));
        field(canonical, Long.toString(maxMs));
        return sha256(canonical.toString());
    }

    private static String eventSha(int sequence, long created, String type,
            String state, String toolId, String inputSha, int inputBytes,
            String runId, String outcome, int invocationsUsed, int inputBytesUsed) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, Integer.toString(sequence));
        field(canonical, Long.toString(created));
        field(canonical, type);
        field(canonical, state);
        field(canonical, toolId);
        field(canonical, inputSha);
        field(canonical, Integer.toString(inputBytes));
        field(canonical, runId);
        field(canonical, outcome);
        field(canonical, Integer.toString(invocationsUsed));
        field(canonical, Integer.toString(inputBytesUsed));
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

    private static boolean validType(String value) {
        return START.equals(value) || INVOKE_REQUEST.equals(value)
            || INVOKE_RESULT.equals(value) || PAUSE.equals(value)
            || RESUME.equals(value) || CANCEL.equals(value)
            || FINISH.equals(value);
    }

    private static boolean validState(String value) {
        return "ACTIVE".equals(value) || "PAUSED".equals(value)
            || "CANCELLED".equals(value) || "FINISHED".equals(value);
    }

    private static void validateSessionId(String value) {
        if (!validUuid(value)) throw new IllegalArgumentException("invalid AI session id");
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
