package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

public final class LaboratoryRegressionEngineTest {
    private static String sha(char value) {
        char[] chars = new char[64];
        Arrays.fill(chars, value);
        return new String(chars);
    }

    private static LaboratoryRegressionEngine.RunEvidence run(
            String id, String status, long seed, long duration,
            String batchSha, String environmentSha, String checkName,
            boolean checkPassed, String expected, String inputSha) {
        return new LaboratoryRegressionEngine.RunEvidence(
            id, "luau-isolated-candidate", "0.1.0", status, seed, duration,
            batchSha, environmentSha,
            Collections.singletonList(new LaboratoryRegressionEngine.CheckEvidence(
                checkName, checkPassed, expected, expected, inputSha)));
    }

    @Test
    public void identicalBehaviorPassesInsidePerformanceBudget() {
        LaboratoryRegressionEngine.RunEvidence baseline =
            run("base", "PASS", 77, 100, sha('a'), sha('e'),
                "regression", true, "ok", sha('1'));
        LaboratoryRegressionEngine.RunEvidence candidate =
            run("candidate", "PASS", 77, 124, sha('b'), sha('e'),
                "regression", true, "ok", sha('2'));

        LaboratoryRegressionEngine.Result result = LaboratoryRegressionEngine.evaluate(
            baseline, candidate, new LaboratoryRegressionEngine.Policy(20, 5, true));

        assertEquals(LaboratoryRegressionEngine.Verdict.PASS, result.verdict);
        assertEquals(125, result.allowedDurationMs);
        assertEquals(24, result.durationDeltaMs);
        assertEquals(Collections.singletonList("regression"), result.coveredTests);
        assertTrue(result.reasons.isEmpty());
        assertEquals(sha('a'), result.baselineBatchSha256);
        assertEquals(sha('b'), result.candidateBatchSha256);
    }

    @Test
    public void durationRegressionFailsWithoutChangingFunctionalVerdictInputs() {
        LaboratoryRegressionEngine.RunEvidence baseline =
            run("base", "PASS", 77, 100, sha('a'), "",
                "deterministic", true, "ok", sha('1'));
        LaboratoryRegressionEngine.RunEvidence candidate =
            run("candidate", "PASS", 77, 126, sha('b'), "",
                "deterministic", true, "ok", sha('2'));

        LaboratoryRegressionEngine.Result result = LaboratoryRegressionEngine.evaluate(
            baseline, candidate, new LaboratoryRegressionEngine.Policy(20, 5, true));

        assertEquals(LaboratoryRegressionEngine.Verdict.FAIL, result.verdict);
        assertTrue(result.reasons.contains("duration regression"));
        assertEquals(Collections.singletonList("deterministic"), result.coveredTests);
    }

    @Test
    public void behavioralOrReproducibilityDifferencesFailComparison() {
        LaboratoryRegressionEngine.RunEvidence baseline =
            run("base", "PASS", 7, 10, sha('a'), sha('e'),
                "caseA", true, "expected", sha('1'));
        LaboratoryRegressionEngine.RunEvidence candidate =
            new LaboratoryRegressionEngine.RunEvidence(
                "candidate", "different-harness", "9.9.9", "FAIL", 8, 10,
                sha('b'), sha('f'),
                Collections.singletonList(new LaboratoryRegressionEngine.CheckEvidence(
                    "caseA", false, "changed", "wrong", sha('2'))));

        LaboratoryRegressionEngine.Result result = LaboratoryRegressionEngine.evaluate(
            baseline, candidate, new LaboratoryRegressionEngine.Policy(100, 100, true));

        assertEquals(LaboratoryRegressionEngine.Verdict.FAIL, result.verdict);
        assertTrue(result.reasons.contains("candidate run is not PASS"));
        assertTrue(result.reasons.contains("test harness identity differs"));
        assertTrue(result.reasons.contains("seed differs"));
        assertTrue(result.reasons.contains("test environment differs"));
        assertTrue(result.reasons.contains("candidate check failed: caseA"));
        assertTrue(result.reasons.contains("expected output changed: caseA"));
    }

    @Test
    public void changedCaseSetAndDuplicatesCannotBeHidden() {
        LaboratoryRegressionEngine.RunEvidence baseline =
            new LaboratoryRegressionEngine.RunEvidence(
                "base", "luau-isolated-candidate", "0.1.0", "PASS",
                1, 10, sha('a'), "", Arrays.asList(
                    new LaboratoryRegressionEngine.CheckEvidence(
                        "caseA", true, "a", "a", sha('1')),
                    new LaboratoryRegressionEngine.CheckEvidence(
                        "caseA", true, "a", "a", sha('1')),
                    new LaboratoryRegressionEngine.CheckEvidence(
                        "caseB", true, "b", "b", sha('1'))));
        LaboratoryRegressionEngine.RunEvidence candidate =
            run("candidate", "PASS", 1, 10, sha('b'), "",
                "caseA", true, "a", sha('2'));

        LaboratoryRegressionEngine.Result result = LaboratoryRegressionEngine.evaluate(
            baseline, candidate, new LaboratoryRegressionEngine.Policy(0, 0, true));

        assertEquals(LaboratoryRegressionEngine.Verdict.FAIL, result.verdict);
        assertTrue(result.reasons.contains("duplicate baseline check: caseA"));
        assertTrue(result.reasons.contains("test case set differs"));
    }

    @Test
    public void differentToolInputCannotBeComparedAsSameCase() {
        LaboratoryRegressionEngine.RunEvidence baseline =
            new LaboratoryRegressionEngine.RunEvidence(
                "base", "luau-isolated-candidate", "0.1.0", "PASS",
                1, 10, sha('a'), "", Collections.singletonList(
                    new LaboratoryRegressionEngine.CheckEvidence(
                        "caseA", true, "ok", "ok", sha('1'), sha('8'))));
        LaboratoryRegressionEngine.RunEvidence candidate =
            new LaboratoryRegressionEngine.RunEvidence(
                "candidate", "luau-isolated-candidate", "0.1.0", "PASS",
                1, 10, sha('b'), "", Collections.singletonList(
                    new LaboratoryRegressionEngine.CheckEvidence(
                        "caseA", true, "ok", "ok", sha('2'), sha('9'))));

        LaboratoryRegressionEngine.Result result = LaboratoryRegressionEngine.evaluate(
            baseline, candidate, new LaboratoryRegressionEngine.Policy(0, 0, true));

        assertEquals(LaboratoryRegressionEngine.Verdict.FAIL, result.verdict);
        assertTrue(result.reasons.contains("tool input differs: caseA"));
        assertTrue(result.coveredTests.isEmpty());
    }

    @Test
    public void policyAndEvidenceBoundsAreValidated() {
        assertThrows(IllegalArgumentException.class,
            () -> new LaboratoryRegressionEngine.Policy(-1, 0, true));
        assertThrows(IllegalArgumentException.class,
            () -> new LaboratoryRegressionEngine.Policy(1001, 0, true));
        assertThrows(IllegalArgumentException.class,
            () -> new LaboratoryRegressionEngine.Policy(0, 60001, true));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryRegressionEngine.CheckEvidence(
                "bad name", true, "x", "x", sha('1')));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryRegressionEngine.RunEvidence(
                "id", "tool", "1", "PASS", 0, -1, sha('a'), "",
                Collections.singletonList(new LaboratoryRegressionEngine.CheckEvidence(
                    "case", true, "x", "x", sha('1')))));
    }
}
