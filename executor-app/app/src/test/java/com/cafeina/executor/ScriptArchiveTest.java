package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class ScriptArchiveTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();

    private ScriptStore store(String name) throws IOException {
        return new ScriptStore(temp.newFolder(name).toPath().resolve("scripts"));
    }

    private byte[] zipped(String entry, String content) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            zip.putNextEntry(new ZipEntry(entry));
            zip.write(content.getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();
        }
        return bytes.toByteArray();
    }

    @Test
    public void roundTripPreservesScriptsAndDoesNotEnableAutoExecute() throws Exception {
        ScriptStore source = store("from");
        ScriptStore dest = store("to");
        source.save("ola.lua", "print('cafeína')\nreturn 42");
        source.save("outro.lua", "return 2");
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        assertEquals(2, ScriptArchive.exportScripts(source, bytes));
        ScriptArchive.ImportResult result = ScriptArchive.importScripts(dest,
            new ByteArrayInputStream(bytes.toByteArray()));
        assertEquals(2, result.names().size());
        assertEquals(0, result.renamedCount());
        assertEquals(source.load("ola.lua"), dest.load("ola.lua"));
        assertEquals(source.load("outro.lua"), dest.load("outro.lua"));
    }

    @Test
    public void existingScriptsAreNeverOverwritten() throws Exception {
        ScriptStore dest = store("target");
        dest.save("main.lua", "return 'original'");
        byte[] zip = zipped("scripts/main.lua", "return 'imported'");
        ScriptArchive.ImportResult result = ScriptArchive.importScripts(dest,
            new ByteArrayInputStream(zip));
        assertEquals("return 'original'", dest.load("main.lua"));
        assertEquals("return 'imported'", dest.load("main-import1.lua"));
        assertEquals(1, result.renamedCount());
    }

    @Test
    public void rejectsTraversalAndDoesNotWriteAnything() throws Exception {
        ScriptStore dest = store("safe");
        assertThrows(IOException.class, () -> ScriptArchive.importScripts(dest,
            new ByteArrayInputStream(zipped("scripts/../../escape.lua", "return 1"))));
        assertTrue(dest.listScripts().isEmpty());
    }

    @Test
    public void rejectsOversizedScriptAndDoesNotWriteAnything() throws Exception {
        ScriptStore dest = store("max");
        String huge = "x".repeat(ScriptStore.MAX_SCRIPT_BYTES + 1);
        assertThrows(IOException.class, () -> ScriptArchive.importScripts(dest,
            new ByteArrayInputStream(zipped("scripts/huge.lua", huge))));
        assertTrue(dest.listScripts().isEmpty());
    }

    @Test
    public void rejectsNonUtf8Script() throws Exception {
        ScriptStore dest = store("utf8");
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            zip.putNextEntry(new ZipEntry("scripts/bad.lua"));
            zip.write(new byte[]{(byte) 0xC3, (byte) 0x28});
            zip.closeEntry();
        }
        assertThrows(IOException.class, () -> ScriptArchive.importScripts(dest,
            new ByteArrayInputStream(bytes.toByteArray())));
        assertTrue(dest.listScripts().isEmpty());
    }
}
