package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

/**
 * Small project-scoped operational chat snapshot.
 *
 * This is deliberately separate from CAFEÍNA knowledge/memory. It exists only
 * to restore the visible conversation and the current task hand-off after the
 * UI or process is recreated.
 */
public final class LaboratoryAiChatSessionStore {
    public static final int MAX_ENTRIES = 64;
    public static final int MAX_ENTRY_CHARS = 8 * 1024;
    public static final int MAX_STATUS_CHARS = 240;
    public static final int MAX_FILE_BYTES = 640 * 1024;

    public enum Role {
        USER,
        ASSISTANT
    }

    public enum WorkflowState {
        IDLE,
        ACTION_REVIEW,
        GOAL_LOCK_CREATED,
        PLANNING,
        PLAN_READY,
        TEST_PREPARED,
        TEST_RUNNING,
        COMPLETED,
        FAILED,
        CANCELLED,
        INTERRUPTED
    }

    public static final class Entry {
        public final String entryId;
        public final Role role;
        public final String text;
        public final boolean modelContext;
        public final long createdAtEpochMs;

        public Entry(
                String entryId,
                Role role,
                String text,
                boolean modelContext,
                long createdAtEpochMs) {
            this.entryId = entryId;
            this.role = role;
            this.text = text;
            this.modelContext = modelContext;
            this.createdAtEpochMs = createdAtEpochMs;
        }

        public static Entry create(
                Role role,
                String text,
                boolean modelContext) {
            return new Entry(
                UUID.randomUUID().toString(),
                role,
                text,
                modelContext,
                System.currentTimeMillis());
        }
    }

    public static final class Snapshot {
        public final long updatedAtEpochMs;
        public final List<Entry> entries;
        public final WorkflowState workflowState;
        public final String contractId;
        public final String scenarioId;
        public final String reportId;
        public final String statusDetail;

        public Snapshot(
                long updatedAtEpochMs,
                List<Entry> entries,
                WorkflowState workflowState,
                String contractId,
                String scenarioId,
                String reportId,
                String statusDetail) {
            this.updatedAtEpochMs = updatedAtEpochMs;
            this.entries = Collections.unmodifiableList(
                new ArrayList<>(entries == null
                    ? Collections.emptyList()
                    : entries));
            this.workflowState = workflowState;
            this.contractId = safeId(contractId);
            this.scenarioId = safeId(scenarioId);
            this.reportId = safeId(reportId);
            this.statusDetail = statusDetail == null ? "" : statusDetail;
        }

        public static Snapshot empty() {
            return new Snapshot(
                System.currentTimeMillis(),
                Collections.emptyList(),
                WorkflowState.IDLE,
                "",
                "",
                "",
                "");
        }
    }

    private final Path root;
    private final Path stateFile;

    public LaboratoryAiChatSessionStore(
            File appFilesDirectory,
            String projectId) {
        if (appFilesDirectory == null
                || projectId == null
                || (!projectId.isEmpty()
                    && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException(
                "invalid chat-session project");
        }

        Path appRoot = appFilesDirectory.toPath()
            .toAbsolutePath()
            .normalize();
        Path laboratoryRoot = appRoot.resolve("laboratory");
        Path projectRoot = laboratoryRoot.resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-chat-session");
        stateFile = root.resolve("state.json");
    }

    public synchronized Snapshot load() throws IOException {
        if (!Files.exists(stateFile, LinkOption.NOFOLLOW_LINKS)) {
            return Snapshot.empty();
        }
        prepareRoot();
        if (Files.isSymbolicLink(stateFile)
                || !Files.isRegularFile(
                    stateFile, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(
                "chat session state is not a safe file");
        }

        long size = Files.size(stateFile);
        if (size < 1L || size > MAX_FILE_BYTES) {
            throw new IOException(
                "chat session state has invalid size");
        }
        byte[] raw = Files.readAllBytes(stateFile);
        if (raw.length != size || raw.length > MAX_FILE_BYTES) {
            throw new IOException(
                "chat session state changed during read");
        }

        try {
            return decode(new JSONObject(
                new String(raw, StandardCharsets.UTF_8)));
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException(
                "invalid chat session state", error);
        }
    }

    public synchronized void save(Snapshot snapshot)
            throws IOException {
        validate(snapshot);
        prepareRoot();

        byte[] encoded;
        try {
            encoded = encode(snapshot)
                .toString()
                .getBytes(StandardCharsets.UTF_8);
        } catch (JSONException error) {
            throw new IOException(
                "could not encode chat session state", error);
        }
        if (encoded.length > MAX_FILE_BYTES) {
            throw new IOException(
                "chat session state exceeds size limit");
        }

        Path temp = root.resolve(
            "state-" + UUID.randomUUID().toString() + ".tmp")
            .normalize();
        if (!root.equals(temp.getParent())) {
            throw new IOException(
                "chat session temporary path escaped root");
        }

        try {
            Files.write(
                temp,
                encoded,
                StandardOpenOption.CREATE_NEW,
                StandardOpenOption.WRITE);
            try {
                Files.move(
                    temp,
                    stateFile,
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(
                    temp,
                    stateFile,
                    StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temp);
        }
    }

    public synchronized void clear() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) return;
        prepareRoot();
        Files.deleteIfExists(stateFile);
    }

    private JSONObject encode(Snapshot snapshot)
            throws JSONException {
        JSONObject json = new JSONObject();
        json.put("schemaVersion", 1);
        json.put("updatedAtEpochMs", snapshot.updatedAtEpochMs);
        json.put("workflowState", snapshot.workflowState.name());
        json.put("contractId", snapshot.contractId);
        json.put("scenarioId", snapshot.scenarioId);
        json.put("reportId", snapshot.reportId);
        json.put("statusDetail", snapshot.statusDetail);

        JSONArray entries = new JSONArray();
        for (Entry entry : snapshot.entries) {
            JSONObject item = new JSONObject();
            item.put("entryId", entry.entryId);
            item.put("role", entry.role.name());
            item.put("text", entry.text);
            item.put("modelContext", entry.modelContext);
            item.put("createdAtEpochMs", entry.createdAtEpochMs);
            entries.put(item);
        }
        json.put("entries", entries);
        return json;
    }

    private Snapshot decode(JSONObject json)
            throws JSONException, IOException {
        if (json.getInt("schemaVersion") != 1) {
            throw new IOException(
                "unsupported chat session schema");
        }

        JSONArray array = json.getJSONArray("entries");
        if (array.length() > MAX_ENTRIES) {
            throw new IOException(
                "chat session has too many entries");
        }

        List<Entry> entries = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.getJSONObject(i);
            Entry entry = new Entry(
                item.getString("entryId"),
                Role.valueOf(item.getString("role")),
                item.getString("text"),
                item.getBoolean("modelContext"),
                item.getLong("createdAtEpochMs"));
            validateEntry(entry);
            entries.add(entry);
        }

        Snapshot snapshot = new Snapshot(
            json.getLong("updatedAtEpochMs"),
            entries,
            WorkflowState.valueOf(
                json.getString("workflowState")),
            json.optString("contractId", ""),
            json.optString("scenarioId", ""),
            json.optString("reportId", ""),
            json.optString("statusDetail", ""));
        validate(snapshot);
        return snapshot;
    }

    private void validate(Snapshot snapshot)
            throws IOException {
        if (snapshot == null
                || snapshot.updatedAtEpochMs <= 0L
                || snapshot.workflowState == null
                || snapshot.entries == null
                || snapshot.entries.size() > MAX_ENTRIES
                || snapshot.statusDetail == null
                || snapshot.statusDetail.length() > MAX_STATUS_CHARS) {
            throw new IOException(
                "invalid chat session snapshot");
        }
        validateOptionalUuid(snapshot.contractId);
        validateOptionalUuid(snapshot.scenarioId);
        validateOptionalUuid(snapshot.reportId);

        for (Entry entry : snapshot.entries) {
            validateEntry(entry);
        }
    }

    private void validateEntry(Entry entry)
            throws IOException {
        if (entry == null
                || !validUuid(entry.entryId)
                || entry.role == null
                || entry.text == null
                || entry.text.isEmpty()
                || entry.text.length() > MAX_ENTRY_CHARS
                || entry.createdAtEpochMs <= 0L) {
            throw new IOException(
                "invalid chat session entry");
        }
    }

    private void prepareRoot() throws IOException {
        Path projectRoot = root.getParent();
        Path laboratoryRoot = projectRoot.getParent();

        Files.createDirectories(laboratoryRoot);
        requireSafeDirectory(
            laboratoryRoot, "laboratory");
        Files.createDirectories(projectRoot);
        requireSafeDirectory(
            projectRoot, "laboratory project");
        Files.createDirectories(root);
        requireSafeDirectory(
            root, "chat session root");

        if (Files.exists(stateFile, LinkOption.NOFOLLOW_LINKS)
                && Files.isSymbolicLink(stateFile)) {
            throw new IOException(
                "chat session state cannot be a symlink");
        }
    }

    private static void requireSafeDirectory(
            Path path,
            String label) throws IOException {
        if (Files.isSymbolicLink(path)
                || !Files.isDirectory(
                    path, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException(
                label + " is not a safe directory");
        }
    }

    private static void validateOptionalUuid(String value)
            throws IOException {
        if (value == null) {
            throw new IOException(
                "chat session id is null");
        }
        if (!value.isEmpty() && !validUuid(value)) {
            throw new IOException(
                "chat session id is invalid");
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

    private static String safeId(String value) {
        return value == null ? "" : value;
    }
}
