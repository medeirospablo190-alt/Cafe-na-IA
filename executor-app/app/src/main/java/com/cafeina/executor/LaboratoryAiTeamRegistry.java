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
 * Immutable AI-team identities plus create-only session attribution.
 *
 * No prompt, goal, tool input/output or model transcript is stored here.
 */
public final class LaboratoryAiTeamRegistry {
    public static final int MAX_MEMBERS = 64;
    public static final int MAX_BINDINGS = 256;
    public static final int MAX_RECORD_BYTES = 12 * 1024;

    public static final String ROLE_TESTER = "TESTER";
    public static final String ROLE_DIAGNOSTIC = "DIAGNOSTIC";
    public static final String ROLE_CREATOR = "CREATOR";
    public static final String ROLE_REVIEWER = "REVIEWER";
    public static final String ROLE_RESEARCHER = "RESEARCHER";
    public static final String ROLE_ORCHESTRATOR = "ORCHESTRATOR";
    public static final String ROLE_SPECIALIST = "SPECIALIST";

    public static final class Member {
        public final String agentId;
        public final String displayName;
        public final String role;
        public final long createdAtEpochMs;
        public final String recordSha256;

        private Member(String agentId, String displayName, String role,
                long createdAtEpochMs, String recordSha256) {
            this.agentId = agentId;
            this.displayName = displayName;
            this.role = role;
            this.createdAtEpochMs = createdAtEpochMs;
            this.recordSha256 = recordSha256;
        }
    }

    public static final class Binding {
        public final String sessionId;
        public final String agentId;
        public final String contractId;
        public final long boundAtEpochMs;
        public final String recordSha256;

        private Binding(String sessionId, String agentId, String contractId,
                long boundAtEpochMs, String recordSha256) {
            this.sessionId = sessionId;
            this.agentId = agentId;
            this.contractId = contractId;
            this.boundAtEpochMs = boundAtEpochMs;
            this.recordSha256 = recordSha256;
        }
    }

    private final File appFilesDirectory;
    private final String projectId;
    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path teamRoot;
    private final Path memberRoot;
    private final Path bindingRoot;

    public LaboratoryAiTeamRegistry(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI-team project");
        }
        this.appFilesDirectory = appFilesDirectory;
        this.projectId = projectId;
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        teamRoot = projectRoot.resolve("ai-team");
        memberRoot = teamRoot.resolve("members");
        bindingRoot = teamRoot.resolve("session-bindings");
    }

    /**
     * Idempotent only for an exact existing identity. Identity mutation requires
     * a new agentId so historical diagnostics never change meaning.
     */
    public synchronized Member registerMember(
            String agentId, String displayName, String role) throws IOException {
        validateAgentId(agentId);
        String safeName = validateDisplayName(displayName);
        validateRole(role);
        ensureRoots();

        Path target = memberRoot.resolve(agentId + ".json");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            Member existing = readMember(agentId);
            if (!existing.displayName.equals(safeName)
                    || !existing.role.equals(role)) {
                throw new IOException(
                    "AI-team identity already exists with different metadata");
            }
            return existing;
        }
        if (countJson(memberRoot) >= MAX_MEMBERS) {
            throw new IOException("AI-team member limit reached");
        }

        long created = System.currentTimeMillis();
        String hash = memberSha(agentId, safeName, role, created);
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("agentId", agentId);
            json.put("displayName", safeName);
            json.put("role", role);
            json.put("createdAtEpochMs", created);
            json.put("recordSha256", hash);
            writeNew(target, json);
        } catch (JSONException error) {
            throw new IOException("could not encode AI-team member", error);
        }
        return readMember(agentId);
    }

    public synchronized Member readMember(String agentId) throws IOException {
        validateAgentId(agentId);
        ensureRoots();
        Path path = memberRoot.resolve(agentId + ".json");
        try {
            JSONObject json = new JSONObject(readSafe(path, memberRoot));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI-team member schema");
            }
            String id = json.getString("agentId");
            String name = validateDisplayName(json.getString("displayName"));
            String role = json.getString("role");
            long created = json.getLong("createdAtEpochMs");
            String stored = json.getString("recordSha256");
            validateAgentId(id);
            validateRole(role);
            if (!agentId.equals(id) || created <= 0
                    || !validSha(stored)
                    || !stored.equals(memberSha(id, name, role, created))) {
                throw new IOException("AI-team member integrity failed");
            }
            return new Member(id, name, role, created, stored);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI-team member", error);
        }
    }

    public synchronized List<Member> listMembers() throws IOException {
        if (!Files.exists(memberRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoots();
        List<Member> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(memberRoot)) {
            List<Path> files = new ArrayList<>();
            stream.forEach(files::add);
            if (files.size() > MAX_MEMBERS) {
                throw new IOException("AI-team member directory exceeds limit");
            }
            for (Path path : files) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".json")
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected AI-team member entry");
                }
                String agentId = name.substring(0, name.length() - 5);
                validateAgentId(agentId);
                result.add(readMember(agentId));
            }
        }
        result.sort(Comparator
            .comparing((Member member) -> member.role)
            .thenComparing(member -> member.agentId));
        return Collections.unmodifiableList(result);
    }

    public synchronized Binding bindSession(
            String sessionId, String agentId, String contractId)
            throws IOException {
        validateUuid(sessionId, "session");
        validateAgentId(agentId);
        if (contractId == null) contractId = "";
        if (!contractId.isEmpty()) validateUuid(contractId, "contract");

        // Proves the member exists and is intact.
        readMember(agentId);

        boolean found = false;
        for (LaboratoryAiSessionStore.Summary summary
                : new LaboratoryAiSessionStore(
                    appFilesDirectory, projectId).list()) {
            if (sessionId.equals(summary.sessionId)) {
                found = true;
                break;
            }
        }
        if (!found) {
            throw new IOException("AI-team session audit not found");
        }

        ensureRoots();
        Path target = bindingRoot.resolve(sessionId + ".json");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            Binding existing = readBinding(sessionId);
            if (!existing.agentId.equals(agentId)
                    || !existing.contractId.equals(contractId)) {
                throw new IOException(
                    "AI session is already attributed to another identity");
            }
            return existing;
        }
        if (countJson(bindingRoot) >= MAX_BINDINGS) {
            throw new IOException("AI-team session binding limit reached");
        }

        long boundAt = System.currentTimeMillis();
        String hash = bindingSha(
            sessionId, agentId, contractId, boundAt);
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("sessionId", sessionId);
            json.put("agentId", agentId);
            json.put("contractId", contractId);
            json.put("boundAtEpochMs", boundAt);
            json.put("recordSha256", hash);
            writeNew(target, json);
        } catch (JSONException error) {
            throw new IOException("could not encode AI-team session binding", error);
        }
        return readBinding(sessionId);
    }

    public synchronized Binding readBinding(String sessionId) throws IOException {
        validateUuid(sessionId, "session");
        ensureRoots();
        Path path = bindingRoot.resolve(sessionId + ".json");
        try {
            JSONObject json = new JSONObject(readSafe(path, bindingRoot));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI-team binding schema");
            }
            String id = json.getString("sessionId");
            String agentId = json.getString("agentId");
            String contractId = json.optString("contractId");
            long boundAt = json.getLong("boundAtEpochMs");
            String stored = json.getString("recordSha256");
            validateUuid(id, "session");
            validateAgentId(agentId);
            if (!contractId.isEmpty()) validateUuid(contractId, "contract");
            readMember(agentId);
            if (!sessionId.equals(id) || boundAt <= 0
                    || !validSha(stored)
                    || !stored.equals(bindingSha(
                        id, agentId, contractId, boundAt))) {
                throw new IOException("AI-team session binding integrity failed");
            }
            return new Binding(id, agentId, contractId, boundAt, stored);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI-team session binding", error);
        }
    }

    public synchronized List<Binding> listBindings() throws IOException {
        if (!Files.exists(bindingRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoots();
        List<Binding> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(bindingRoot)) {
            List<Path> files = new ArrayList<>();
            stream.forEach(files::add);
            if (files.size() > MAX_BINDINGS) {
                throw new IOException("AI-team binding directory exceeds limit");
            }
            for (Path path : files) {
                String name = path.getFileName().toString();
                if (!name.matches("[0-9a-f-]{36}\\.json")
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected AI-team binding entry");
                }
                result.add(readBinding(
                    name.substring(0, name.length() - 5)));
            }
        }
        result.sort(Comparator
            .comparingLong((Binding binding) -> binding.boundAtEpochMs)
            .thenComparing(binding -> binding.sessionId));
        return Collections.unmodifiableList(result);
    }

    private void ensureRoots() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(teamRoot);
        ensureSafeDirectory(memberRoot);
        ensureSafeDirectory(bindingRoot);
    }

    private static int countJson(Path root) throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            return (int) stream
                .filter(path -> path.getFileName().toString().endsWith(".json"))
                .limit(MAX_BINDINGS + 1L).count();
        }
    }

    private static String validateDisplayName(String value) {
        if (value == null) throw new IllegalArgumentException("AI display name missing");
        String name = value.trim();
        if (name.isEmpty() || name.length() > 80) {
            throw new IllegalArgumentException("invalid AI display name");
        }
        return name;
    }

    private static void validateAgentId(String value) {
        if (value == null
                || !value.matches("[a-z0-9][a-z0-9._-]{0,63}")) {
            throw new IllegalArgumentException("invalid AI agent id");
        }
    }

    private static void validateRole(String role) {
        if (!(ROLE_TESTER.equals(role)
                || ROLE_DIAGNOSTIC.equals(role)
                || ROLE_CREATOR.equals(role)
                || ROLE_REVIEWER.equals(role)
                || ROLE_RESEARCHER.equals(role)
                || ROLE_ORCHESTRATOR.equals(role)
                || ROLE_SPECIALIST.equals(role))) {
            throw new IllegalArgumentException("invalid AI-team role");
        }
    }

    private static void validateUuid(String value, String label) {
        try {
            if (value == null
                    || !UUID.fromString(value).toString().equals(value)) {
                throw new IllegalArgumentException("invalid " + label + " id");
            }
        } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException("invalid " + label + " id", error);
        }
    }

    private static String readSafe(Path path, Path expectedParent)
            throws IOException {
        if (!expectedParent.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_RECORD_BYTES) {
            throw new IOException("AI-team record missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("AI-team record already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECORD_BYTES) {
            throw new IOException("AI-team record exceeds size budget");
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

    private static String memberSha(
            String agentId, String displayName, String role, long created) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, agentId);
        field(canonical, displayName);
        field(canonical, role);
        field(canonical, Long.toString(created));
        return sha256(canonical.toString());
    }

    private static String bindingSha(
            String sessionId, String agentId, String contractId, long boundAt) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, sessionId);
        field(canonical, agentId);
        field(canonical, contractId);
        field(canonical, Long.toString(boundAt));
        return sha256(canonical.toString());
    }

    private static void field(StringBuilder out, String value) {
        String safe = value == null ? "" : value;
        out.append(safe.length()).append(':').append(safe);
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
            throw new IOException("unsafe AI-team directory");
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
