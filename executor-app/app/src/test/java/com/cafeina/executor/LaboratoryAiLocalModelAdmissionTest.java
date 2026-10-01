package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

public final class LaboratoryAiLocalModelAdmissionTest {
    @Test
    public void admitsOnlyAppPrivateGgufCandidate() throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-admission");
        Path models = Files.createDirectory(app.resolve("models"));
        Path model = models.resolve("planner-q4.gguf");
        Files.write(model, new byte[] {
            0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00
        });

        LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
            LaboratoryAiLocalModelAdmission.admit(
                app.toFile(), model.toFile());

        assertEquals("planner-q4.gguf", admitted.fileName);
        assertEquals(8L, admitted.sizeBytes);
        assertEquals(
            model.toRealPath().toFile(),
            admitted.fileForRuntime());
    }

    @Test
    public void acceptsCanonicalCandidateWhenAncestorAliasDiffers()
            throws Exception {
        Path base = Files.createTempDirectory("cafeina-model-alias");
        Path realParent = Files.createDirectory(base.resolve("real"));
        Path app = Files.createDirectory(realParent.resolve("app"));
        Path models = Files.createDirectory(app.resolve("models"));
        Path model = models.resolve("planner.gguf");
        Files.write(model, new byte[] {
            0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00
        });

        Path aliasParent = base.resolve("alias");
        Files.createSymbolicLink(aliasParent, realParent);
        File aliasedApp = aliasParent.resolve("app").toFile();
        File canonicalModel = aliasParent.resolve("app")
            .resolve("models")
            .resolve("planner.gguf")
            .toFile()
            .getCanonicalFile();

        LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
            LaboratoryAiLocalModelAdmission.admit(
                aliasedApp, canonicalModel);

        assertEquals("planner.gguf", admitted.fileName);
        assertEquals(8L, admitted.sizeBytes);
        assertEquals(
            model.toRealPath().toFile(),
            admitted.fileForRuntime());
    }

    @Test
    public void rejectsReadableGgufOutsidePrivateModelDirectory()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-root");
        Files.createDirectory(app.resolve("models"));
        Path outside = Files.createTempFile(
            "outside-cafeina-model", ".gguf");
        Files.write(outside, new byte[] {
            0x47, 0x47, 0x55, 0x46
        });

        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelAdmission.admit(
                app.toFile(), outside.toFile()));
    }

    @Test
    public void rejectsNonGgufHeaderAndNonGgufName() throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-invalid");
        Path models = Files.createDirectory(app.resolve("models"));

        Path wrongHeader = models.resolve("wrong.gguf");
        Files.write(wrongHeader, new byte[] {
            0x00, 0x01, 0x02, 0x03
        });
        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelAdmission.admit(
                app.toFile(), wrongHeader.toFile()));

        Path wrongName = models.resolve("model.bin");
        Files.write(wrongName, new byte[] {
            0x47, 0x47, 0x55, 0x46
        });
        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelAdmission.admit(
                app.toFile(), wrongName.toFile()));
    }

    @Test
    public void rejectsSymbolicLinkEvenWhenItPointsToGguf()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-link");
        Path models = Files.createDirectory(app.resolve("models"));
        Path target = Files.createTempFile(
            "cafeina-model-link-target", ".gguf");
        Files.write(target, new byte[] {
            0x47, 0x47, 0x55, 0x46
        });
        Path link = models.resolve("linked.gguf");
        Files.createSymbolicLink(link, target);

        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelAdmission.admit(
                app.toFile(), link.toFile()));
    }

    @Test
    public void missingPrivateModelDirectoryIsNotCreatedImplicitly()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-no-root");
        File expected = new File(app.toFile(), "models");

        assertEquals(
            expected.getAbsoluteFile(),
            LaboratoryAiLocalModelAdmission
                .modelDirectory(app.toFile()).getAbsoluteFile());

        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelAdmission.admit(
                app.toFile(),
                new File(expected, "missing.gguf")));
    }
}
