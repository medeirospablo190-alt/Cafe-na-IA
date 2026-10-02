package com.cafeina.executor;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/**
 * Bounded, create-only history for local planner execution status events.
 *
 * The store records execution metadata only. It never stores the Goal Lock
 * text, prompt, model output, tool input, stdout, or executable source.
 */
public final class LaboratoryAiExecutionHistoryStore {
    public static final int MAX_EXECUTIONS = 128;
    public static final int MAX_EVENTS_PER_EXECUTION = 64;
    public static final int MAX_EVENT_BYTES = 8 * 1024;

    public static final class Event {
        public final int sequence;
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
        public final String terminalReason;

        private Event(
                int sequence,
                String executionId,
                String contractId,
                long startedAtEpochMs,
                long updatedAtEpochMs,
                long elapsedMs,
                LaboratoryAiExecutionStatus.State state,
                LaboratoryAiExecutionStatus.Phase phase,
                String detail,
                int attempt,
                int maxAttempts,
                String terminalReason) {
            this.sequence = sequence;
            this.executionId = executionId;
            this.contractId = contractId;
            this.startedAtEpochMs = startedAtEpochMs;
            this.updatedAtEpochMs = updatedAtEpochMs;
            this.elapsedMs = elapsedMs;
            this.state = state;
            this.phase = phase;
            this.detail = detail;
            this.attempt = attempt;
            this.maxAttempts = maxAttempts;
            this.terminalReason = terminalReason;
        }

        public boolean terminal() {
            return state != LaboratoryAiExecutionStatus.State.RUNNING;
        }
    }

    public static final class Summary {
        public final String executionId;
        public final String contractId;
        public final long startedAtEpochMs;
        public final long updatedAtEpochMs;
        public final long elapsedMs;
        public final LaboratoryAiExecutionStatus.State state;
        public final LaboratoryAiExecutionStatus.Phase phase;
        public final int attempt;
        public final int maxAttempts;
        public final int eventCount;
        public final String terminalReason;

        private Summary(Event last, int eventCount) {
            executionId = last.executionId;
            contractId = last.contractId;
            startedAtEpochMs = last.startedAtEpochMs;
            updatedAtEpochMs = last.updatedAtEpochMs;
            elapsedMs = last.elapsedMs;
            state = last.state;
            phase = last.phase;
            attempt = last.attempt;
            maxAttempts = last.maxAttempts;
            this.eventCount = eventCount;
            terminalReason = last.terminalReason;
        }
    }

    private final Path historyRoot;

    public LaboratoryAiExecutionHistoryStore(
            File appFilesDirectory,
            String projectId) {
        if (appFilesDirectory == null
                || projectId == null
                || (!projectId.isEmpty()
                    && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException(
                "invalid execution history project");
        }

        Path appRoot = appFilesDirectory.toPath()
            .toAbsolutePath()
            .normalize();
        Path laboratoryRoot = appRoot.resolve("laboratory");
        Path projectRoot = laboratoryRoot.resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        historyRoot = projectRoot.resolve("ai-execution-history");
    }

    public synchronized void append(
            LaboratoryAiExecutionStatus.Snapshot snapshot)
            throws IOException {
        validateSnapshot(snapshot);
        prepareRoot();

        Path executionRoot = resolveExecutionRoot(snapshot.executionId);
        boolean newExecution =
            !Files.exists(executionRoot, LinkOption.NOFOLLOW_LINKS);

        if (newExecution) {
            if (countExecutionDirectories() >= MAX_EXECUTIONS) {
                throw new IOException(
                    "execution history limit reached; history preserved");
            }
            Files.createDirectory(executionRoot);
        } else {
            requireSafeDirectory(executionRoot, "execution history");
        }

        List<Event> existing = readEventsInternal(
            snapshot.executionId,
            executionRoot,
            true);
        if (existing.size() >= MAX_EVENTS_PER_EXECUTION) {
            throw new IOException(
                "execution event limit reached; history preserved");
        }

        if (!existing.isEmpty()) {
            Event last = existing.get(existing.size() - 1);
            if (!last.contractId.equals(snapshot.contractId)
                    || last.startedAtEpochMs != snapshot.startedAtEpochMs) {
                throw new IOException(
                    "execution identity changed during history append");
            }
            if (last.terminal()) {
                throw new IOException(
                    "terminal execution history cannot be extended");
            }
            if (snapshot.updatedAtEpochMs < last.updatedAtEpochMs
                    || snapshot.elapsedMs < last.elapsedMs) {
                throw new IOException(
                    "execution history time moved backwards");
            }
        }

        int sequence = existing.size() + 1;
        byte[] encoded = encode(sequence, snapshot)
            .toString()
            .getBytes(StandardCharsets.UTF_8);
        if (encoded.length > MAX_EVENT_BYTES) {
            throw new IOException("execution status event exceeds size limit");
        }

        Path target = executionRoot.resolve(fileName(sequence)).normalize();
        if (!executionRoot.equals(target.getParent())) {
            throw new IOException("execution history path escaped root");
        }
        Files.write(
            target,
            encoded,
            StandardOpenOption.CREATE_NEW,
            StandardOpenOption.WRITE);
    }

    public synchronized void saveExecution(
            List<LaboratoryAiExecutionStatus.Snapshot> snapshots)
            throws IOException {
        if (snapshots == null
                || snapshots.isEmpty()
                || snapshots.size() > MAX_EVENTS_PER_EXECUTION) {
            throw new IOException("invalid execution history snapshot list");
        }

        LaboratoryAiExecutionStatus.Snapshot first = snapshots.get(0);
        validateSnapshot(first);
        for (LaboratoryAiExecutionStatus.Snapshot snapshot : snapshots) {
            validateSnapshot(snapshot);
            if (!first.executionId.equals(snapshot.executionId)
                    || !first.contractId.equals(snapshot.contractId)
                    || first.startedAtEpochMs != snapshot.startedAtEpochMs) {
                throw new IOException(
                    "execution history snapshot identity mismatch");
            }
        }
        if (!snapshots.get(snapshots.size() - 1).terminal()) {
            throw new IOException(
                "only terminal executions may be persisted");
        }

        prepareRoot();
        Path executionRoot = resolveExecutionRoot(first.executionId);
        List<Event> existing = Files.exists(
                executionRoot, LinkOption.NOFOLLOW_LINKS)
            ? readEventsInternal(first.executionId, executionRoot, true)
            : Collections.emptyList();

        if (existing.size() > snapshots.size()) {
            throw new IOException(
                "persisted execution history is longer than source history");
        }
        for (int i = 0; i < existing.size(); i++) {
            if (!same(existing.get(i), snapshots.get(i))) {
                throw new IOException(
                    "persisted execution history prefix mismatch");
            }
        }
        if (!existing.isEmpty()
                && existing.get(existing.size() - 1).terminal()) {
            if (existing.size() == snapshots.size()) return;
            throw new IOException(
                "terminal execution history cannot be extended");
        }

        for (int i = existing.size(); i < snapshots.size(); i++) {
            append(snapshots.get(i));
        }
    }

    public synchronized List<Summary> list() throws IOException {
        if (!Files.exists(historyRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        prepareRoot();

        List<Summary> result = new ArrayList<>();
        List<Path> roots = listExecutionDirectories();
        for (Path executionRoot : roots) {
            String executionId = executionRoot.getFileName().toString();
            List<Event> events =
                readEventsInternal(executionId, executionRoot, true);
            if (events.isEmpty()) {
                throw new IOException("execution history contains no events");
            }
            result.add(new Summary(
                events.get(events.size() - 1),
                events.size()));
        }

        result.sort(Comparator
            .comparingLong((Summary value) -> value.startedAtEpochMs)
            .reversed()
            .thenComparing(value -> value.executionId));
        return Collections.unmodifiableList(result);
    }

    public synchronized List<Event> readEvents(String executionId)
            throws IOException {
        validateUuid(executionId);
        prepareRoot();
        Path executionRoot = resolveExecutionRoot(executionId);
        requireSafeDirectory(executionRoot, "execution history");
        return Collections.unmodifiableList(
            readEventsInternal(executionId, executionRoot, true));
    }

    private List<Event> readEventsInternal(
            String executionId,
            Path executionRoot,
            boolean requireContiguous)
            throws IOException {
        if (!Files.exists(executionRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireSafeDirectory(executionRoot, "execution history");

        List<Path> paths = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream =
                Files.list(executionRoot)) {
            stream.forEach(paths::add);
        }
        if (paths.size() > MAX_EVENTS_PER_EXECUTION) {
            throw new IOException("execution event directory exceeds limit");
        }
        paths.sort(Comparator.comparing(
            path -> path.getFileName().toString()));

        List<Event> events = new ArrayList<>();
        int expectedSequence = 1;
        String contractId = null;
        long startedAt = -1L;
        Event previous = null;
        for (Path path : paths) {
            if (Files.isSymbolicLink(path)
                    || !Files.isRegularFile(
                        path, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException(
                    "unsafe execution history entry");
            }

            String name = path.getFileName().toString();
            if (!name.matches("[0-9]{6}\\.json")) {
                throw new IOException(
                    "unexpected execution history entry");
            }
            int sequence = Integer.parseInt(
                name.substring(0, 6));
            if (requireContiguous && sequence != expectedSequence) {
                throw new IOException(
                    "execution history sequence is not contiguous");
            }
            Event event = parse(
                executionId,
                sequence,
                readLimited(path));
            if (contractId == null) {
                contractId = event.contractId;
                startedAt = event.startedAtEpochMs;
            } else if (!contractId.equals(event.contractId)
                    || startedAt != event.startedAtEpochMs) {
                throw new IOException(
                    "execution history identity mismatch");
            }

            if (previous != null) {
                if (previous.terminal()) {
                    throw new IOException(
                        "execution history extends terminal state");
                }
                if (event.updatedAtEpochMs
                        < previous.updatedAtEpochMs
                        || event.elapsedMs < previous.elapsedMs) {
                    throw new IOException(
                        "execution history time moved backwards");
                }
            }

            events.add(event);
            previous = event;
            expectedSequence = sequence + 1;
        }
        return events;
    }

    private JSONObject encode(
            int sequence,
            LaboratoryAiExecutionStatus.Snapshot snapshot)
            throws IOException {
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("sequence", sequence);
            json.put("executionId", snapshot.executionId);
            json.put("contractId", snapshot.contractId);
            json.put("startedAtEpochMs", snapshot.startedAtEpochMs);
            json.put("updatedAtEpochMs", snapshot.updatedAtEpochMs);
            json.put("elapsedMs", snapshot.elapsedMs);
            json.put("state", snapshot.state.name());
            json.put("phase", snapshot.phase.name());
            json.put("detail", snapshot.detail);
            json.put("attempt", snapshot.attempt);
            json.put("maxAttempts", snapshot.maxAttempts);
            json.put("terminalReason", snapshot.terminalReason);
            return json;
        } catch (JSONException error) {
            throw new IOException(
                "could not encode execution history event", error);
        }
    }

    private Event parse(
            String expectedExecutionId,
            int expectedSequence,
            String raw) throws IOException {
        try {
            JSONObject json = new JSONObject(raw);
            int sequence = json.getInt("sequence");
            String executionId = json.getString("executionId");
            String contractId = json.getString("contractId");
            long started = json.getLong("startedAtEpochMs");
            long updated = json.getLong("updatedAtEpochMs");
            long elapsed = json.getLong("elapsedMs");
            int attempt = json.getInt("attempt");
            int maxAttempts = json.getInt("maxAttempts");
            String detail = json.optString("detail");
            String terminalReason =
                json.optString("terminalReason");

            if (json.getInt("schemaVersion") != 1
                    || sequence != expectedSequence
                    || !expectedExecutionId.equals(executionId)
                    || !validUuid(executionId)
                    || !validUuid(contractId)
                    || started <= 0L
                    || updated < started
                    || elapsed != Math.max(0L, updated - started)
                    || attempt < 0
                    || maxAttempts < 0
                    || attempt > maxAttempts
                    || (attempt > 0 && maxAttempts == 0)
                    || detail.length() > 240
                    || terminalReason.length() > 240) {
                throw new IOException(
                    "execution history event failed validation");
            }

            LaboratoryAiExecutionStatus.State state =
                LaboratoryAiExecutionStatus.State.valueOf(
                    json.getString("state"));
            LaboratoryAiExecutionStatus.Phase phase =
                LaboratoryAiExecutionStatus.Phase.valueOf(
                    json.getString("phase"));

            if (state
                    == LaboratoryAiExecutionStatus.State.COMPLETED
                    && phase
                    != LaboratoryAiExecutionStatus.Phase.COMPLETED) {
                throw new IOException(
                    "completed execution has invalid phase");
            }
            if (state
                    == LaboratoryAiExecutionStatus.State.RUNNING
                    && phase
                    == LaboratoryAiExecutionStatus.Phase.COMPLETED) {
                throw new IOException(
                    "running execution has terminal phase");
            }

            return new Event(
                sequence,
                executionId,
                contractId,
                started,
                updated,
                elapsed,
                state,
                phase,
                detail,
                attempt,
                maxAttempts,
                terminalReason);
        } catch (JSONException
                | IllegalArgumentException error) {
            throw new IOException(
                "invalid execution history event", error);
        }
    }

    private static boolean same(
            Event event,
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        return event.executionId.equals(snapshot.executionId)
            && event.contractId.equals(snapshot.contractId)
            && event.startedAtEpochMs == snapshot.startedAtEpochMs
            && event.updatedAtEpochMs == snapshot.updatedAtEpochMs
            && event.elapsedMs == snapshot.elapsedMs
            && event.state == snapshot.state
            && event.phase == snapshot.phase
            && event.detail.equals(snapshot.detail)
            && event.attempt == snapshot.attempt
            && event.maxAttempts == snapshot.maxAttempts
            && event.terminalReason.equals(snapshot.terminalReason);
    }

    private void validateSnapshot(
            LaboratoryAiExecutionStatus.Snapshot snapshot)
            throws IOException {
        if (snapshot == null
                || !validUuid(snapshot.executionId)
                || !validUuid(snapshot.contractId)
                || snapshot.startedAtEpochMs <= 0L
                || snapshot.updatedAtEpochMs
                    < snapshot.startedAtEpochMs
                || snapshot.elapsedMs != Math.max(
                    0L,
                    snapshot.updatedAtEpochMs
                        - snapshot.startedAtEpochMs)
                || snapshot.state == null
                || snapshot.phase == null
                || snapshot.detail == null
                || snapshot.detail.length() > 240
                || snapshot.terminalReason == null
                || snapshot.terminalReason.length() > 240
                || snapshot.attempt < 0
                || snapshot.maxAttempts < 0
                || snapshot.attempt > snapshot.maxAttempts
                || (snapshot.attempt > 0
                    && snapshot.maxAttempts == 0)) {
            throw new IOException(
                "invalid execution status snapshot");
        }
    }

    private void prepareRoot() throws IOException {
        Path projectRoot = historyRoot.getParent();
        Path laboratoryRoot = projectRoot.getParent();

        Files.createDirectories(laboratoryRoot);
        requireSafeDirectory(laboratoryRoot, "laboratory");

        Files.createDirectories(projectRoot);
        requireSafeDirectory(projectRoot, "laboratory project");

        Files.createDirectories(historyRoot);
        requireSafeDirectory(historyRoot, "execution history root");
    }

    private int countExecutionDirectories() throws IOException {
        return listExecutionDirectories().size();
    }

    private List<Path> listExecutionDirectories() throws IOException {
        List<Path> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream =
                Files.list(historyRoot)) {
            stream.forEach(result::add);
        }
        if (result.size() > MAX_EXECUTIONS) {
            throw new IOException(
                "execution history directory exceeds limit");
        }

        for (Path path : result) {
            if (Files.isSymbolicLink(path)
                    || !Files.isDirectory(
                        path, LinkOption.NOFOLLOW_LINKS)
                    || !validUuid(
                        path.getFileName().toString())) {
                throw new IOException(
                    "unexpected execution history directory");
            }
        }
        return result;
    }

    private Path resolveExecutionRoot(String executionId)
            throws IOException {
        validateUuid(executionId);
        Path path = historyRoot.resolve(executionId).normalize();
        if (!historyRoot.equals(path.getParent())) {
            throw new IOException(
                "execution history path escaped root");
        }
        return path;
    }

    private String readLimited(Path path) throws IOException {
        long size = Files.size(path);
        if (size < 1L || size > MAX_EVENT_BYTES) {
            throw new IOException(
                "execution history event has invalid size");
        }
        byte[] data = Files.readAllBytes(path);
        if (data.length != size
                || data.length > MAX_EVENT_BYTES) {
            throw new IOException(
                "execution history event size changed");
        }
        return new String(data, StandardCharsets.UTF_8);
    }

    private static String fileName(int sequence) {
        return String.format(
            java.util.Locale.ROOT,
            "%06d.json",
            sequence);
    }

    private static void requireSafeDirectory(
            Path path,
            String label) throws IOException {
        if (Files.isSymbolicLink(path)
                || !Files.isDirectory(
                    path, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(label + " is not a safe directory");
        }
    }

    private static void validateUuid(String value)
            throws IOException {
        if (!validUuid(value)) {
            throw new IOException(
                "invalid execution history id");
        }
    }

    private static boolean validUuid(String value) {
        if (value == null) return false;
        try {
            return UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }
}
