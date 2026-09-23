package com.cafeina.executor;

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
import java.util.List;
import java.util.UUID;

public final class ProjectSnapshotStore {
    public static final int MAX_SNAPSHOT_BYTES = 16 * 1024 * 1024;
    public static final int MAX_SNAPSHOT_ID_LENGTH = 64;

    private final Path snapshotsDirectory;

    public ProjectSnapshotStore(ProjectStore.Project project) {
        this.snapshotsDirectory = project.snapshotsDirectory().toAbsolutePath().normalize();
    }

    public Path snapshotFile(String snapshotId) {
        String safeId = validateId(snapshotId);
        Path file = snapshotsDirectory.resolve(safeId + ".cafeina-world.json").normalize();
        if (!snapshotsDirectory.equals(file.getParent())) {
            throw new IllegalArgumentException("snapshot path escaped project directory");
        }
        return file;
    }

    public void save(String snapshotId, String worldJson) throws IOException {
        if (worldJson == null) throw new IllegalArgumentException("snapshot JSON must not be null");
        byte[] bytes = worldJson.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_SNAPSHOT_BYTES) throw new IOException("snapshot exceeds size limit");
        requireSafeDirectory();
        Path file = snapshotFile(snapshotId);
        if (Files.exists(file, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("snapshot already exists: " + snapshotId);
        }
        Path temp = snapshotsDirectory.resolve("." + file.getFileName() + ".tmp-" + UUID.randomUUID()).normalize();
        boolean committed = false;
        try {
            try (FileOutputStream output = new FileOutputStream(temp.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            try {
                Files.move(temp, file, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temp, file);
            }
            committed = true;
        } finally {
            if (!committed) Files.deleteIfExists(temp);
        }
    }

    public String load(String snapshotId) throws IOException {
        requireSafeDirectory();
        Path file = snapshotFile(snapshotId);
        requireSafeFile(file);
        if (Files.size(file) > MAX_SNAPSHOT_BYTES) throw new IOException("snapshot exceeds size limit");
        return new String(Files.readAllBytes(file), StandardCharsets.UTF_8);
    }

    public List<String> listSnapshotIds() throws IOException {
        requireSafeDirectory();
        List<String> ids = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(snapshotsDirectory)) {
            stream.forEach(path -> {
                String name = path.getFileName().toString();
                String suffix = ".cafeina-world.json";
                if (!name.endsWith(suffix)) return;
                String id = name.substring(0, name.length() - suffix.length());
                if (!isValidId(id)) return;
                try {
                    requireSafeFile(path);
                    if (Files.size(path) <= MAX_SNAPSHOT_BYTES) ids.add(id);
                } catch (IOException ignored) {
                }
            });
        }
        Collections.sort(ids);
        return Collections.unmodifiableList(ids);
    }

    public static boolean isValidId(String id) {
        if (id == null || id.isEmpty() || id.length() > MAX_SNAPSHOT_ID_LENGTH) return false;
        for (int i = 0; i < id.length(); i++) {
            char c = id.charAt(i);
            if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
        }
        char first = id.charAt(0);
        return (first >= 'a' && first <= 'z') || (first >= '0' && first <= '9');
    }

    private static String validateId(String id) {
        if (!isValidId(id)) throw new IllegalArgumentException("invalid snapshot id");
        return id;
    }

    private void requireSafeDirectory() throws IOException {
        if (Files.isSymbolicLink(snapshotsDirectory) || !Files.isDirectory(snapshotsDirectory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("project snapshots path is not a safe directory");
        }
    }

    private static void requireSafeFile(Path file) throws IOException {
        if (Files.isSymbolicLink(file) || !Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("snapshot not found or unsafe");
        }
    }
}
