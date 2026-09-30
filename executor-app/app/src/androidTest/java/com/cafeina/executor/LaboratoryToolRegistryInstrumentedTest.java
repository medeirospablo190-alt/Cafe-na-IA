package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryToolRegistryInstrumentedTest {
    private static String projectId(String prefix) {
        return prefix + UUID.randomUUID().toString().substring(0, 8);
    }

    private static String artifactSha(String source) {
        String fingerprint = LaboratoryEngine.fingerprint(source);
        return fingerprint.substring("sha256:".length(), "sha256:".length() + 64);
    }

    private static LaboratoryEngine.Report passEvidence(Context app, String projectId,
            String source, String testName) throws Exception {
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                testName, source, LaboratoryEngine.fingerprint(source))));
        return LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), projectId, request, new LaboratoryEngine.Cancellation());
    }

    private static LaboratoryToolRegistry.Descriptor descriptor(String version,
            String source, List<String> requiredTests) {
        return new LaboratoryToolRegistry.Descriptor(
            "mesh-checker", version, artifactSha(source), "AI_TOOL_WORKSHOP",
            Arrays.asList("geometry", "diagnostics"),
            requiredTests,
            "cafeina-lab-api-1", 2500, 64 * 1024);
    }

    @Test
    public void lifecyclePersistsInPrivateAndroidStorageWithApprovalGate() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId("toolreg");
        String source = "android-tool";
        LaboratoryEngine.Report report = passEvidence(app, project, source, "artifact");

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratoryToolRegistry.Descriptor tool =
            descriptor("0.1.0", source, Collections.singletonList("artifact"));

        registry.registerExperimental(tool);
        registry.qualifyCandidate(tool.toolId, tool.version,
            Collections.singletonList(report.runId));
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(tool.toolId, tool.version));

        LaboratoryToolRegistry.ApprovalGate deny =
            (action, toolId, from, to, approval) -> false;
        try {
            registry.activateStable(tool.toolId, tool.version,
                Collections.singletonList(report.runId), "not-approved", deny);
            throw new AssertionError("stable activation should require approval");
        } catch (SecurityException expected) {
            // Candidate remains inactive.
        }
        assertNull(registry.activeStable(tool.toolId));

        LaboratoryToolRegistry.ApprovalGate approved =
            (action, toolId, from, to, approval) ->
                "ACTIVATE_STABLE".equals(action)
                    && "user-test-approval".equals(approval);
        registry.activateStable(tool.toolId, tool.version,
            Collections.singletonList(report.runId), "user-test-approval", approved);

        assertEquals("0.1.0", registry.activeStable(tool.toolId).version);
        assertEquals(LaboratoryToolRegistry.Stage.STABLE,
            registry.stage(tool.toolId, tool.version));
        assertEquals(2, registry.history(tool.toolId).size());
        assertEquals(1, registry.history(tool.toolId).get(0).sequence);
        assertEquals(2, registry.history(tool.toolId).get(1).sequence);
    }

    @Test
    public void candidateNeedsExactArtifactAndAllMandatoryTests() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId("evidence");
        String source = "candidate-source";
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratoryToolRegistry.Descriptor tool = descriptor(
            "0.2.0", source, Arrays.asList("deterministic", "regression"));

        registry.registerExperimental(tool);
        try {
            registry.registerExperimental(tool);
            throw new AssertionError("tool versions must be immutable");
        } catch (IOException expected) {
            // Existing version is preserved.
        }

        LaboratoryEngine.Report wrong =
            passEvidence(app, project, "different-source", "deterministic");
        try {
            registry.qualifyCandidate(tool.toolId, tool.version,
                Collections.singletonList(wrong.runId));
            throw new AssertionError("evidence for a different artifact must fail");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("artifact"));
        }

        LaboratoryEngine.Report deterministic =
            passEvidence(app, project, source, "deterministic");
        try {
            registry.qualifyCandidate(tool.toolId, tool.version,
                Collections.singletonList(deterministic.runId));
            throw new AssertionError("missing mandatory regression test must fail");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("required tool tests"));
        }

        LaboratoryEngine.Report regression =
            passEvidence(app, project, source, "regression");
        registry.qualifyCandidate(tool.toolId, tool.version,
            Arrays.asList(deterministic.runId, regression.runId));
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(tool.toolId, tool.version));
    }

    @Test
    public void rollbackSelectsPreviouslyStableVersionWithoutDeletingHistory()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = projectId("rollback");
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratoryToolRegistry.ApprovalGate approve =
            (action, toolId, from, to, approval) -> approval.startsWith("user-");

        LaboratoryToolRegistry.Descriptor v1 =
            descriptor("1.0.0", "stable-one", Collections.singletonList("artifact"));
        LaboratoryEngine.Report e1 = passEvidence(app, project, "stable-one", "artifact");
        registry.registerExperimental(v1);
        registry.qualifyCandidate(v1.toolId, v1.version, Collections.singletonList(e1.runId));
        registry.activateStable(v1.toolId, v1.version,
            Collections.singletonList(e1.runId), "user-v1", approve);

        LaboratoryToolRegistry.Descriptor v2 =
            descriptor("1.1.0", "stable-one", Collections.singletonList("artifact"));
        LaboratoryEngine.Report e2 = passEvidence(app, project, "stable-one", "artifact");
        registry.registerExperimental(v2);
        registry.qualifyCandidate(v2.toolId, v2.version, Collections.singletonList(e2.runId));

        try {
            registry.activateStable(v2.toolId, v2.version,
                Collections.singletonList(e2.runId), "user-v2", approve);
            throw new AssertionError("stable upgrade must require regression evidence");
        } catch (IOException expected) {
            assertTrue(expected.getMessage().contains("regression evidence"));
        }

        LaboratoryRegressionStore regressionStore =
            new LaboratoryRegressionStore(app.getFilesDir(), project);
        LaboratoryRegressionStore.Record comparison = regressionStore.compareAndSave(
            e1.runId, e2.runId,
            new LaboratoryRegressionEngine.Policy(1000, 60_000, true));
        assertEquals("PASS", comparison.verdict);
        assertEquals(v1.artifactSha256, comparison.baselineInputSha256);
        assertEquals(v2.artifactSha256, comparison.candidateInputSha256);

        registry.activateStable(v2.toolId, v2.version,
            Collections.singletonList(e2.runId),
            Collections.singletonList(comparison.comparisonId),
            "user-v2", approve);

        registry.rollbackStable(v2.toolId, "1.0.0", "user-rollback", approve);

        assertEquals("1.0.0", registry.activeStable(v2.toolId).version);
        assertEquals(LaboratoryToolRegistry.Stage.STABLE,
            registry.stage(v2.toolId, "1.1.0"));
        assertNotNull(registry.readDescriptor(v2.toolId, "1.0.0"));
        assertNotNull(registry.readDescriptor(v2.toolId, "1.1.0"));
        assertEquals(5, registry.history(v2.toolId).size());
        for (int i = 0; i < registry.history(v2.toolId).size(); i++) {
            assertEquals(i + 1, registry.history(v2.toolId).get(i).sequence);
        }
        LaboratoryToolRegistry.Event promotion =
            registry.history(v2.toolId).get(3);
        assertEquals("ACTIVATE_STABLE", promotion.action);
        assertEquals(Collections.singletonList(comparison.comparisonId),
            promotion.regressionComparisonIds);

        LaboratoryToolRegistry.Event last =
            registry.history(v2.toolId).get(registry.history(v2.toolId).size() - 1);
        assertEquals("ROLLBACK_STABLE", last.action);
        assertEquals("1.1.0", last.fromVersion);
        assertEquals("1.0.0", last.toVersion);
        assertEquals(64, last.approvalSha256.length());
    }
}
