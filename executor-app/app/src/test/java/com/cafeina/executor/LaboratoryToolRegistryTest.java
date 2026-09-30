package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class LaboratoryToolRegistryTest {
    @Rule public final TemporaryFolder temporary = new TemporaryFolder();

    private static LaboratoryToolRegistry.Descriptor descriptor(
            String version, String artifactSha256) {
        return new LaboratoryToolRegistry.Descriptor(
            "mesh-checker", version, artifactSha256, "AI_TOOL_WORKSHOP",
            Arrays.asList("geometry", "diagnostics"),
            Arrays.asList("deterministic", "regression"),
            "cafeina-lab-api-1", 2500, 64 * 1024);
    }

    private static LaboratoryEngine.Report passEvidence(
            File root, String projectId, String source, String testName) throws IOException {
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                testName, source, LaboratoryEngine.fingerprint(source))));
        LaboratoryEngine.Report report =
            LaboratoryEngine.run(request, new LaboratoryEngine.Cancellation());
        new LaboratoryReportStore(root, projectId).save(report);
        return report;
    }

    private static String artifactSha(String source) {
        String fingerprint = LaboratoryEngine.fingerprint(source);
        return fingerprint.substring("sha256:".length(), "sha256:".length() + 64);
    }

    @Test
    public void versionsAreImmutableAndStartExperimental() throws Exception {
        File root = temporary.newFolder("app-files");
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(root, "project1");
        LaboratoryToolRegistry.Descriptor first =
            descriptor("0.1.0", artifactSha("tool-v1"));

        registry.registerExperimental(first);

        assertEquals(LaboratoryToolRegistry.Stage.EXPERIMENTAL,
            registry.stage(first.toolId, first.version));
        assertEquals(first.artifactSha256,
            registry.readDescriptor(first.toolId, first.version).artifactSha256);
        assertThrows(IOException.class, () -> registry.registerExperimental(first));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "../escape", "1.0.0", first.artifactSha256, "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 1000, 1024));
    }

    @Test
    public void candidateRequiresExactArtifactAndEveryMandatoryTest() throws Exception {
        File root = temporary.newFolder("evidence-files");
        String project = "project2";
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(root, project);
        LaboratoryToolRegistry.Descriptor tool =
            descriptor("0.2.0", artifactSha("candidate-source"));
        registry.registerExperimental(tool);

        LaboratoryEngine.Report wrong = passEvidence(
            root, project, "different-source", "deterministic");
        assertThrows(IOException.class, () ->
            registry.qualifyCandidate(tool.toolId, tool.version,
                Collections.singletonList(wrong.runId)));
        assertEquals(LaboratoryToolRegistry.Stage.EXPERIMENTAL,
            registry.stage(tool.toolId, tool.version));

        LaboratoryEngine.Report deterministic = passEvidence(
            root, project, "candidate-source", "deterministic");
        assertThrows(IOException.class, () ->
            registry.qualifyCandidate(tool.toolId, tool.version,
                Collections.singletonList(deterministic.runId)));

        LaboratoryEngine.Report regression = passEvidence(
            root, project, "candidate-source", "regression");
        registry.qualifyCandidate(tool.toolId, tool.version,
            Arrays.asList(deterministic.runId, regression.runId));
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(tool.toolId, tool.version));
    }

    @Test
    public void stablePromotionAndRollbackNeedExplicitApprovalAndKeepHistory()
            throws Exception {
        File root = temporary.newFolder("promotion-files");
        String project = "project3";
        LaboratoryToolRegistry registry = new LaboratoryToolRegistry(root, project);

        LaboratoryToolRegistry.Descriptor v1 =
            descriptor("1.0.0", artifactSha("stable-one"));
        registry.registerExperimental(v1);
        LaboratoryEngine.Report report1a = passEvidence(
            root, project, "stable-one", "deterministic");
        LaboratoryEngine.Report report1b = passEvidence(
            root, project, "stable-one", "regression");
        List<String> evidence1 = Arrays.asList(report1a.runId, report1b.runId);
        registry.qualifyCandidate(v1.toolId, v1.version, evidence1);

        LaboratoryToolRegistry.ApprovalGate deny =
            (action, tool, from, to, approval) -> false;
        assertThrows(SecurityException.class, () ->
            registry.activateStable(v1.toolId, v1.version,
                evidence1, "approval-1", deny));
        assertNull(registry.activeStable(v1.toolId));

        LaboratoryToolRegistry.ApprovalGate approveExact =
            (action, tool, from, to, approval) -> approval.startsWith("approval-");
        registry.activateStable(v1.toolId, v1.version,
            evidence1, "approval-1", approveExact);
        assertEquals("1.0.0", registry.activeStable(v1.toolId).version);
        assertEquals(LaboratoryToolRegistry.Stage.STABLE,
            registry.stage(v1.toolId, v1.version));

        LaboratoryToolRegistry.Descriptor v2 =
            descriptor("1.1.0", artifactSha("stable-two"));
        registry.registerExperimental(v2);
        LaboratoryEngine.Report report2a = passEvidence(
            root, project, "stable-two", "deterministic");
        LaboratoryEngine.Report report2b = passEvidence(
            root, project, "stable-two", "regression");
        List<String> evidence2 = Arrays.asList(report2a.runId, report2b.runId);
        registry.qualifyCandidate(v2.toolId, v2.version, evidence2);
        registry.activateStable(v2.toolId, v2.version,
            evidence2, "approval-2", approveExact);
        assertEquals("1.1.0", registry.activeStable(v2.toolId).version);

        registry.rollbackStable(v2.toolId, "1.0.0", "approval-3", approveExact);
        assertEquals("1.0.0", registry.activeStable(v2.toolId).version);
        assertEquals(LaboratoryToolRegistry.Stage.STABLE,
            registry.stage(v2.toolId, "1.1.0"));

        assertEquals(5, registry.history(v2.toolId).size());
        for (int i = 0; i < registry.history(v2.toolId).size(); i++) {
            assertEquals(i + 1, registry.history(v2.toolId).get(i).sequence);
        }
        LaboratoryToolRegistry.Event last =
            registry.history(v2.toolId).get(registry.history(v2.toolId).size() - 1);
        assertEquals("ROLLBACK_STABLE", last.action);
        assertEquals("1.1.0", last.fromVersion);
        assertEquals("1.0.0", last.toVersion);
        assertEquals(64, last.approvalSha256.length());
        assertTrue(!last.approvalSha256.contains("approval-3"));
        assertNotNull(registry.readDescriptor(v2.toolId, "1.0.0"));
        assertNotNull(registry.readDescriptor(v2.toolId, "1.1.0"));
    }
}
