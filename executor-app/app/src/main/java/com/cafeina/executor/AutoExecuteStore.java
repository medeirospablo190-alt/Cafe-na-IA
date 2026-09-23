package com.cafeina.executor;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

public final class AutoExecuteStore {
    private final Path file;

    public AutoExecuteStore(File appFilesDirectory) {
        this(appFilesDirectory.toPath().resolve("autoexecute.txt"));
    }

    public AutoExecuteStore(Path file) {
        this.file = file.toAbsolutePath().normalize();
    }

    public Set<String> load() throws IOException {
        if (!Files.exists(file)) {
            return Collections.emptySet();
        }
        if (!Files.isRegularFile(file)) {
            throw new IOException("autoexecute path is not a file");
        }

        LinkedHashSet<String> names = new LinkedHashSet<>();
        for (String line : Files.readAllLines(file, StandardCharsets.UTF_8)) {
            if (line.isEmpty()) continue;
            if (!ScriptStore.isValidName(line)) continue;
            names.add(line);
        }
        return Collections.unmodifiableSet(names);
    }

    public void save(Set<String> names) throws IOException {
        LinkedHashSet<String> validated = new LinkedHashSet<>();
        if (names != null) {
            for (String name : names) {
                if (!ScriptStore.isValidName(name)) {
                    throw new IllegalArgumentException("invalid autoexecute script name");
                }
                validated.add(name);
            }
        }

        Path parent = file.getParent();
        if (parent == null) {
            throw new IOException("autoexecute file has no parent");
        }
        Files.createDirectories(parent);

        Path temp = parent.resolve("." + file.getFileName() + ".tmp-" + UUID.randomUUID()).normalize();
        boolean committed = false;

        try {
            StringBuilder body = new StringBuilder();
            for (String name : validated) {
                body.append(name).append('\n');
            }

            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            try (FileOutputStream output = new FileOutputStream(temp.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }

            try {
                Files.move(
                    temp,
                    file,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                );
            } catch (AtomicMoveNotSupportedException unsupported) {
                Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING);
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
}
