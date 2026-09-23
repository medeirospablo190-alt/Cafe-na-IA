package com.cafeina.executor;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

public final class ScriptStore {
    public static final int MAX_NAME_LENGTH = 80;
    public static final int MAX_SCRIPT_BYTES = 2 * 1024 * 1024;

    private final Path directory;

    public ScriptStore(File appFilesDirectory) {
        this(appFilesDirectory.toPath().resolve("scripts"));
    }

    public ScriptStore(Path directory) {
        this.directory = directory.toAbsolutePath().normalize();
    }

    public Path directory() {
        return directory;
    }

    public void save(String name, String content) throws IOException {
        String safeName = validateName(name);
        String safeContent = content == null ? "" : content;
        byte[] bytes = safeContent.getBytes(StandardCharsets.UTF_8);

        if (bytes.length > MAX_SCRIPT_BYTES) {
            throw new IllegalArgumentException("script exceeds " + MAX_SCRIPT_BYTES + " bytes");
        }

        ensureDirectory();

        Path target = resolveSafe(safeName);
        Path temp = directory.resolve("." + safeName + ".tmp-" + UUID.randomUUID()).normalize();

        if (!temp.getParent().equals(directory)) {
            throw new IllegalStateException("temporary path escaped scripts directory");
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
                    target,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                );
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING);
            }

            committed = true;
        } finally {
            if (!committed) {
                try {
                    Files.deleteIfExists(temp);
                } catch (IOException ignored) {
                    // A leftover temp file is ignored by listScripts and never replaces user data.
                }
            }
        }
    }

    public String load(String name) throws IOException {
        String safeName = validateName(name);
        Path target = resolveSafe(safeName);

        if (!Files.isRegularFile(target)) {
            throw new IOException("script not found: " + safeName);
        }

        long size = Files.size(target);
        if (size > MAX_SCRIPT_BYTES) {
            throw new IOException("script exceeds " + MAX_SCRIPT_BYTES + " bytes");
        }

        return new String(Files.readAllBytes(target), StandardCharsets.UTF_8);
    }

    public boolean exists(String name) {
        String safeName = validateName(name);
        return Files.isRegularFile(resolveSafe(safeName));
    }

    public List<String> listScripts() throws IOException {
        ensureDirectory();

        List<String> names = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(directory)) {
            stream
                .filter(Files::isRegularFile)
                .map(path -> path.getFileName().toString())
                .filter(ScriptStore::isValidName)
                .forEach(names::add);
        }

        names.sort(Comparator.comparing(String::toLowerCase).thenComparing(String::compareTo));
        return Collections.unmodifiableList(names);
    }

    public static boolean isValidName(String name) {
        if (name == null) return false;
        if (name.length() < 5 || name.length() > MAX_NAME_LENGTH) return false;
        if (!name.equals(name.trim())) return false;
        if (!name.endsWith(".lua")) return false;
        if (name.startsWith(".")) return false;
        if (name.contains("..")) return false;
        if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) return false;

        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            if (Character.isISOControl(c)) return false;
        }

        return true;
    }

    private static String validateName(String name) {
        if (!isValidName(name)) {
            throw new IllegalArgumentException("invalid script name");
        }
        return name;
    }

    private void ensureDirectory() throws IOException {
        Files.createDirectories(directory);
        if (!Files.isDirectory(directory)) {
            throw new IOException("scripts path is not a directory");
        }
    }

    private Path resolveSafe(String name) {
        Path resolved = directory.resolve(name).normalize();
        if (!resolved.getParent().equals(directory)) {
            throw new IllegalArgumentException("script path escaped scripts directory");
        }
        return resolved;
    }
}
