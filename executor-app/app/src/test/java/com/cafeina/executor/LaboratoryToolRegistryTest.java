package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

public final class LaboratoryToolRegistryTest {
    private static String artifactSha(String source) {
        String fingerprint = LaboratoryEngine.fingerprint(source);
        return fingerprint.substring("sha256:".length(), "sha256:".length() + 64);
    }

    @Test
    public void descriptorAcceptsBoundedVersionContract() {
        LaboratoryToolRegistry.Descriptor descriptor =
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "1.2.3-beta.1", artifactSha("tool"),
                "AI_TOOL_WORKSHOP",
                Arrays.asList("geometry", "diagnostics"),
                Arrays.asList("deterministic", "regression"),
                "cafeina-lab-api-1", 2500, 64 * 1024);

        assertEquals("mesh-checker", descriptor.toolId);
        assertEquals("1.2.3-beta.1", descriptor.version);
        assertEquals(2, descriptor.capabilities.size());
        assertEquals(2, descriptor.requiredTests.size());
    }

    @Test
    public void descriptorRejectsUnsafeIdentityAndMalformedVersionOrHash() {
        String sha = artifactSha("tool");
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "../escape", "1.0.0", sha, "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 1000, 1024));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "01.0.0", sha, "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 1000, 1024));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "1.0.0", "not-a-sha", "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 1000, 1024));
    }

    @Test
    public void descriptorRejectsDuplicateContractsAndUnboundedBudgets() {
        String sha = artifactSha("tool");
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "1.0.0", sha, "AI_TOOL_WORKSHOP",
                Arrays.asList("geometry", "geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 1000, 1024));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "1.0.0", sha, "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Arrays.asList("regression", "regression"),
                "api-1", 1000, 1024));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "1.0.0", sha, "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 60_001, 1024));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryToolRegistry.Descriptor(
                "mesh-checker", "1.0.0", sha, "AI_TOOL_WORKSHOP",
                Collections.singletonList("geometry"),
                Collections.singletonList("deterministic"),
                "api-1", 1000, 4 * 1024 * 1024 + 1));
    }
}
