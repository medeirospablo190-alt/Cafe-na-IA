package com.cafeina.executor;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
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
import java.util.stream.Stream;

/**
 * Versioned, create-only copies of APPROVED laboratory inputs.
 *
 * Snapshot bytes never come from the user's scripts or project folders through
 * this class. A caller must explicitly pass a bounded test artifact. Recovery
 * returns a separate byte-array copy; it never writes into the original file,
 * promotes a candidate, changes a project or touches the app's runtime-fs.
 *
 * The snapshot vault is app-private, not a security boundary against root or
 * code already running with the app's UID.
 */
public final class LaboratorySnapshotStore {
    public static final int MAX_SNAPSHOTS = 64;
    public static final int MAX_CONTENT_BYTES = 128 * 1024;
    private static final int MAX_STORAGE_BYTES = MAX_CONTENT_BYTES + 256;
    private static final int MAX_ENTRIES = MAX_SNAPSHOTS * 2;
    private static final String MAGIC = "CAFEINA_LAB_SNAPSHOT";
    private static final int FORMAT_VERSION = 1;

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path snapshotRoot;

    public static final class Snapshot {
        public final String id;
        public final String label;
        public final long createdAtEpochMs;
        public final String sha256;
        public final int sizeBytes;
        private final byte[] contents;

        private Snapshot(String id, String label, long created, String hash, byte[] bytes) {
            this.id = id;
            this.label = label;
            this.createdAtEpochMs = created;
            this.sha256 = hash;
            this.sizeBytes = bytes.length;
            this.contents = bytes.clone();
        }

        /** A fresh copy: editing it cannot change the stored snapshot. */
        public byte[] contentCopy() {
            return contents.clone();
        }
    }

    public LaboratorySnapshotStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid laboratory snapshot project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        snapshotRoot = projectRoot.resolve("snapshots");
    }

    public synchronized Snapshot create(String label, byte[] approvedInput) throws IOException {
        if (!validLabel(label) || approvedInput == null
                || approvedInput.length == 0 || approvedInput.length > MAX_CONTENT_BYTES) {
            throw new IllegalArgumentException("invalid or oversized snapshot input");
        }
        // Caller may reuse/mutate its buffer. Capture exactly one immutable value.
        byte[] contents = approvedInput.clone();
        ensureWritable();
        String id = UUID.randomUUID().toString();
        long created = System.currentTimeMillis();
        String sha = hexSha256(contents);
        Path target = snapshotRoot.resolve(id + ".snap");
        Path temporary = snapshotRoot.resolve("." + id + ".tmp-" + UUID.randomUUID());
        boolean committed = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream file = new FileOutputStream(temporary.toFile(), false);
                    DataOutputStream output = new DataOutputStream(file)) {
                output.writeUTF(MAGIC);
                output.writeInt(FORMAT_VERSION);
                output.writeUTF(id);
                output.writeUTF(label);
                output.writeLong(created);
                output.writeInt(contents.length);
                output.writeUTF(sha);
                output.write(contents);
                output.flush();
                file.getFD().sync();
            }
            if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("snapshot identifier already exists");
            }
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unavailable) {
                Files.move(temporary, target);
            }
            committed = true;
        } finally {
            if (!committed) Files.deleteIfExists(temporary);
        }
        return new Snapshot(id, label, created, sha, contents);
    }

    /**
     * Validates length and SHA-256 before returning a copy. A missing, altered,
     * linked, oversized or incompatible snapshot fails closed.
     */
    public synchronized Snapshot readCopy(String id) throws IOException {
        if (!validId(id)) throw new IOException("invalid snapshot id");
        requireExistingDirectory();
        Path target = snapshotRoot.resolve(id + ".snap");
        if (!Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(target)) {
            throw new IOException("snapshot missing or unsafe");
        }
        long size = Files.size(target);
        if (size < 1 || size > MAX_STORAGE_BYTES) {
            throw new IOException("snapshot size is invalid");
        }
        byte[] binary = Files.readAllBytes(target);
        try (DataInputStream input =
                new DataInputStream(new ByteArrayInputStream(binary))) {
            if (!MAGIC.equals(input.readUTF()) || input.readInt() != FORMAT_VERSION
                    || !id.equals(input.readUTF())) {
                throw new IOException("snapshot version or identity is invalid");
            }
            String label = input.readUTF();
            long created = input.readLong();
            int length = input.readInt();
            String hash = input.readUTF();
            if (!validLabel(label) || created <= 0
                    || length < 1 || length > MAX_CONTENT_BYTES
                    || !hash.matches("[0-9a-f]{64}") || length != input.available()) {
                throw new IOException("snapshot header is invalid");
            }
            byte[] contents = new byte[length];
            input.readFully(contents);
            if (input.read() != -1 || !hash.equals(hexSha256(contents))) {
                throw new IOException("snapshot integrity check failed");
            }
            return new Snapshot(id, label, created, hash, contents);
        } catch (RuntimeException malformed) {
            throw new IOException("snapshot is malformed", malformed);
        }
    }

    /** Does not hide corrupted snapshots by silently removing their records. */
    public synchronized List<Snapshot> listVerified() throws IOException {
        if (!Files.exists(laboratoryRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(projectRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(snapshotRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireExistingDirectory();
        List<String> ids = new ArrayList<>();
        try (Stream<Path> entries = Files.list(snapshotRoot)) {
            entries.forEach(path -> {
                String name = path.getFileName().toString();
                if (name.endsWith(".snap") && validId(name.substring(0, name.length() - 5))) {
                    ids.add(name.substring(0, name.length() - 5));
                }
            });
        }
        if (ids.size() > MAX_SNAPSHOTS) throw new IOException("snapshot limit exceeded");
        List<Snapshot> snapshots = new ArrayList<>();
        for (String id : ids) snapshots.add(readCopy(id));
        snapshots.sort(Comparator.comparingLong((Snapshot s) -> s.createdAtEpochMs)
            .reversed().thenComparing(s -> s.id));
        return Collections.unmodifiableList(snapshots);
    }

    private void ensureWritable() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(snapshotRoot);
        try (Stream<Path> entries = Files.list(snapshotRoot)) {
            List<Path> paths = new ArrayList<>();
            entries.forEach(paths::add);
            if (paths.size() >= MAX_ENTRIES) {
                throw new IOException("snapshot vault entry budget reached");
            }
            int valid = 0;
            for (Path path : paths) {
                if (Files.isSymbolicLink(path)) {
                    throw new IOException("unsafe entry in snapshot vault");
                }
                String name = path.getFileName().toString();
                if (name.endsWith(".snap") && validId(name.substring(0, name.length() - 5))) {
                    valid++;
                }
            }
            if (valid >= MAX_SNAPSHOTS) {
                throw new IOException("snapshot limit reached; no snapshots deleted");
            }
        }
    }

    private void requireExistingDirectory() throws IOException {
        for (Path path : new Path[]{laboratoryRoot, projectRoot, snapshotRoot}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("snapshot vault directory missing or unsafe");
            }
        }
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Recheck instead of following an object another writer created.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe snapshot vault directory");
        }
    }

    private static boolean validLabel(String label) {
        return label != null && label.matches("[a-z0-9][a-z0-9_-]{0,47}");
    }

    public static boolean validId(String id) {
        try {
            return id != null && UUID.fromString(id).toString().equals(id);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static String hexSha256(byte[] bytes) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder hex = new StringBuilder(64);
            for (byte value : hash) {
                hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
