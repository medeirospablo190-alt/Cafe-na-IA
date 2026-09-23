package com.cafeina.executor;

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
import java.util.List;
import java.util.UUID;

public final class ProjectStore {
    public static final int STORAGE_VERSION = 1;
    public static final int MAX_ID_LENGTH = 64;

    private static final String MARKER_NAME = ".cafeina-project";
    private static final String MARKER_BODY = "CAFEINA_PROJECT\n" + STORAGE_VERSION + "\n";

    private final Path projectsDirectory;

    public ProjectStore(File appFilesDirectory) {
        this(appFilesDirectory.toPath().resolve("projects"));
    }

    public ProjectStore(Path projectsDirectory) {
        this.projectsDirectory = projectsDirectory.toAbsolutePath().normalize();
    }

    public Path projectsDirectory() {
        return projectsDirectory;
    }

    public Project create(String projectId) throws IOException {
        String safeId = validateId(projectId);
        ensureProjectsDirectory();

        Path root = resolveSafeProjectRoot(safeId);
        if (Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("project already exists: " + safeId);
        }

        Files.createDirectory(root);
        boolean complete = false;
        try {
            createProjectDirectories(root);
            writeMarker(root);
            complete = true;
            return new Project(safeId, root);
        } finally {
            if (!complete) {
                deleteNewProjectTree(root);
            }
        }
    }

    public Project open(String projectId) throws IOException {
        String safeId = validateId(projectId);
        ensureProjectsDirectory();

        Path root = resolveSafeProjectRoot(safeId);
        validateProjectRoot(root);
        validateMarker(root);
        validateProjectDirectories(root);

        return new Project(safeId, root);
    }

    public boolean exists(String projectId) {
        String safeId = validateId(projectId);
        Path root = resolveSafeProjectRoot(safeId);

        try {
            validateProjectRoot(root);
            validateMarker(root);
            validateProjectDirectories(root);
            return true;
        } catch (IOException ignored) {
            return false;
        }
    }

    public List<String> listProjectIds() throws IOException {
        ensureProjectsDirectory();

        List<String> ids = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(projectsDirectory)) {
            stream.forEach(path -> {
                String name = path.getFileName().toString();
                if (!isValidId(name)) {
                    return;
                }

                try {
                    validateProjectRoot(path);
                    validateMarker(path);
                    validateProjectDirectories(path);
                    ids.add(name);
                } catch (IOException ignored) {
                    // Incomplete, corrupted or foreign directories are not projects.
                }
            });
        }

        ids.sort((left, right) -> {
            int folded = left.compareToIgnoreCase(right);
            return folded != 0 ? folded : left.compareTo(right);
        });
        return Collections.unmodifiableList(ids);
    }

    public static boolean isValidId(String projectId) {
        if (projectId == null || projectId.isEmpty() || projectId.length() > MAX_ID_LENGTH) {
            return false;
        }

        for (int i = 0; i < projectId.length(); i++) {
            char c = projectId.charAt(i);
            boolean allowed =
                (c >= 'a' && c <= 'z') ||
                (c >= '0' && c <= '9') ||
                c == '-' ||
                c == '_';

            if (!allowed) {
                return false;
            }
        }

        char first = projectId.charAt(0);
        return (first >= 'a' && first <= 'z') || (first >= '0' && first <= '9');
    }

    private static String validateId(String projectId) {
        if (!isValidId(projectId)) {
            throw new IllegalArgumentException("invalid project id");
        }
        return projectId;
    }

    private void ensureProjectsDirectory() throws IOException {
        Files.createDirectories(projectsDirectory);

        if (Files.isSymbolicLink(projectsDirectory) || !Files.isDirectory(projectsDirectory, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("projects path is not a safe directory");
        }
    }

    private Path resolveSafeProjectRoot(String projectId) {
        Path root = projectsDirectory.resolve(projectId).normalize();
        if (!projectsDirectory.equals(root.getParent())) {
            throw new IllegalArgumentException("project path escaped projects directory");
        }
        return root;
    }

    private static void createProjectDirectories(Path root) throws IOException {
        Files.createDirectory(root.resolve("scripts"));
        Files.createDirectory(root.resolve("runtime-fs"));
        Files.createDirectory(root.resolve("worlds"));
        Files.createDirectory(root.resolve("assets"));
        Files.createDirectory(root.resolve("snapshots"));
    }

    private static void validateProjectRoot(Path root) throws IOException {
        if (Files.isSymbolicLink(root) || !Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("project not found or unsafe");
        }
    }

    private static void validateProjectDirectories(Path root) throws IOException {
        requireSafeDirectory(root.resolve("scripts"), "scripts");
        requireSafeDirectory(root.resolve("runtime-fs"), "runtime-fs");
        requireSafeDirectory(root.resolve("worlds"), "worlds");
        requireSafeDirectory(root.resolve("assets"), "assets");
        requireSafeDirectory(root.resolve("snapshots"), "snapshots");
    }

    private static void requireSafeDirectory(Path path, String name) throws IOException {
        if (Files.isSymbolicLink(path) || !Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("project directory missing or unsafe: " + name);
        }
    }

    private static void writeMarker(Path root) throws IOException {
        byte[] bytes = MARKER_BODY.getBytes(StandardCharsets.UTF_8);
        Path marker = root.resolve(MARKER_NAME);
        Path temp = root.resolve("." + MARKER_NAME + ".tmp-" + UUID.randomUUID());

        boolean committed = false;
        try {
            try (FileOutputStream output = new FileOutputStream(temp.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }

            try {
                Files.move(temp, marker, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temp, marker);
            }

            committed = true;
        } finally {
            if (!committed) {
                Files.deleteIfExists(temp);
            }
        }
    }

    private static void validateMarker(Path root) throws IOException {
        Path marker = root.resolve(MARKER_NAME);
        if (Files.isSymbolicLink(marker) || !Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("project marker missing or unsafe");
        }

        byte[] bytes = Files.readAllBytes(marker);
        String body = new String(bytes, StandardCharsets.UTF_8);
        if (!MARKER_BODY.equals(body)) {
            throw new IOException("unsupported or corrupted project storage version");
        }
    }

    private static void deleteNewProjectTree(Path root) {
        try {
            if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(root)) {
                return;
            }

            try (java.util.stream.Stream<Path> stream = Files.walk(root)) {
                stream
                    .sorted((left, right) -> right.getNameCount() - left.getNameCount())
                    .forEach(path -> {
                        try {
                            Files.deleteIfExists(path);
                        } catch (IOException ignored) {
                        }
                    });
            }
        } catch (IOException ignored) {
        }
    }

    public static final class Project {
        private final String id;
        private final Path root;

        private Project(String id, Path root) {
            this.id = id;
            this.root = root;
        }

        public String id() {
            return id;
        }

        public Path root() {
            return root;
        }

        public Path scriptsDirectory() {
            return root.resolve("scripts");
        }

        public Path runtimeFilesDirectory() {
            return root.resolve("runtime-fs");
        }

        public Path worldsDirectory() {
            return root.resolve("worlds");
        }

        public Path assetsDirectory() {
            return root.resolve("assets");
        }

        public Path snapshotsDirectory() {
            return root.resolve("snapshots");
        }
    }
}
