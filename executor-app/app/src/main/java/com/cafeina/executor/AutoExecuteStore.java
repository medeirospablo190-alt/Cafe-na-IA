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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

public final class AutoExecuteStore {
    public static final int MAX_ENTRIES = 32;
    private static final int MAX_METADATA_BYTES = 64 * 1024;

    private final Path metadataPath;

    public AutoExecuteStore(File appFilesDirectory) {
        this(appFilesDirectory.toPath().resolve("autoexec.list"));
    }

    public AutoExecuteStore(Path metadataPath) {
        this.metadataPath = metadataPath.toAbsolutePath().normalize();
    }

    public Path metadataPath() {
        return metadataPath;
    }

    public synchronized boolean isEnabled(String scriptName) throws IOException {
        return new LinkedHashSet<>(enabledScripts()).contains(validateName(scriptName));
    }

    public synchronized List<String> enabledScripts() throws IOException {
        if (!Files.exists(metadataPath)) {
            return Collections.emptyList();
        }

        if (!Files.isRegularFile(metadataPath)) {
            throw new IOException("autoexec metadata path is not a file");
        }

        long size = Files.size(metadataPath);
        if (size > MAX_METADATA_BYTES) {
            throw new IOException("autoexec metadata exceeds " + MAX_METADATA_BYTES + " bytes");
        }

        List<String> lines = Files.readAllLines(metadataPath, StandardCharsets.UTF_8);
        LinkedHashSet<String> valid = new LinkedHashSet<>();

        for (String line : lines) {
            String name = line == null ? "" : line.trim();
            if (ScriptStore.isValidName(name)) {
                valid.add(name);
            }
            if (valid.size() >= MAX_ENTRIES) {
                break;
            }
        }

        return Collections.unmodifiableList(new ArrayList<>(valid));
    }

    public synchronized void setEnabled(String scriptName, boolean enabled) throws IOException {
        String safeName = validateName(scriptName);
        LinkedHashSet<String> entries = new LinkedHashSet<>(enabledScripts());

        if (enabled) {
            if (!entries.contains(safeName) && entries.size() >= MAX_ENTRIES) {
                throw new IOException("autoexec entry limit reached");
            }
            entries.add(safeName);
        } else {
            entries.remove(safeName);
        }

        writeEntries(entries);
    }

    private void writeEntries(Set<String> entries) throws IOException {
        Path parent = metadataPath.getParent();
        if (parent == null) {
            throw new IOException("autoexec metadata has no parent directory");
        }
        Files.createDirectories(parent);

        StringBuilder body = new StringBuilder();
        for (String name : entries) {
            body.append(name).append('\n');
        }
        byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);

        if (bytes.length > MAX_METADATA_BYTES) {
            throw new IOException("autoexec metadata exceeds " + MAX_METADATA_BYTES + " bytes");
        }

        Path temp = parent.resolve("." + metadataPath.getFileName() + ".tmp-" + UUID.randomUUID()).normalize();
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
                    metadataPath,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                );
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temp, metadataPath, StandardCopyOption.REPLACE_EXISTING);
            }

            committed = true;
        } finally {
            if (!committed) {
                try {
                    Files.deleteIfExists(temp);
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static String validateName(String name) {
        if (!ScriptStore.isValidName(name)) {
            throw new IllegalArgumentException("invalid autoexec script name");
        }
        return name;
    }
}
