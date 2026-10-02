package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.lang.reflect.Constructor;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiPermissionSuggestionInstrumentedTest {
    @Test
    public void suggestsMatchingStableToolOnly() throws Exception {
        LaboratoryAiToolController.Tool script = tool(
            "script-inspector",
            Arrays.asList("script", "luau", "validate"));
        LaboratoryAiToolController.Tool mesh = tool(
            "mesh-inspector",
            Arrays.asList("mesh", "geometry", "3d"));

        LaboratoryAiPermissionSuggestion.Result result =
            LaboratoryAiPermissionSuggestion.suggest(
                "Validar este script Luau antes de continuar",
                Arrays.asList(script, mesh));

        assertTrue(result.confident);
        assertEquals(
            Collections.singletonList("script-inspector"),
            result.suggestedToolIds);
    }

    @Test
    public void ambiguousRequestDoesNotPreselectAnything()
            throws Exception {
        LaboratoryAiToolController.Tool script = tool(
            "script-inspector",
            Arrays.asList("script", "luau", "validate"));
        LaboratoryAiToolController.Tool mesh = tool(
            "mesh-inspector",
            Arrays.asList("mesh", "geometry", "3d"));

        LaboratoryAiPermissionSuggestion.Result result =
            LaboratoryAiPermissionSuggestion.suggest(
                "Faça isso no projeto",
                Arrays.asList(script, mesh));

        assertFalse(result.confident);
        assertTrue(result.suggestedToolIds.isEmpty());
    }

    @Test
    public void suggestionNeverAddsUnavailableTool() throws Exception {
        LaboratoryAiToolController.Tool mesh = tool(
            "mesh-inspector",
            Arrays.asList("mesh", "geometry", "repair"));

        LaboratoryAiPermissionSuggestion.Result result =
            LaboratoryAiPermissionSuggestion.suggest(
                "Validar script Luau",
                Collections.singletonList(mesh));

        assertFalse(result.confident);
        assertTrue(result.suggestedToolIds.isEmpty());
    }

    private static LaboratoryAiToolController.Tool tool(
            String toolId,
            List<String> capabilities) throws Exception {
        LaboratoryToolRegistry.Descriptor descriptor =
            new LaboratoryToolRegistry.Descriptor(
                toolId,
                "1.0.0",
                repeat("a", 64),
                "TEST",
                capabilities,
                Collections.singletonList("smoke"),
                "android",
                1000,
                1024);

        Constructor<LaboratoryAiToolController.Tool> constructor =
            LaboratoryAiToolController.Tool.class.getDeclaredConstructor(
                LaboratoryToolRegistry.Descriptor.class);
        constructor.setAccessible(true);
        return constructor.newInstance(descriptor);
    }

    private static String repeat(String value, int count) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < count; i++) out.append(value);
        return out.toString();
    }
}
