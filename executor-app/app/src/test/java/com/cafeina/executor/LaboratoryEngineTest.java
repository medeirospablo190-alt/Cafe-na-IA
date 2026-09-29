package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

public final class LaboratoryEngineTest {
    private static LaboratoryEngine.Request request(LaboratoryEngine.TestCase... cases) {
        return new LaboratoryEngine.Request(LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION, 20260929L, 5000, Arrays.asList(cases));
    }

    @Test
    public void fingerprintIsStableForUtf8InputWithoutExecutingSource() {
        assertEquals(
            "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                + ";bytes:3;lines:1",
            LaboratoryEngine.fingerprint("abc"));
        assertTrue(LaboratoryEngine.fingerprint("olá\n").endsWith(";bytes:5;lines:2"));
    }

    @Test
    public void resultsPreserveEvidenceForSuccessAndFailureWithoutSourceText() {
        LaboratoryEngine.Report result = LaboratoryEngine.run(request(
            new LaboratoryEngine.TestCase("valid",
                "secret test input", LaboratoryEngine.fingerprint("secret test input")),
            new LaboratoryEngine.TestCase("wrong",
                "other secret input", "expected different output")),
            new LaboratoryEngine.Cancellation());

        assertEquals(LaboratoryEngine.Status.FAIL, result.status);
        assertEquals("EXPERIMENTAL", result.stage);
        assertEquals(1, result.passed);
        assertEquals(1, result.failed);
        assertEquals(2, result.checks.size());
        assertTrue(result.checks.get(0).passed);
        assertFalse(result.checks.get(1).passed);
        assertEquals(64, result.candidateBatchSha256.length());
        assertFalse(result.checks.get(1).actualOutput.contains("other secret input"));
        assertNotEquals(result.checks.get(0).inputSha256, result.checks.get(1).inputSha256);
    }

    @Test
    public void cancellationBeforeRunDoesNotExecuteAnyCase() {
        LaboratoryEngine.Cancellation cancel = new LaboratoryEngine.Cancellation();
        cancel.cancel();
        LaboratoryEngine.Report result = LaboratoryEngine.run(request(
            new LaboratoryEngine.TestCase("case", "a", LaboratoryEngine.fingerprint("a"))),
            cancel);
        assertEquals(LaboratoryEngine.Status.CANCELLED, result.status);
        assertTrue(result.checks.isEmpty());
    }

    @Test
    public void unknownToolsCannotRunInHostProcess() {
        try {
            new LaboratoryEngine.Request("generated-luau-executor", "1.0.0",
                0, 2000, Collections.singletonList(
                    new LaboratoryEngine.TestCase("case", "print(1)", "1")));
            fail("Unknown tool should have been rejected");
        } catch (IllegalArgumentException expected) {
            assertTrue(expected.getMessage().contains("allowlisted"));
        }
    }

    @Test
    public void oversizedCodeAndBudgetsAreRejected() {
        try {
            new LaboratoryEngine.TestCase("huge", new String(new char[16 * 1024 + 1]), "ok");
            fail("huge source was accepted");
        } catch (IllegalArgumentException expected) {
            assertTrue(expected.getMessage().contains("limit"));
        }
        try {
            new LaboratoryEngine.Request(LaboratoryEngine.FINGERPRINT_TOOL,
                LaboratoryEngine.FINGERPRINT_VERSION, 0, 10001,
                Collections.singletonList(
                    new LaboratoryEngine.TestCase("case", "abc", "expected")));
            fail("unbounded runtime was accepted");
        } catch (IllegalArgumentException expected) {
            assertTrue(expected.getMessage().contains("timeout"));
        }
    }
}
