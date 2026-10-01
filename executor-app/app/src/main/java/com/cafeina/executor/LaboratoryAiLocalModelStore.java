package com.cafeina.executor;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;

/**
 * Explicit app-private import path for local GGUF files.
 *
 * Import is content-addressed by SHA-256, bounded by the same size limit used by
 * admission, writes through a temporary file, fsyncs before publish, and never
 * overwrites an existing model. It does not download models and does not open
 * the native runtime.
 */
public final class LaboratoryAiLocalModelStore {
    private static final int COPY_BUFFER_BYTES = 64 * 1024;
    private static final byte[] GGUF_MAGIC = new byte[] {
        0x47, 0x47, 0x55, 0x46
    };

    public static final class ImportResult {
        public final File modelFile;
        public final String sha256;
        public final long sizeBytes;
        public final boolean duplicate;

        private ImportResult(
                File modelFile,
                String sha256,
                long sizeBytes,
                boolean duplicate) {
            this.modelFile = modelFile;
            this.sha256 = sha256;
            this.sizeBytes = sizeBytes;
            this.duplicate = duplicate;
        }
    }

    private LaboratoryAiLocalModelStore() {}

    /**
     * Copy one caller-provided stream into files/models.
     *
     * The caller retains ownership of the InputStream and must close it.
     */
    public static ImportResult importGguf(
            File appFilesDirectory,
            InputStream input) throws IOException {
        if (appFilesDirectory == null || input == null) {
            throw new IllegalArgumentException(
                "local model import input missing");
        }

        Path modelsRoot = ensureModelDirectory(appFilesDirectory);
        Path temp = Files.createTempFile(
            modelsRoot, ".cafeina-model-", ".part");

        boolean published = false;
        try {
            MessageDigest digest = sha256();
            byte[] buffer = new byte[COPY_BUFFER_BYTES];
            byte[] header = new byte[GGUF_MAGIC.length];
            int headerBytes = 0;
            long total = 0L;

            try (FileOutputStream output =
                    new FileOutputStream(temp.toFile())) {
                while (true) {
                    int read = input.read(buffer);
                    if (read < 0) break;
                    if (read == 0) continue;

                    if (total > LaboratoryAiLocalModelAdmission.MAX_MODEL_BYTES
                            - read) {
                        throw new IOException(
                            "local model import exceeds size limit");
                    }

                    if (headerBytes < header.length) {
                        int copy = Math.min(
                            read, header.length - headerBytes);
                        System.arraycopy(
                            buffer, 0, header, headerBytes, copy);
                        headerBytes += copy;
                    }

                    digest.update(buffer, 0, read);
                    output.write(buffer, 0, read);
                    total += read;
                }
                output.getFD().sync();
            }

            requireGgufHeader(header, headerBytes);
            if (total < GGUF_MAGIC.length) {
                throw new IOException(
                    "local model import is too small");
            }

            String sha = hex(digest.digest());
            Path target = modelsRoot.resolve(sha + ".gguf");
            boolean duplicate = false;

            if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
                verifyExisting(target, total, sha);
                duplicate = true;
            } else {
                try {
                    publish(temp, target);
                    published = true;
                } catch (FileAlreadyExistsException concurrentImport) {
                    verifyExisting(target, total, sha);
                    duplicate = true;
                }
            }

            Path finalPath = target.toRealPath(
                LinkOption.NOFOLLOW_LINKS);
            LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
                LaboratoryAiLocalModelAdmission.admit(
                    appFilesDirectory, finalPath.toFile());

            if (admitted.sizeBytes != total) {
                throw new IOException(
                    "imported local model size changed after publish");
            }

            return new ImportResult(
                finalPath.toFile(),
                sha,
                total,
                duplicate);
        } finally {
            if (!published || Files.exists(temp, LinkOption.NOFOLLOW_LINKS)) {
                Files.deleteIfExists(temp);
            }
        }
    }

    static Path ensureModelDirectory(
            File appFilesDirectory) throws IOException {
        Path appRoot = appFilesDirectory.toPath()
            .toAbsolutePath().normalize();
        if (!Files.isDirectory(appRoot, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(appRoot)) {
            throw new IOException(
                "app files directory is unsafe for local model import");
        }

        Path modelsRoot = appRoot.resolve("models").normalize();
        if (Files.exists(modelsRoot, LinkOption.NOFOLLOW_LINKS)) {
            if (!Files.isDirectory(modelsRoot, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(modelsRoot)) {
                throw new IOException(
                    "local model directory is unsafe");
            }
        } else {
            Files.createDirectory(modelsRoot);
        }

        if (!Files.isDirectory(modelsRoot, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(modelsRoot)) {
            throw new IOException(
                "local model directory could not be created safely");
        }
        return modelsRoot.toRealPath(LinkOption.NOFOLLOW_LINKS);
    }

    private static void publish(Path temp, Path target)
            throws IOException {
        try {
            Files.move(temp, target, StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException ignored) {
            Files.move(temp, target);
        }
    }

    private static void verifyExisting(
            Path target,
            long expectedSize,
            String expectedSha) throws IOException {
        if (!Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(target)
                || Files.size(target) != expectedSize) {
            throw new IOException(
                "existing local model conflicts with imported content");
        }

        String actualSha = hashFile(target);
        if (!expectedSha.equals(actualSha)) {
            throw new IOException(
                "existing local model hash does not match its content address");
        }
    }

    private static String hashFile(Path path) throws IOException {
        MessageDigest digest = sha256();
        byte[] buffer = new byte[COPY_BUFFER_BYTES];
        long total = 0L;
        try (InputStream input = Files.newInputStream(path)) {
            while (true) {
                int read = input.read(buffer);
                if (read < 0) break;
                if (read == 0) continue;
                if (total > LaboratoryAiLocalModelAdmission.MAX_MODEL_BYTES
                        - read) {
                    throw new IOException(
                        "existing local model exceeds size limit");
                }
                digest.update(buffer, 0, read);
                total += read;
            }
        }
        return hex(digest.digest());
    }

    private static void requireGgufHeader(
            byte[] header,
            int headerBytes) throws IOException {
        if (headerBytes != GGUF_MAGIC.length) {
            throw new IOException(
                "local model import has incomplete GGUF header");
        }
        for (int i = 0; i < GGUF_MAGIC.length; i++) {
            if (header[i] != GGUF_MAGIC[i]) {
                throw new IOException(
                    "local model import is not a GGUF file");
            }
        }
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(
                "SHA-256 unavailable", impossible);
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(
            bytes.length * 2);
        for (byte value : bytes) {
            result.append(String.format(
                Locale.ROOT, "%02x", value & 0xff));
        }
        return result.toString();
    }
}
