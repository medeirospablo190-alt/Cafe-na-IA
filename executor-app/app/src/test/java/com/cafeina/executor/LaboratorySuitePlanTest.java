package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

public final class LaboratorySuitePlanTest {
    private static LaboratoryEngine.Request request(String value, int timeoutMs) {
        return new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL, LaboratoryEngine.FINGERPRINT_VERSION,
            2209, timeoutMs,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "fingerprint", value, LaboratoryEngine.fingerprint(value))));
    }

    @Test
    public void samePlanHasStableDigestAndReplayRequiresTwiceTheBudget() {
        LaboratoryEngine.Request first = request("return 42", 1000);
        LaboratorySuiteRunner.Plan batch = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH, Arrays.asList(first, request("return 7", 1000)),
            Collections.emptyList());
        LaboratorySuiteRunner.Plan same = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH, Arrays.asList(first, request("return 7", 1000)),
            Collections.emptyList());
        LaboratorySuiteRunner.Plan replay = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.REPLAY, Arrays.asList(first, request("return 7", 1000)),
            Collections.emptyList());
        assertEquals(2, batch.plannedRuns);
        assertEquals(4, replay.plannedRuns);
        assertEquals(64, batch.planSha256.length());
        assertEquals(batch.planSha256, same.planSha256);
        assertNotEquals(batch.planSha256, replay.planSha256);
        assertNotEquals(batch.planSha256, new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH,
            Arrays.asList(first, request("return 8", 1000)),
            Collections.emptyList()).planSha256);
    }

    @Test
    public void invalidSuiteBudgetsAndRegressionBaselineCountsFailFast() {
        LaboratoryEngine.Request request = request("abc", 10000);
        assertThrows(IllegalArgumentException.class, () -> new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.REPLAY, Arrays.asList(request, request),
            Collections.emptyList()));
        assertThrows(IllegalArgumentException.class, () -> new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH, Collections.emptyList(),
            Collections.emptyList()));
        assertThrows(IllegalArgumentException.class, () -> new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH,
            Arrays.asList(request, request, request, request, request),
            Collections.emptyList()));
        assertThrows(IllegalArgumentException.class, () -> new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.REGRESSION, Collections.singletonList(request),
            Collections.emptyList()));
        assertThrows(IllegalArgumentException.class, () -> new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.REGRESSION, Collections.singletonList(request),
            Collections.singletonList("../../user/scripts.lua")));
        assertEquals(1, new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.REGRESSION, Collections.singletonList(request),
            Collections.singletonList(UUID.randomUUID().toString())).plannedRuns);
    }

    @Test
    public void unknownOrGeneratedToolsCannotRunThroughHostSuite() {
        assertThrows(IllegalArgumentException.class, () -> new LaboratoryEngine.Request(
            "untrusted-generated-tool", "1.0.0", 0, 1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "source", "return 1", "1"))));
    }
}
