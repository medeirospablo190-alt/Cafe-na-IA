package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.junit.Test;

public final class LaboratoryAiLocalModelCatalogTest {
    @Test
    public void listsOnlyAdmittedGgufModelsInStableOrder()
            throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-catalog");
        Path models = Files.createDirectory(app.resolve("models"));
        Files.write(models.resolve("b.gguf"), fakeGguf((byte) 0x22));
        Files.write(models.resolve("a.gguf"), fakeGguf((byte) 0x11));
        Files.write(models.resolve("ignore.txt"), new byte[] {1, 2, 3});

        List<LaboratoryAiLocalModelCatalog.Model> listed =
            LaboratoryAiLocalModelCatalog.list(app.toFile());

        assertEquals(2, listed.size());
        assertEquals("a.gguf", listed.get(0).fileName);
        assertEquals("b.gguf", listed.get(1).fileName);
    }

    @Test
    public void resolvesOnlyDirectModelFilename() throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-resolve");
        Path models = Files.createDirectory(app.resolve("models"));
        Files.write(models.resolve("model.gguf"), fakeGguf((byte) 0x33));

        LaboratoryAiLocalModelCatalog.Model model =
            LaboratoryAiLocalModelCatalog.resolve(
                app.toFile(), "model.gguf");

        assertEquals("model.gguf", model.fileName);
        assertEquals(
            models.resolve("model.gguf").toRealPath().toFile(),
            model.modelFile);
    }

    @Test
    public void rejectsTraversalSelection() throws Exception {
        Path app = Files.createTempDirectory("cafeina-model-traversal");
        Files.createDirectory(app.resolve("models"));

        assertThrows(
            IOException.class,
            () -> LaboratoryAiLocalModelCatalog.resolve(
                app.toFile(), "../outside.gguf"));
    }

    private static byte[] fakeGguf(byte marker) {
        return new byte[] {
            0x47, 0x47, 0x55, 0x46,
            marker, 0x01, 0x02, 0x03
        };
    }
}
