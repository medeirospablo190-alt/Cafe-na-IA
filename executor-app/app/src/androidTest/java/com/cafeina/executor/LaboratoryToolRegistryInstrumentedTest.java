package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryToolRegistryInstrumentedTest {
    @Test
    public void lifecyclePersistsInPrivateAndroidStorageWithApprovalGate() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "toolreg" + UUID.randomUUID().toString().substring(0, 8);
        String source = "android-tool";
        String fingerprint = LaboratoryEngine.fingerprint(source);
        String artifactSha = fingerprint.substring(
            "sha256:".length(), "sha256:".length() + 64);

        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "artifact", source, fingerprint)));
        LaboratoryEngine.Report report = LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), projectId, request, new LaboratoryEngine.Cancellation());

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), projectId);
        LaboratoryToolRegistry.Descriptor descriptor =
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "0.1.0", artifactSha, "AI_TOOL_WORKSHOP",
                Arrays.asList("geometry", "diagnostics"),
                Collections.singletonList("artifact"),
                "cafeina-lab-api-1", 2500, 64 * 1024);

        registry.registerExperimental(descriptor);
        registry.qualifyCandidate(descriptor.toolId, descriptor.version,
            Collections.singletonList(report.runId));
        assertEquals(LaboratoryToolRegistry.Stage.CANDIDATE,
            registry.stage(descriptor.toolId, descriptor.version));

        LaboratoryToolRegistry.ApprovalGate deny =
            (action, tool, from, to, approval) -> false;
        try {
            registry.activateStable(descriptor.toolId, descriptor.version,
                Collections.singletonList(report.runId), "not-approved", deny);
            throw new AssertionError("stable activation should require approval");
        } catch (SecurityException expected) {
            // Expected: candidate remains inactive.
        }
        assertNull(registry.activeStable(descriptor.toolId));

        LaboratoryToolRegistry.ApprovalGate approved =
            (action, tool, from, to, approval) ->
                "ACTIVATE_STABLE".equals(action)
                    && "user-test-approval".equals(approval);
        registry.activateStable(descriptor.toolId, descriptor.version,
            Collections.singletonList(report.runId), "user-test-approval", approved);

        assertEquals("0.1.0", registry.activeStable(descriptor.toolId).version);
        assertEquals(LaboratoryToolRegistry.Stage.STABLE,
            registry.stage(descriptor.toolId, descriptor.version));
        assertEquals(2, registry.history(descriptor.toolId).size());
        assertEquals(1, registry.history(descriptor.toolId).get(0).sequence);
        assertEquals(2, registry.history(descriptor.toolId).get(1).sequence);
    }
}
