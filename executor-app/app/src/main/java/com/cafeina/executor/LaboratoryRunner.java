package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.util.Objects;

/**
 * Single entry point for future internal specialists: bounded built-in probe,
 * then mandatory persistent report. The normal UI never calls this method.
 * No candidate code is executed, installed, saved to a project or promoted.
 */
public final class LaboratoryRunner {
    private LaboratoryRunner() {}

    public static LaboratoryEngine.Report runApprovedBuiltIn(File appFilesDirectory,
            String projectId, LaboratoryEngine.Request request,
            LaboratoryEngine.Cancellation cancellation) throws IOException {
        Objects.requireNonNull(request, "request");
        Objects.requireNonNull(cancellation, "cancellation");
        LaboratoryReportStore store = new LaboratoryReportStore(appFilesDirectory, projectId);
        // Refuse a run before executing if the report vault cannot be accessed.
        // An unsuccessful save still fails the call; never report unrecorded success.
        store.ensureWritable();
        LaboratoryEngine.Report result = LaboratoryEngine.run(request, cancellation);
        store.save(result);
        return result;
    }
}
