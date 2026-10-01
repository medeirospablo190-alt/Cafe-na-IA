package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;

public final class LaboratoryAiLocalModelStoreTest {
    @Test
    public void importsGgufIntoContentAddressedPrivateFile()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-import");
        byte[] model = fakeGguf((byte) 0x21);

        LaboratoryAiLocalModelStore.ImportResult result =
            LaboratoryAiLocalModelStore.importGguf(
                app.toFile(),
                new ByteArrayInputStream(model));

        assertFalse(result.duplicate);
        assertEquals(model.length, result.sizeBytes);
        assertEquals(sha256(model), result.sha256);
        assertEquals(
            result.sha256 + ".gguf",
            result.modelFile.getName());
        assertTrue(result.modelFile.isFile());
        assertEquals(
            app.resolve("models").toRealPath().toFile(),
            result.modelFile.getParentFile());

        LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
            LaboratoryAiLocalModelAdmission.admit(
                app.toFile(), result.modelFile);
        assertEquals(result.sizeBytes, admitted.sizeBytes);
    }

    @Test
    public void duplicateImportReusesExistingContentAddress()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-dedup");
        byte[] model = fakeGguf((byte) 0x42);

        LaboratoryAiLocalModelStore.ImportResult first =
            LaboratoryAiLocalModelStore.importGguf(
                app.toFile(),
                new ByteArrayInputStream(model));
        LaboratoryAiLocalModelStore.ImportResult second =
            LaboratoryAiLocalModelStore.importGguf(
                app.toFile(),
                new ByteArrayInputStream(model));

        assertFalse(first.duplicate);
        assertTrue(second.duplicate);
        assertEquals(first.sha256, second.sha256);
        assertEquals(
            first.modelFile.getCanonicalFile(),
            second.modelFile.getCanonicalFile());

        long ggufFiles;
        try (java.util.stream.Stream<Path> stream =
                Files.list(app.resolve("models"))) {
            ggufFiles = stream
                .filter(path -> path.getFileName().toString()
                    .endsWith(".gguf"))
                .count();
        }
        assertEquals(1L, ggufFiles);
    }

    @Test
    public void invalidHeaderLeavesNoPublishedOrTemporaryModel()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-bad");
        byte[] invalid = new byte[] {
            0x00, 0x01, 0x02, 0x03, 0x55, 0x66
        };

        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelStore.importGguf(
                app.toFile(),
                new ByteArrayInputStream(invalid)));

        Path models = app.resolve("models");
        assertTrue(Files.isDirectory(models));
        try (java.util.stream.Stream<Path> stream =
                Files.list(models)) {
            assertEquals(0L, stream.count());
        }
    }

    @Test
    public void unsafeExistingModelDirectoryIsRejected()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-dir");
        Path regularFile = app.resolve("models");
        Files.write(regularFile, new byte[] { 0x01 });

        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelStore.importGguf(
                app.toFile(),
                new ByteArrayInputStream(fakeGguf((byte) 0x11))));
    }

    private static byte[] fakeGguf(byte marker) {
        return new byte[] {
            0x47, 0x47, 0x55, 0x46,
            0x03, 0x00, 0x00, 0x00,
            marker, (byte) (marker + 1)
        };
    }

    private static String sha256(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256")
            .digest(bytes);
        StringBuilder result = new StringBuilder();
        for (byte value : digest) {
            result.append(String.format(
                java.util.Locale.ROOT,
                "%02x",
                value & 0xff));
        }
        return result.toString();
    }
}
