package com.cafeina.executor;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

public final class WorldDocumentStore {
    public static final String MAIN_WORLD_FILE = "main.cafeina-world.json";
    public static final int MAX_WORLD_BYTES = 16 * 1024 * 1024;

    private final Path worldsDirectory;
    private final Path worldFile;

    public WorldDocumentStore(ProjectStore.Project project) {
        this(project.worldsDirectory());
    }

    WorldDocumentStore(Path worldsDirectory) {
        this.worldsDirectory = worldsDirectory.toAbsolutePath().normalize();
        this.worldFile = this.worldsDirectory.resolve(MAIN_WORLD_FILE).normalize();

        if (!this.worldsDirectory.equals(this.worldFile.getParent())) {
            throw new IllegalArgumentException("world file escaped project worlds directory");
        }
    }

    public Path worldFile() {
        return worldFile;
    }

    public boolean exists() throws IOException {
        requireSafeWorldsDirectory();

        if (!Files.exists(worldFile, LinkOption.NOFOLLOW_LINKS)) {
            return false;
        }

        requireSafeWorldFile();
        return true;
    }

    public String load() throws IOException {
        requireSafeWorldsDirectory();
        requireSafeWorldFile();

        long size = Files.size(worldFile);
        if (size > MAX_WORLD_BYTES) {
            throw new IOException("world file exceeds size limit");
        }

        byte[] bytes = Files.readAllBytes(worldFile);
        return new String(bytes, StandardCharsets.UTF_8);
    }

    public void save(String worldJson) throws IOException {
        if (worldJson == null) {
            throw new IllegalArgumentException("world JSON must not be null");
        }

        byte[] bytes = worldJson.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_WORLD_BYTES) {
            throw new IOException("world JSON exceeds size limit");
        }

        requireSafeWorldsDirectory();

        if (
            Files.exists(worldFile, LinkOption.NOFOLLOW_LINKS)
                && Files.isSymbolicLink(worldFile)
        ) {
            throw new IOException("world file is an unsafe symbolic link");
        }

        Path temp = worldsDirectory.resolve(
            "." + MAIN_WORLD_FILE + ".tmp-" + UUID.randomUUID()
        ).normalize();

        if (!worldsDirectory.equals(temp.getParent())) {
            throw new IOException("temporary world file escaped project directory");
        }

        boolean committed = false;
        try {
            try (FileOutputStream output = new FileOutputStream(temp.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }

            try {
                Files.move(
                    temp,
                    worldFile,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                );
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(
                    temp,
                    worldFile,
                    StandardCopyOption.REPLACE_EXISTING
                );
            }

            committed = true;
        } finally {
            if (!committed) {
                Files.deleteIfExists(temp);
            }
        }
    }

    private void requireSafeWorldsDirectory() throws IOException {
        if (
            Files.isSymbolicLink(worldsDirectory)
                || !Files.isDirectory(worldsDirectory, LinkOption.NOFOLLOW_LINKS)
        ) {
            throw new IOException("project worlds path is not a safe directory");
        }
    }

    private void requireSafeWorldFile() throws IOException {
        if (
            Files.isSymbolicLink(worldFile)
                || !Files.isRegularFile(worldFile, LinkOption.NOFOLLOW_LINKS)
        ) {
            throw new IOException("world file not found or unsafe");
        }
    }
}
