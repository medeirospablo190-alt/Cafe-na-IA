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
 * Append-only user decisions for improvement proposals.
 *
 * Decisions only change proposal workflow state. They never execute tools,
 * mutate AI code, change budgets or apply an improvement.
 */
public final class LaboratoryAiImprovementDecisionStore {
    public static final String ACTION_ROUTE = "ROUTE_FOR_REVIEW";
    public static final String ACTION_DISMISS = "DISMISS";
    public static final String ACTION_REOPEN = "REOPEN";

    public static final String STATE_PENDING = "PENDING";
    public static final String STATE_ROUTED = "ROUTED_FOR_REVIEW";
    public static final String STATE_DISMISSED = "DISMISSED";

    public static final int MAX_EVENTS_PER_PROPOSAL = 32;
    public static final int MAX_EVENT_BYTES = 12 * 1024;

    private static final Object WRITE_LOCK = new Object();

    public static final class Event {
        public final String eventId;
        public final int sequence;
        public final String proposalId;
        public final String proposalKeySha256;
        public final String action;
        public final String previousState;
        public final String newState;
        public final String targetRole;
        public final String actor;
        public final long createdAtEpochMs;
        public final String recordSha256;

        private Event(String eventId, int sequence, String proposalId,
                String proposalKeySha256, String action,
                String previousState, String newState, String targetRole,
                String actor, long createdAtEpochMs, String recordSha256) {
            this.eventId = eventId;
            this.sequence = sequence;
            this.proposalId = proposalId;
            this.proposalKeySha256 = proposalKeySha256;
            this.action = action;
            this.previousState = previousState;
            this.newState = newState;
            this.targetRole = targetRole;
            this.actor = actor;
            this.createdAtEpochMs = createdAtEpochMs;
            this.recordSha256 = recordSha256;
        }
    }

    public static final class State {
        public final String proposalId;
        public final String status;
        public final int eventCount;
        public final long updatedAtEpochMs;

        private State(String proposalId, String status,
                int eventCount, long updatedAtEpochMs) {
            this.proposalId = proposalId;
            this.status = status;
            this.eventCount = eventCount;
            this.updatedAtEpochMs = updatedAtEpochMs;
        }
    }

    private final File appFilesDirectory;
    private final String projectId;
    private final Path root;

    public LaboratoryAiImprovementDecisionStore(
            File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException(
                "invalid AI improvement decision project");
        }
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path projectRoot = appRoot.resolve("laboratory").resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-improvement-decisions");
    }

    public Event routeForReview(String proposalId) throws IOException {
        return append(proposalId, ACTION_ROUTE);
    }

    public Event dismiss(String proposalId) throws IOException {
        return append(proposalId, ACTION_DISMISS);
    }

    public Event reopen(String proposalId) throws IOException {
        return append(proposalId, ACTION_REOPEN);
    }

    public Event append(String proposalId, String action) throws IOException {
        synchronized (WRITE_LOCK) {
            validateAction(action);
            LaboratoryAiImprovementProposalStore.Proposal proposal =
                new LaboratoryAiImprovementProposalStore(
                    appFilesDirectory, projectId).read(proposalId);

            State before = stateLocked(proposalId);
            String next = nextState(before.status, action);
            Path directory = ensureProposalDirectory(proposalId);
            List<Event> existing = readEventsLocked(proposalId, directory);
            if (existing.size() >= MAX_EVENTS_PER_PROPOSAL) {
                throw new IOException(
                    "AI improvement decision history limit reached");
            }

            int sequence = existing.size() + 1;
            String eventId = UUID.randomUUID().toString();
            long created = System.currentTimeMillis();
            String actor = "USER";
            String targetRole = ACTION_ROUTE.equals(action)
                ? proposal.targetRole : "";
            String hash = eventSha(
                eventId,
                sequence,
                proposal.proposalId,
                proposal.proposalKeySha256,
                action,
                before.status,
                next,
                targetRole,
                actor,
                created);

            try {
                JSONObject json = new JSONObject();
                json.put("schemaVersion", 1);
                json.put("eventId", eventId);
                json.put("sequence", sequence);
                json.put("proposalId", proposal.proposalId);
                json.put("proposalKeySha256", proposal.proposalKeySha256);
                json.put("action", action);
                json.put("previousState", before.status);
                json.put("newState", next);
                json.put("targetRole", targetRole);
                json.put("actor", actor);
                json.put("createdAtEpochMs", created);
                json.put("recordSha256", hash);
                writeNew(directory.resolve(
                    String.format(Locale.ROOT, "%06d.json", sequence)), json);
            } catch (JSONException error) {
                throw new IOException(
                    "could not encode AI improvement decision", error);
            }

            return readEventsLocked(proposalId, directory)
                .get(sequence - 1);
        }
    }

    public State state(String proposalId) throws IOException {
        synchronized (WRITE_LOCK) {
            return stateLocked(proposalId);
        }
    }

    public List<Event> history(String proposalId) throws IOException {
        synchronized (WRITE_LOCK) {
            Path directory = ensureProposalDirectory(proposalId);
            return Collections.unmodifiableList(
                new ArrayList<>(readEventsLocked(proposalId, directory)));
        }
    }

    private State stateLocked(String proposalId) throws IOException {
        // Also validates the proposal itself and its hash.
        new LaboratoryAiImprovementProposalStore(
            appFilesDirectory, projectId).read(proposalId);

        Path directory = root.resolve(proposalId);
        if (!Files.exists(directory, LinkOption.NOFOLLOW_LINKS)) {
            ensureRoot();
            return new State(proposalId, STATE_PENDING, 0, 0L);
        }

        List<Event> events = readEventsLocked(
            proposalId, ensureProposalDirectory(proposalId));
        if (events.isEmpty()) {
            return new State(proposalId, STATE_PENDING, 0, 0L);
        }
        Event last = events.get(events.size() - 1);
        return new State(
            proposalId,
            last.newState,
            events.size(),
            last.createdAtEpochMs);
    }

    private List<Event> readEventsLocked(
            String proposalId, Path directory) throws IOException {
        LaboratoryAiImprovementProposalStore.Proposal proposal =
            new LaboratoryAiImprovementProposalStore(
                appFilesDirectory, projectId).read(proposalId);

        List<Event> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(directory)) {
            List<Path> files = new ArrayList<>();
            stream.forEach(files::add);
            if (files.size() > MAX_EVENTS_PER_PROPOSAL) {
                throw new IOException(
                    "AI improvement decision history exceeds limit");
            }
            files.sort(Comparator.comparing(
                path -> path.getFileName().toString()));
            for (Path path : files) {
                String name = path.getFileName().toString();
                if (!name.matches("[0-9]{6}\\.json")
                        || Files.isSymbolicLink(path)) {
                    throw new IOException(
                        "unexpected AI improvement decision entry");
                }
                Event event = parse(path);
                if (event.sequence != result.size() + 1
                        || !proposalId.equals(event.proposalId)
                        || !proposal.proposalKeySha256.equals(
                            event.proposalKeySha256)) {
                    throw new IOException(
                        "AI improvement decision sequence/proposal mismatch");
                }

                String expectedPrevious = result.isEmpty()
                    ? STATE_PENDING
                    : result.get(result.size() - 1).newState;
                if (!expectedPrevious.equals(event.previousState)
                        || !nextState(
                            event.previousState, event.action)
                            .equals(event.newState)) {
                    throw new IOException(
                        "AI improvement decision state transition invalid");
                }
                if (ACTION_ROUTE.equals(event.action)) {
                    if (!proposal.targetRole.equals(event.targetRole)) {
                        throw new IOException(
                            "AI improvement routed to wrong role");
                    }
                } else if (!event.targetRole.isEmpty()) {
                    throw new IOException(
                        "non-route decision must not contain target role");
                }
                result.add(event);
            }
        }
        return result;
    }

    private Event parse(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_EVENT_BYTES) {
            throw new IOException(
                "AI improvement decision missing, unsafe or too large");
        }
        try {
            JSONObject json = new JSONObject(
                new String(Files.readAllBytes(path), StandardCharsets.UTF_8));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException(
                    "unsupported AI improvement decision schema");
            }
            Event event = new Event(
                json.getString("eventId"),
                json.getInt("sequence"),
                json.getString("proposalId"),
                json.getString("proposalKeySha256"),
                json.getString("action"),
                json.getString("previousState"),
                json.getString("newState"),
                json.optString("targetRole"),
                json.getString("actor"),
                json.getLong("createdAtEpochMs"),
                json.getString("recordSha256"));
            validateEvent(event);
            String expected = eventSha(
                event.eventId,
                event.sequence,
                event.proposalId,
                event.proposalKeySha256,
                event.action,
                event.previousState,
                event.newState,
                event.targetRole,
                event.actor,
                event.createdAtEpochMs);
            if (!event.recordSha256.equals(expected)) {
                throw new IOException(
                    "AI improvement decision integrity failed");
            }
            return event;
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException(
                "invalid AI improvement decision record", error);
        }
    }

    private Path ensureProposalDirectory(String proposalId)
            throws IOException {
        validateUuid(proposalId);
        ensureRoot();
        Path directory = root.resolve(proposalId);
        if (!Files.exists(directory, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(directory);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(directory)) {
            throw new IOException(
                "unsafe AI improvement decision directory");
        }
        return directory;
    }

    private void ensureRoot() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            Path parent = root.getParent();
            if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(parent)) {
                throw new IOException(
                    "AI improvement decision parent missing or unsafe");
            }
            try {
                Files.createDirectory(root);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(root)) {
            throw new IOException(
                "unsafe AI improvement decision root");
        }
    }

    private static String nextState(String current, String action)
            throws IOException {
        if (STATE_PENDING.equals(current)) {
            if (ACTION_ROUTE.equals(action)) return STATE_ROUTED;
            if (ACTION_DISMISS.equals(action)) return STATE_DISMISSED;
        } else if (STATE_ROUTED.equals(current)) {
            if (ACTION_DISMISS.equals(action)) return STATE_DISMISSED;
            if (ACTION_REOPEN.equals(action)) return STATE_PENDING;
        } else if (STATE_DISMISSED.equals(current)) {
            if (ACTION_REOPEN.equals(action)) return STATE_PENDING;
        }
        throw new IOException(
            "AI improvement decision is not valid from state " + current);
    }

    private static void validateEvent(Event event) {
        validateUuid(event.eventId);
        validateUuid(event.proposalId);
        validateAction(event.action);
        if (event.sequence < 1
                || event.sequence > MAX_EVENTS_PER_PROPOSAL
                || !validSha(event.proposalKeySha256)
                || !validState(event.previousState)
                || !validState(event.newState)
                || (!event.targetRole.isEmpty()
                    && !validRole(event.targetRole))
                || !"USER".equals(event.actor)
                || event.createdAtEpochMs <= 0
                || !validSha(event.recordSha256)) {
            throw new IllegalArgumentException(
                "invalid AI improvement decision event");
        }
    }

    private static void validateAction(String value) {
        if (!(ACTION_ROUTE.equals(value)
                || ACTION_DISMISS.equals(value)
                || ACTION_REOPEN.equals(value))) {
            throw new IllegalArgumentException(
                "invalid AI improvement decision action");
        }
    }

    private static boolean validState(String value) {
        return STATE_PENDING.equals(value)
            || STATE_ROUTED.equals(value)
            || STATE_DISMISSED.equals(value);
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

    private static void writeNew(Path destination, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(
                "AI improvement decision event already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_EVENT_BYTES) {
            throw new IOException(
                "AI improvement decision exceeds size limit");
        }

        Path temporary = destination.getParent().resolve(
            "." + destination.getFileName()
                + ".tmp-" + UUID.randomUUID());
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
                Files.move(
                    temporary,
                    destination,
                    StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unavailable) {
                Files.move(temporary, destination);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private static String eventSha(
            String eventId, int sequence, String proposalId,
            String proposalKeySha256, String action,
            String previousState, String newState,
            String targetRole, String actor, long created) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, eventId);
        field(canonical, Integer.toString(sequence));
        field(canonical, proposalId);
        field(canonical, proposalKeySha256);
        field(canonical, action);
        field(canonical, previousState);
        field(canonical, newState);
        field(canonical, targetRole);
        field(canonical, actor);
        field(canonical, Long.toString(created));
        return sha256(canonical.toString());
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
                out.append(String.format(
                    Locale.ROOT, "%02x", b & 0xff));
            }
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(
                "SHA-256 unavailable", impossible);
        }
    }
}
