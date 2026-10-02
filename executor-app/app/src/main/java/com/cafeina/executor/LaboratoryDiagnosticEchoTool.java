package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Host-owned bootstrap tool used to validate the complete laboratory lifecycle.
 *
 * The executable is intentionally trivial and isolated: it returns tool_input.
 * It has no filesystem/network capability. Passing its deterministic suite may
 * qualify it as CANDIDATE only; STABLE activation still requires explicit
 * human approval and AI exposure still requires a separate permission grant.
 */
public final class LaboratoryDiagnosticEchoTool {
    public static final String TOOL_ID = "diagnostic-echo";
    public static final String VERSION = "1.0.0";
    public static final String ORIGIN = "CAFEINA_BOOTSTRAP";
    public static final String COMPATIBILITY = "cafeina-lab-api-1";
    public static final int MAX_RUNTIME_MS = 1_500;
    public static final int MAX_INPUT_BYTES = 4 * 1024;

    private static final String SOURCE = "return tool_input";
    private static final List<String> CAPABILITIES =
        Collections.unmodifiableList(Arrays.asList(
            LaboratoryStableToolExecutor.REQUIRED_CAPABILITY,
            "diagnostics",
            "echo"));
    private static final List<String> REQUIRED_TESTS =
        Collections.unmodifiableList(Arrays.asList(
            "echo_empty",
            "echo_text",
            "echo_repeat"));

    public static final class State {
        public final boolean registered;
        public final boolean artifactBound;
        public final LaboratoryToolRegistry.Stage stage;

        private State(
                boolean registered,
                boolean artifactBound,
                LaboratoryToolRegistry.Stage stage) {
            this.registered = registered;
            this.artifactBound = artifactBound;
            this.stage = stage;
        }
    }

    private LaboratoryDiagnosticEchoTool() {}

    public static State inspect(
            File filesDir,
            String projectId) throws IOException {
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(filesDir, projectId);

        LaboratoryToolRegistry.Descriptor found = null;
        for (LaboratoryToolRegistry.Descriptor descriptor :
                registry.listRegisteredVersions()) {
            if (TOOL_ID.equals(descriptor.toolId)
                    && VERSION.equals(descriptor.version)) {
                found = descriptor;
                break;
            }
        }

        if (found == null) {
            return new State(false, false, null);
        }

        validateDescriptor(found);
        LaboratoryToolRegistry.Stage stage =
            registry.stage(TOOL_ID, VERSION);

        boolean bound;
        try {
            bound = new LaboratoryToolArtifactStore(
                filesDir, projectId)
                .isBound(TOOL_ID, VERSION);
        } catch (IOException error) {
            if (stage != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
                throw error;
            }
            bound = false;
        }

        return new State(true, bound, stage);
    }

    public static State prepareExperimental(
            File filesDir,
            String projectId) throws IOException {
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(filesDir, projectId);
        State before = inspect(filesDir, projectId);

        if (!before.registered) {
            registry.registerExperimental(expectedDescriptor());
        } else if (before.stage
                != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
            // Already progressed. Never rewrite a candidate/stable artifact.
            return before;
        }

        LaboratoryToolArtifactStore artifacts =
            new LaboratoryToolArtifactStore(filesDir, projectId);
        if (!artifacts.isBound(TOOL_ID, VERSION)) {
            LaboratorySnapshotStore.Snapshot snapshot =
                new LaboratorySnapshotStore(filesDir, projectId)
                    .create(
                        TOOL_ID,
                        SOURCE.getBytes(StandardCharsets.UTF_8));
            artifacts.bindLuauSource(
                TOOL_ID,
                VERSION,
                snapshot.id);
        }

        return inspect(filesDir, projectId);
    }

    public static List<LaboratoryCandidateTestSuiteRunner.TestCase>
            suiteCases() {
        return Collections.unmodifiableList(Arrays.asList(
            new LaboratoryCandidateTestSuiteRunner.TestCase(
                "echo_empty",
                "",
                "",
                2026100201L,
                1_000),
            new LaboratoryCandidateTestSuiteRunner.TestCase(
                "echo_text",
                "cafeina-diagnostic",
                "cafeina-diagnostic",
                2026100202L,
                1_000),
            new LaboratoryCandidateTestSuiteRunner.TestCase(
                "echo_repeat",
                "12345-ABCDE",
                "12345-ABCDE",
                2026100203L,
                1_000)));
    }

    public static State qualifyCandidate(
            File filesDir,
            String projectId,
            LaboratoryCandidateTestSuiteRunner.Result suite)
            throws IOException {
        if (suite == null
                || !TOOL_ID.equals(suite.toolId)
                || !VERSION.equals(suite.version)
                || !suite.qualifiesRequiredEvidence()) {
            throw new IOException(
                "diagnostic echo suite does not qualify candidate evidence");
        }

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(filesDir, projectId);
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(TOOL_ID, VERSION);
        validateDescriptor(descriptor);

        if (registry.stage(TOOL_ID, VERSION)
                != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
            throw new IOException(
                "diagnostic echo is no longer EXPERIMENTAL");
        }

        registry.qualifyCandidate(
            TOOL_ID,
            VERSION,
            suite.runIds);
        return inspect(filesDir, projectId);
    }

    public static State qualifyCandidate(
            File filesDir,
            String projectId,
            LaboratoryCandidateEvidenceRecovery.Result recovered)
            throws IOException {
        if (recovered == null
                || !recovered.ready
                || !TOOL_ID.equals(recovered.toolId)
                || !VERSION.equals(recovered.version)
                || !sourceSha256().equals(recovered.artifactSha256)
                || recovered.runIds.isEmpty()) {
            throw new IOException(
                "recovered diagnostic echo evidence is not eligible");
        }

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(filesDir, projectId);
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(TOOL_ID, VERSION);
        validateDescriptor(descriptor);
        if (registry.stage(TOOL_ID, VERSION)
                != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
            throw new IOException(
                "diagnostic echo is no longer EXPERIMENTAL");
        }

        LaboratoryToolArtifactStore.Binding binding =
            new LaboratoryToolArtifactStore(
                filesDir, projectId)
                .readVerified(TOOL_ID, VERSION);
        if (!binding.snapshotId.equals(recovered.snapshotId)
                || !binding.artifactSha256.equals(
                    recovered.artifactSha256)) {
            throw new IOException(
                "recovered evidence no longer matches bound artifact");
        }

        registry.qualifyCandidate(
            TOOL_ID,
            VERSION,
            recovered.runIds);
        return inspect(filesDir, projectId);
    }

    public static String sourceSha256() {
        return LaboratoryEngine.fingerprint(SOURCE).substring(7, 71);
    }

    private static LaboratoryToolRegistry.Descriptor
            expectedDescriptor() {
        return new LaboratoryToolRegistry.Descriptor(
            TOOL_ID,
            VERSION,
            sourceSha256(),
            ORIGIN,
            CAPABILITIES,
            REQUIRED_TESTS,
            COMPATIBILITY,
            MAX_RUNTIME_MS,
            MAX_INPUT_BYTES);
    }

    private static void validateDescriptor(
            LaboratoryToolRegistry.Descriptor descriptor)
            throws IOException {
        if (descriptor == null
                || !TOOL_ID.equals(descriptor.toolId)
                || !VERSION.equals(descriptor.version)
                || !sourceSha256().equals(descriptor.artifactSha256)
                || !ORIGIN.equals(descriptor.origin)
                || !COMPATIBILITY.equals(descriptor.compatibility)
                || descriptor.maxRuntimeMs != MAX_RUNTIME_MS
                || descriptor.maxInputBytes != MAX_INPUT_BYTES
                || !descriptor.capabilities.equals(CAPABILITIES)
                || !descriptor.requiredTests.equals(REQUIRED_TESTS)) {
            throw new IOException(
                "diagnostic echo descriptor does not match bootstrap template");
        }
    }
}
