package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Creates the first tiny diagnostic tool needed to exercise the real
 * Goal Lock -> planner -> TestAgent path on a fresh project.
 *
 * This helper intentionally stops at CANDIDATE. It cannot promote itself to
 * STABLE and cannot grant itself to the AI. Those remain separate human gates.
 */
public final class LaboratoryInitialDiagnosticTool {
    public static final String TOOL_ID = "diagnostic-roundtrip";
    public static final String VERSION = "1.0.0";
    public static final String SOURCE = "return tool_input";

    private static final String ORIGIN = "APP_BOOTSTRAP";
    private static final String COMPATIBILITY = "cafeina-lab-api-1";
    private static final int MAX_RUNTIME_MS = 1_000;
    private static final int MAX_INPUT_BYTES = 4_096;
    private static final List<String> CAPABILITIES =
        Collections.unmodifiableList(Arrays.asList(
            LaboratoryStableToolExecutor.REQUIRED_CAPABILITY,
            "diagnostics",
            "text-roundtrip"));
    private static final List<String> REQUIRED_TESTS =
        Collections.singletonList("artifact");

    public enum State {
        MISSING,
        EXPERIMENTAL,
        CANDIDATE,
        STABLE
    }

    private LaboratoryInitialDiagnosticTool() {}

    public static State state(File appFilesDirectory, String projectId)
            throws IOException {
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(appFilesDirectory, projectId);
        LaboratoryToolRegistry.Descriptor descriptor =
            findDescriptor(registry);
        if (descriptor == null) return State.MISSING;
        requireExpectedDescriptor(descriptor);
        return fromStage(registry.stage(TOOL_ID, VERSION));
    }

    /**
     * Prepare and verify the bootstrap tool, stopping at CANDIDATE.
     *
     * This must run off the main thread because it writes snapshots/reports.
     * Calling it again is safe: a verified CANDIDATE or STABLE is returned
     * unchanged instead of duplicating lifecycle records.
     */
    public static State prepareCandidate(
            Context context, String projectId) throws IOException {
        if (context == null) {
            throw new IllegalArgumentException("diagnostic bootstrap context missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "diagnostic bootstrap must run off the UI thread");
        }

        File files = context.getApplicationContext().getFilesDir();
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(files, projectId);
        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(files, projectId);

        LaboratoryToolRegistry.Descriptor existing = findDescriptor(registry);
        if (existing == null) {
            registry.registerExperimental(descriptor());
        } else {
            requireExpectedDescriptor(existing);
        }

        State current = fromStage(registry.stage(TOOL_ID, VERSION));
        if (current == State.STABLE || current == State.CANDIDATE) {
            // A lifecycle transition freezes the executable artifact. Verify it
            // before reporting the bootstrap as usable.
            requireExpectedBinding(artifacts.readVerified(TOOL_ID, VERSION));
            return current;
        }

        if (!artifacts.isBound(TOOL_ID, VERSION)) {
            LaboratorySnapshotStore snapshots =
                new LaboratorySnapshotStore(files, projectId);
            LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
                TOOL_ID,
                SOURCE.getBytes(StandardCharsets.UTF_8));
            artifacts.bindLuauSource(TOOL_ID, VERSION, snapshot.id);
        }
        requireExpectedBinding(artifacts.readVerified(TOOL_ID, VERSION));

        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20261001L,
            1_000,
            Collections.singletonList(
                new LaboratoryEngine.TestCase(
                    "artifact",
                    SOURCE,
                    LaboratoryEngine.fingerprint(SOURCE))));
        LaboratoryEngine.Report evidence =
            LaboratoryRunner.runApprovedBuiltIn(
                files,
                projectId,
                request,
                new LaboratoryEngine.Cancellation());
        if (evidence.status != LaboratoryEngine.Status.PASS) {
            throw new IOException(
                "initial diagnostic evidence did not pass");
        }

        registry.qualifyCandidate(
            TOOL_ID,
            VERSION,
            Collections.singletonList(evidence.runId));

        State prepared = fromStage(registry.stage(TOOL_ID, VERSION));
        if (prepared != State.CANDIDATE) {
            throw new IOException(
                "initial diagnostic tool did not reach CANDIDATE");
        }
        return prepared;
    }

    private static LaboratoryToolRegistry.Descriptor descriptor() {
        return new LaboratoryToolRegistry.Descriptor(
            TOOL_ID,
            VERSION,
            artifactSha256(),
            ORIGIN,
            CAPABILITIES,
            REQUIRED_TESTS,
            COMPATIBILITY,
            MAX_RUNTIME_MS,
            MAX_INPUT_BYTES);
    }

    private static LaboratoryToolRegistry.Descriptor findDescriptor(
            LaboratoryToolRegistry registry) throws IOException {
        for (LaboratoryToolRegistry.Descriptor descriptor :
                registry.listRegisteredVersions()) {
            if (TOOL_ID.equals(descriptor.toolId)
                    && VERSION.equals(descriptor.version)) {
                return descriptor;
            }
        }
        return null;
    }

    private static void requireExpectedDescriptor(
            LaboratoryToolRegistry.Descriptor descriptor)
            throws IOException {
        if (!TOOL_ID.equals(descriptor.toolId)
                || !VERSION.equals(descriptor.version)
                || !artifactSha256().equals(descriptor.artifactSha256)
                || !ORIGIN.equals(descriptor.origin)
                || !CAPABILITIES.equals(descriptor.capabilities)
                || !REQUIRED_TESTS.equals(descriptor.requiredTests)
                || !COMPATIBILITY.equals(descriptor.compatibility)
                || MAX_RUNTIME_MS != descriptor.maxRuntimeMs
                || MAX_INPUT_BYTES != descriptor.maxInputBytes) {
            throw new IOException(
                "initial diagnostic tool identity does not match this app build");
        }
    }

    private static void requireExpectedBinding(
            LaboratoryToolArtifactStore.Binding binding)
            throws IOException {
        if (binding == null
                || !TOOL_ID.equals(binding.toolId)
                || !VERSION.equals(binding.version)
                || !artifactSha256().equals(binding.artifactSha256)
                || !SOURCE.equals(binding.luauSource())) {
            throw new IOException(
                "initial diagnostic executable binding is invalid");
        }
    }

    private static State fromStage(
            LaboratoryToolRegistry.Stage stage) {
        if (stage == LaboratoryToolRegistry.Stage.STABLE) {
            return State.STABLE;
        }
        if (stage == LaboratoryToolRegistry.Stage.CANDIDATE) {
            return State.CANDIDATE;
        }
        return State.EXPERIMENTAL;
    }

    private static String artifactSha256() {
        String fingerprint = LaboratoryEngine.fingerprint(SOURCE);
        return fingerprint.substring(
            "sha256:".length(),
            "sha256:".length() + 64);
    }
}
