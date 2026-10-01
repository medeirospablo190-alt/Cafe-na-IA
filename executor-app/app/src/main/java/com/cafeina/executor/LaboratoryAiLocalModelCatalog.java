package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Read-only catalog for imported app-private local models.
 *
 * This class never imports, deletes, downloads, loads, or executes a model.
 * Every returned entry passes the same admission gate used by the native
 * runtime before it may be selected.
 */
public final class LaboratoryAiLocalModelCatalog {
    public static final class Model {
        public final File modelFile;
        public final String fileName;
        public final long sizeBytes;

        private Model(
                File modelFile,
                String fileName,
                long sizeBytes) {
            this.modelFile = modelFile;
            this.fileName = fileName;
            this.sizeBytes = sizeBytes;
        }
    }

    private LaboratoryAiLocalModelCatalog() {}

    public static List<Model> list(File appFilesDirectory)
            throws IOException {
        if (appFilesDirectory == null) {
            throw new IllegalArgumentException(
                "app files directory missing for local model catalog");
        }

        File directory =
            LaboratoryAiLocalModelAdmission.modelDirectory(
                appFilesDirectory);
        if (!directory.exists()) {
            return Collections.emptyList();
        }
        if (!Files.isDirectory(
                directory.toPath(), LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(directory.toPath())) {
            throw new IOException(
                "local model catalog path is missing or unsafe");
        }

        File[] candidates = directory.listFiles(
            (parent, name) ->
                name != null
                    && name.toLowerCase(java.util.Locale.ROOT)
                        .endsWith(".gguf"));
        if (candidates == null) {
            throw new IOException(
                "local model catalog could not be listed");
        }

        List<Model> result = new ArrayList<>();
        for (File candidate : candidates) {
            LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
                LaboratoryAiLocalModelAdmission.admit(
                    appFilesDirectory, candidate);
            result.add(new Model(
                candidate.getCanonicalFile(),
                admitted.fileName,
                admitted.sizeBytes));
        }

        result.sort(Comparator.comparing(model -> model.fileName));
        return Collections.unmodifiableList(result);
    }

    public static Model resolve(
            File appFilesDirectory,
            String fileName) throws IOException {
        if (appFilesDirectory == null
                || fileName == null
                || fileName.isEmpty()) {
            throw new IllegalArgumentException(
                "local model catalog selection missing");
        }
        if (fileName.indexOf('/') >= 0
                || fileName.indexOf('\\') >= 0
                || fileName.equals(".")
                || fileName.equals("..")) {
            throw new IOException(
                "local model selection filename is unsafe");
        }

        File candidate = new File(
            LaboratoryAiLocalModelAdmission.modelDirectory(
                appFilesDirectory),
            fileName);
        LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
            LaboratoryAiLocalModelAdmission.admit(
                appFilesDirectory, candidate);
        return new Model(
            candidate.getCanonicalFile(),
            admitted.fileName,
            admitted.sizeBytes);
    }
}
