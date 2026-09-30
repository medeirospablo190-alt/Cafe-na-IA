package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

public final class LaboratoryCandidateSuitePlanTest {
    @Test
    public void planDigestIsStableAndBindsToolCasesInputsAndExpectations() {
        LaboratoryCandidateSuiteRunner.Plan a = new LaboratoryCandidateSuiteRunner.Plan(
            "text-tool", "0.1.0", 77,
            Arrays.asList(
                new LaboratoryCandidateSuiteRunner.Case("upper", "abc", "ABC"),
                new LaboratoryCandidateSuiteRunner.Case("empty", "", "")
            ));
        LaboratoryCandidateSuiteRunner.Plan same = new LaboratoryCandidateSuiteRunner.Plan(
            "text-tool", "0.1.0", 77,
            Arrays.asList(
                new LaboratoryCandidateSuiteRunner.Case("upper", "abc", "ABC"),
                new LaboratoryCandidateSuiteRunner.Case("empty", "", "")
            ));
        assertEquals(2, a.cases.size());
        assertEquals(64, a.planSha256.length());
        assertEquals(a.planSha256, same.planSha256);
        assertNotEquals(a.planSha256, new LaboratoryCandidateSuiteRunner.Plan(
            "text-tool", "0.1.0", 77,
            Collections.singletonList(
                new LaboratoryCandidateSuiteRunner.Case("upper", "abcd", "ABCD")))
            .planSha256);
        assertNotEquals(a.planSha256, new LaboratoryCandidateSuiteRunner.Plan(
            "text-tool", "0.1.1", 77, a.cases).planSha256);
        assertNotEquals(a.planSha256, new LaboratoryCandidateSuiteRunner.Plan(
            "text-tool", "0.1.0", 78, a.cases).planSha256);
    }

    @Test
    public void invalidCaseCountsIdentifiersAndInputsFailBeforeExecution() {
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Plan("../tool", "0.1.0", 0,
                Collections.singletonList(
                    new LaboratoryCandidateSuiteRunner.Case("case", "", ""))));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Plan("text-tool", "01.0.0", 0,
                Collections.singletonList(
                    new LaboratoryCandidateSuiteRunner.Case("case", "", ""))));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Plan("text-tool", "0.1.0", 0,
                Collections.emptyList()));

        java.util.List<LaboratoryCandidateSuiteRunner.Case> many =
            new java.util.ArrayList<>();
        for (int i = 0; i < LaboratoryCandidateSuiteRunner.MAX_CASES + 1; i++) {
            many.add(new LaboratoryCandidateSuiteRunner.Case("c" + i, "", ""));
        }
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Plan("text-tool", "0.1.0", 0, many));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Case("../case", "", ""));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Case("case",
                new String(new char[LaboratorySandboxService.MAX_INPUT_CHARS + 1]), ""));
        assertThrows(IllegalArgumentException.class, () ->
            new LaboratoryCandidateSuiteRunner.Case("case", "",
                new String(new char[257])));
    }
}
