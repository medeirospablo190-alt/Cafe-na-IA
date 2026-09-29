package com.cafeina.executor;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.StandardCharsets;
import java.nio.charset.CodingErrorAction;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/** Portable script-only ZIP archives, using Android Storage Access Framework at the UI edge. */
public final class ScriptArchive {
    private static final int MAX_SCRIPTS = 128;
    private static final long MAX_TOTAL_BYTES = 16L * 1024 * 1024;
    private static final String PREFIX = "scripts/";

    private ScriptArchive() {}

    public static int exportScripts(ScriptStore store, OutputStream target) throws IOException {
        List<String> names = store.listScripts();
        if (names.size() > MAX_SCRIPTS) throw new IOException("too many scripts for one ZIP");
        long total = 0;
        try (ZipOutputStream zip = new ZipOutputStream(target, StandardCharsets.UTF_8)) {
            ZipEntry info = new ZipEntry("LEIA_PRIMEIRO.txt");
            zip.putNextEntry(info);
            zip.write(("CAFEINA script backup. Importar pelo aplicativo CAFEINA. "
                + "Scripts importados nunca ativam o Auto Execute automaticamente.\n")
                .getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();
            for (String name : names) {
                byte[] bytes = store.load(name).getBytes(StandardCharsets.UTF_8);
                total += bytes.length;
                if (total > MAX_TOTAL_BYTES) throw new IOException("script backup too large");
                zip.putNextEntry(new ZipEntry(PREFIX + name));
                zip.write(bytes);
                zip.closeEntry();
            }
            zip.finish();
        }
        return names.size();
    }

    public static ImportResult importScripts(ScriptStore store, InputStream source)
            throws IOException {
        Map<String, String> staged = new LinkedHashMap<>();
        long total = 0;
        int allEntries = 0;
        try (ZipInputStream zip = new ZipInputStream(source, StandardCharsets.UTF_8)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (++allEntries > MAX_SCRIPTS + 2) {
                    throw new IOException("too many entries in ZIP");
                }
                String path = entry.getName();
                if (entry.isDirectory()) {
                    if (!PREFIX.equals(path)) throw new IOException("unexpected ZIP directory");
                    zip.closeEntry();
                    continue;
                }
                if ("LEIA_PRIMEIRO.txt".equals(path)) {
                    drainSmall(zip, 4096);
                    zip.closeEntry();
                    continue;
                }
                if (path == null || !path.startsWith(PREFIX)) {
                    throw new IOException("unexpected ZIP entry");
                }
                String name = path.substring(PREFIX.length());
                if (!ScriptStore.isValidName(name) || staged.containsKey(name)) {
                    throw new IOException("invalid or repeated script name in ZIP");
                }
                if (staged.size() >= MAX_SCRIPTS) throw new IOException("too many scripts in ZIP");
                byte[] bytes = drainSmall(zip, ScriptStore.MAX_SCRIPT_BYTES);
                total += bytes.length;
                if (total > MAX_TOTAL_BYTES) throw new IOException("import is too large");
                staged.put(name, decodeUtf8(bytes));
                zip.closeEntry();
            }
        }
        if (staged.isEmpty()) throw new IOException("ZIP does not contain scripts");

        // Validate and assign every destination before writing any file. Existing files
        // always keep their original contents; Auto Execute metadata is never imported.
        Set<String> occupied = new LinkedHashSet<>(store.listScripts());
        List<String> imported = new ArrayList<>();
        int renamed = 0;
        for (Map.Entry<String, String> item : staged.entrySet()) {
            String wanted = item.getKey();
            String dest = uniqueName(wanted, occupied);
            if (!dest.equals(wanted)) renamed++;
            occupied.add(dest);
            imported.add(dest);
        }
        int index = 0;
        for (String content : staged.values()) {
            store.save(imported.get(index++), content);
        }
        return new ImportResult(imported, renamed);
    }

    private static String uniqueName(String wanted, Set<String> occupied) throws IOException {
        if (!occupied.contains(wanted)) return wanted;
        String stem = wanted.substring(0, wanted.length() - 4);
        for (int i = 1; i <= 9999; i++) {
            String suffix = "-import" + i + ".lua";
            int allowedStem = ScriptStore.MAX_NAME_LENGTH - suffix.length();
            String candidate = stem.substring(0, Math.min(stem.length(), allowedStem)) + suffix;
            if (ScriptStore.isValidName(candidate) && !occupied.contains(candidate)) {
                return candidate;
            }
        }
        throw new IOException("could not assign a safe import filename");
    }

    private static String decodeUtf8(byte[] bytes) throws IOException {
        try {
            return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException invalid) {
            throw new IOException("ZIP contains a script that is not valid UTF-8", invalid);
        }
    }

    private static byte[] drainSmall(InputStream source, int maxBytes) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] chunk = new byte[8192];
        int read;
        int total = 0;
        while ((read = source.read(chunk)) != -1) {
            total += read;
            if (total > maxBytes) throw new IOException("ZIP entry exceeds size limit");
            output.write(chunk, 0, read);
        }
        return output.toByteArray();
    }

    public static final class ImportResult {
        private final List<String> names;
        private final int renamed;
        private ImportResult(List<String> names, int renamed) {
            this.names = Collections.unmodifiableList(new ArrayList<>(names));
            this.renamed = renamed;
        }
        public List<String> names() { return names; }
        public int renamedCount() { return renamed; }
    }
}
