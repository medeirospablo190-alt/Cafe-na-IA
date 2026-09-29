package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.nio.file.Path;

/** Selects isolated storage for the active Android project; never migrates legacy data. */
public final class ProjectWorkspace {
    private final String id;
    private final ScriptStore scripts;
    private final AutoExecuteStore autoExecute;
    private final String runtimeFilesRoot;

    private ProjectWorkspace(String id, Path scriptsDirectory, Path autoExecuteMetadata,
            Path runtimeDirectory) {
        this.id = id;
        this.scripts = new ScriptStore(scriptsDirectory);
        this.autoExecute = new AutoExecuteStore(autoExecuteMetadata);
        this.runtimeFilesRoot = runtimeDirectory.toAbsolutePath().normalize().toString();
    }

    public static ProjectWorkspace openLegacy(File appFilesDirectory) {
        Path root = appFilesDirectory.toPath().toAbsolutePath().normalize();
        return new ProjectWorkspace("", root.resolve("scripts"),
            root.resolve("autoexec.list"), root.resolve("runtime-fs"));
    }

    public static ProjectWorkspace open(File appFilesDirectory, String projectId)
            throws IOException {
        if (projectId == null || projectId.isEmpty()) {
            return openLegacy(appFilesDirectory);
        }
        ProjectStore.Project project = new ProjectStore(appFilesDirectory).open(projectId);
        return new ProjectWorkspace(project.id(), project.scriptsDirectory(),
            project.root().resolve("autoexec.list"), project.runtimeFilesDirectory());
    }

    public String id() {
        return id;
    }

    public String label() {
        return id.isEmpty() ? "Scripts antigos" : id;
    }

    public ScriptStore scriptStore() {
        return scripts;
    }

    public AutoExecuteStore autoExecuteStore() {
        return autoExecute;
    }

    public String runtimeFilesRoot() {
        return runtimeFilesRoot;
    }
}
