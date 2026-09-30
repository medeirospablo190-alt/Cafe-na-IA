package com.cafeina.executor;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

/**
 * Immutable binding between a registered tool version and the exact verified
 * snapshot that contains its executable artifact.
 *
 * This class does not execute the artifact. Future execution gates must call
 * readVerified() and use only the returned verified bytes/source.
 */
public final class LaboratoryToolArtifactStore {
    public static final String LUAU_SOURCE_V1 = "LUAU_SOURCE_V1";
    public static final int MAX_BINDINGS_PER_TOOL = 64;
    public static final int MAX_BINDING_BYTES = 8 * 1024;

    public static final class Binding {
        public final String toolId;
        public final String version;
        public final String artifactKind;
        public final String snapshotId;
        public final String artifactSha256;
        public final long createdAtEpochMs;
        private final String verifiedLuauSource;

        private Binding(String toolId, String version, String artifactKind,
                String snapshotId, String artifactSha256, long createdAtEpochMs,
                String verifiedLuauSource) {
            this.toolId = toolId;
            this.version = version;
            this.artifactKind = artifactKind;
            this.snapshotId = snapshotId;
            this.artifactSha256 = artifactSha256;
            this.createdAtEpochMs = createdAtEpochMs;
            this.verifiedLuauSource = verifiedLuauSource;
        }

        /**
         * Returned only after descriptor + binding + snapshot hashes are checked.
         * No caller-provided source is accepted here.
         */
        public String luauSource() {
            return verifiedLuauSource;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path artifactRoot;
    private final LaboratoryToolRegistry registry;
    private final LaboratorySnapshotStore snapshots;

    public LaboratoryToolArtifactStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid tool artifact project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        artifactRoot = projectRoot.resolve("tool-artifacts");
        registry = new LaboratoryToolRegistry(appFilesDirectory, projectId);
        snapshots = new LaboratorySnapshotStore(appFilesDirectory, projectId);
    }

    /**
     * Binding is allowed only while the registered version is EXPERIMENTAL.
     * Once a version becomes CANDIDATE, its executable artifact is frozen.
     */
    public synchronized Binding bindLuauSource(
            String toolId, String version, String snapshotId) throws IOException {
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(toolId, version);
        if (registry.stage(toolId, version) != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
            throw new IOException("tool artifact must be bound before candidate qualification");
        }
        if (!LaboratorySnapshotStore.validId(snapshotId)) {
            throw new IOException("invalid executable snapshot id");
        }

        LaboratorySnapshotStore.Snapshot snapshot = snapshots.readCopy(snapshotId);
        if (!descriptor.artifactSha256.equals(snapshot.sha256)) {
            throw new IOException("snapshot hash does not match registered artifact");
        }
        decodeLuau(snapshot.contentCopy());

        Path toolDirectory = ensureWritableToolDirectory(toolId);
        Path target = toolDirectory.resolve(version + ".json");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("tool artifact binding already exists");
        }
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("toolId", toolId);
            json.put("version", version);
            json.put("artifactKind", LUAU_SOURCE_V1);
            json.put("snapshotId", snapshotId);
            json.put("artifactSha256", descriptor.artifactSha256);
            json.put("createdAtEpochMs", System.currentTimeMillis());
            writeNew(target, json);
        } catch (JSONException error) {
            throw new IOException("could not encode tool artifact binding", error);
        }
        return readVerified(toolId, version);
    }

    /**
     * Fails closed if the descriptor, binding or snapshot no longer agree.
     */
    public synchronized Binding readVerified(String toolId, String version)
            throws IOException {
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(toolId, version);
        requireExistingDirectories(toolId);
        Path path = artifactRoot.resolve(toolId).resolve(version + ".json");
        String raw = readSafe(path);
        try {
            JSONObject json = new JSONObject(raw);
            if (json.getInt("schemaVersion") != 1
                    || !toolId.equals(json.getString("toolId"))
                    || !version.equals(json.getString("version"))
                    || !LUAU_SOURCE_V1.equals(json.getString("artifactKind"))) {
                throw new IOException("tool artifact binding identity is invalid");
            }
            String snapshotId = json.getString("snapshotId");
            String artifactSha = json.getString("artifactSha256");
            long created = json.getLong("createdAtEpochMs");
            if (!LaboratorySnapshotStore.validId(snapshotId)
                    || created <= 0
                    || !artifactSha.matches("[0-9a-f]{64}")
                    || !descriptor.artifactSha256.equals(artifactSha)) {
                throw new IOException("tool artifact binding metadata is invalid");
            }

            LaboratorySnapshotStore.Snapshot snapshot = snapshots.readCopy(snapshotId);
            if (!artifactSha.equals(snapshot.sha256)) {
                throw new IOException("tool artifact snapshot integrity mismatch");
            }
            String source = decodeLuau(snapshot.contentCopy());
            return new Binding(toolId, version, LUAU_SOURCE_V1, snapshotId,
                artifactSha, created, source);
        } catch (JSONException error) {
            throw new IOException("invalid tool artifact binding", error);
        }
    }

    /**
     * Narrow resolution path for the future execution gate: the caller supplies
     * only a tool ID; the active STABLE version and its exact snapshot are
     * resolved internally.
     */
    public synchronized Binding readActiveStableVerified(String toolId) throws IOException {
        LaboratoryToolRegistry.Descriptor active = registry.activeStable(toolId);
        if (active == null) throw new IOException("no active STABLE tool version");
        return readVerified(active.toolId, active.version);
    }

    public synchronized boolean isBound(String toolId, String version) throws IOException {
        registry.readDescriptor(toolId, version);
        Path toolDirectory = artifactRoot.resolve(toolId);
        if (!Files.exists(toolDirectory, LinkOption.NOFOLLOW_LINKS)) return false;
        requireExistingDirectories(toolId);
        Path binding = toolDirectory.resolve(version + ".json");
        if (!Files.exists(binding, LinkOption.NOFOLLOW_LINKS)) return false;
        readVerified(toolId, version);
        return true;
    }

    private Path ensureWritableToolDirectory(String toolId) throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(artifactRoot);
        Path toolDirectory = artifactRoot.resolve(toolId);
        ensureSafeDirectory(toolDirectory);

        try (java.util.stream.Stream<Path> stream = Files.list(toolDirectory)) {
            long count = stream.filter(path -> {
                String name = path.getFileName().toString();
                return name.endsWith(".json");
            }).limit(MAX_BINDINGS_PER_TOOL + 1L).count();
            if (count >= MAX_BINDINGS_PER_TOOL) {
                throw new IOException(
                    "tool artifact binding limit reached; existing bindings were preserved");
            }
        }
        return toolDirectory;
    }

    private void requireExistingDirectories(String toolId) throws IOException {
        for (Path path : new Path[]{
                laboratoryRoot, projectRoot, artifactRoot, artifactRoot.resolve(toolId)}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("tool artifact directory missing or unsafe");
            }
        }
    }

    private static String decodeLuau(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length == 0
                || bytes.length > LaboratorySnapshotStore.MAX_CONTENT_BYTES) {
            throw new IOException("invalid executable artifact size");
        }
        final String source;
        try {
            source = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString();
        } catch (CharacterCodingException invalidUtf8) {
            throw new IOException("executable artifact is not valid UTF-8", invalidUtf8);
        }
        if (source.isEmpty()
                || source.length() > LaboratorySandboxService.MAX_SOURCE_CHARS) {
            throw new IOException("executable Luau artifact exceeds sandbox limits");
        }
        return source;
    }

    private static void writeNew(Path target, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("tool artifact binding already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_BINDING_BYTES) {
            throw new IOException("tool artifact binding exceeds size budget");
        }
        Path temporary = target.getParent().resolve(
            "." + target.getFileName() + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("tool artifact binding already exists");
            }
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unavailable) {
                Files.move(temporary, target);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private static String readSafe(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_BINDING_BYTES) {
            throw new IOException("tool artifact binding missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
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
            throw new IOException("unsafe tool artifact directory");
        }
    }
}
