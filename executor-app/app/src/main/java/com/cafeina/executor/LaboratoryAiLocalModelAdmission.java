package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.Locale;

/**
 * Read-only admission gate for local GGUF files before the native runtime is
 * allowed to open them.
 *
 * Models must already have been copied into the app-private files/models
 * directory by a separate, explicit import flow. This class never downloads,
 * copies, deletes, executes, or mutates model files.
 */
public final class LaboratoryAiLocalModelAdmission {
    public static final long MAX_MODEL_BYTES =
        8L * 1024L * 1024L * 1024L;

    private static final byte[] GGUF_MAGIC = new byte[] {
        0x47, 0x47, 0x55, 0x46
    };

    public static final class AdmittedModel {
        public final String fileName;
        public final long sizeBytes;
        private final File file;

        private AdmittedModel(File file, long sizeBytes) {
            this.file = file;
            this.fileName = file.getName();
            this.sizeBytes = sizeBytes;
        }

        File fileForRuntime() {
            return file;
        }
    }

    private LaboratoryAiLocalModelAdmission() {}

    public static File modelDirectory(File appFilesDirectory) {
        if (appFilesDirectory == null) {
            throw new IllegalArgumentException(
                "app files directory missing for local model");
        }
        return new File(appFilesDirectory, "models");
    }

    public static AdmittedModel admit(
            File appFilesDirectory,
            File modelFile) throws IOException {
        if (appFilesDirectory == null || modelFile == null) {
            throw new IllegalArgumentException(
                "local model admission input missing");
        }

        Path appRoot = appFilesDirectory.toPath()
            .toAbsolutePath().normalize();
        if (!Files.isDirectory(appRoot, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(appRoot)) {
            throw new IOException(
                "app files directory is unsafe for local model admission");
        }

        Path modelsRoot = appRoot.resolve("models").normalize();
        if (!Files.isDirectory(modelsRoot, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(modelsRoot)) {
            throw new IOException(
                "app-private local model directory is missing or unsafe");
        }

        Path candidate = modelFile.toPath()
            .toAbsolutePath().normalize();
        if (!Files.isRegularFile(candidate, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(candidate)) {
            throw new IOException(
                "local model is missing, not regular, or is a symbolic link");
        }

        Path realRoot = modelsRoot.toRealPath(LinkOption.NOFOLLOW_LINKS);
        Path realCandidate =
            candidate.toRealPath(LinkOption.NOFOLLOW_LINKS);
        if (realCandidate.getParent() == null
                || !realCandidate.getParent().equals(realRoot)) {
            throw new IOException(
                "local model resolved outside the admitted directory");
        }

        String fileName = realCandidate.getFileName().toString();
        String lowerName = fileName.toLowerCase(Locale.ROOT);
        if (fileName.length() > 160
                || !fileName.matches("[A-Za-z0-9][A-Za-z0-9._-]*")
                || !lowerName.endsWith(".gguf")) {
            throw new IOException("local model filename is not admitted");
        }

        long sizeBytes = Files.size(realCandidate);
        if (sizeBytes < GGUF_MAGIC.length
                || sizeBytes > MAX_MODEL_BYTES) {
            throw new IOException("local model size is not admitted");
        }

        byte[] header = new byte[GGUF_MAGIC.length];
        int offset = 0;
        try (InputStream input = Files.newInputStream(realCandidate)) {
            while (offset < header.length) {
                int read = input.read(
                    header, offset, header.length - offset);
                if (read < 0) break;
                offset += read;
            }
        }
        if (offset != header.length) {
            throw new IOException("local model header is incomplete");
        }
        for (int i = 0; i < GGUF_MAGIC.length; i++) {
            if (header[i] != GGUF_MAGIC[i]) {
                throw new IOException(
                    "local model does not have a GGUF header");
            }
        }

        return new AdmittedModel(
            realCandidate.toFile(),
            sizeBytes);
    }
}
