package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;

/**
 * Pure deterministic comparison of two already-recorded laboratory runs.
 * It performs no I/O and does not execute candidate code.
 */
public final class LaboratoryRegressionEngine {
    public enum Verdict { PASS, FAIL }

    public static final class Policy {
        public final int maxSlowdownPercent;
        public final long graceMs;
        public final boolean requireSameEnvironment;

        public Policy(int maxSlowdownPercent, long graceMs, boolean requireSameEnvironment) {
            if (maxSlowdownPercent < 0 || maxSlowdownPercent > 1000) {
                throw new IllegalArgumentException("invalid slowdown budget");
            }
            if (graceMs < 0 || graceMs > 60_000) {
                throw new IllegalArgumentException("invalid regression grace");
            }
            this.maxSlowdownPercent = maxSlowdownPercent;
            this.graceMs = graceMs;
            this.requireSameEnvironment = requireSameEnvironment;
        }
    }

    public static final class CheckEvidence {
        public final String name;
        public final boolean passed;
        public final String expectedOutput;
        public final String actualOutput;
        public final String inputSha256;
        public final String toolInputSha256;

        public CheckEvidence(String name, boolean passed, String expectedOutput,
                String actualOutput, String inputSha256) {
            this(name, passed, expectedOutput, actualOutput, inputSha256, "");
        }

        public CheckEvidence(String name, boolean passed, String expectedOutput,
                String actualOutput, String inputSha256, String toolInputSha256) {
            if (name == null || !name.matches("[a-zA-Z0-9_-]{1,64}")) {
                throw new IllegalArgumentException("invalid regression check name");
            }
            if (expectedOutput == null || actualOutput == null) {
                throw new IllegalArgumentException("missing regression output");
            }
            if (inputSha256 == null || !inputSha256.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("invalid regression input hash");
            }
            if (toolInputSha256 == null
                    || (!toolInputSha256.isEmpty()
                        && !toolInputSha256.matches("[0-9a-f]{64}"))) {
                throw new IllegalArgumentException("invalid tool input hash");
            }
            this.name = name;
            this.passed = passed;
            this.expectedOutput = expectedOutput;
            this.actualOutput = actualOutput;
            this.inputSha256 = inputSha256;
            this.toolInputSha256 = toolInputSha256;
        }
    }

    public static final class RunEvidence {
        public final String runId;
        public final String toolId;
        public final String toolVersion;
        public final String status;
        public final long seed;
        public final long durationMs;
        public final String candidateBatchSha256;
        public final String environmentSha256;
        public final List<CheckEvidence> checks;

        public RunEvidence(String runId, String toolId, String toolVersion,
                String status, long seed, long durationMs, String candidateBatchSha256,
                String environmentSha256, List<CheckEvidence> checks) {
            if (runId == null || runId.isEmpty() || toolId == null || toolId.isEmpty()
                    || toolVersion == null || toolVersion.isEmpty()
                    || status == null || status.isEmpty()) {
                throw new IllegalArgumentException("missing regression run identity");
            }
            if (durationMs < 0) throw new IllegalArgumentException("negative run duration");
            if (candidateBatchSha256 == null
                    || !candidateBatchSha256.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("invalid regression batch hash");
            }
            if (environmentSha256 == null
                    || (!environmentSha256.isEmpty()
                        && !environmentSha256.matches("[0-9a-f]{64}"))) {
                throw new IllegalArgumentException("invalid regression environment hash");
            }
            if (checks == null || checks.isEmpty() || checks.size() > 64) {
                throw new IllegalArgumentException("invalid regression check set");
            }
            List<CheckEvidence> copy = new ArrayList<>();
            for (CheckEvidence check : checks) {
                copy.add(Objects.requireNonNull(check, "regression check"));
            }
            this.runId = runId;
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.status = status;
            this.seed = seed;
            this.durationMs = durationMs;
            this.candidateBatchSha256 = candidateBatchSha256;
            this.environmentSha256 = environmentSha256;
            this.checks = Collections.unmodifiableList(copy);
        }
    }

    public static final class Result {
        public final Verdict verdict;
        public final String baselineRunId;
        public final String candidateRunId;
        public final String toolId;
        public final String toolVersion;
        public final long seed;
        public final String environmentSha256;
        public final String baselineBatchSha256;
        public final String candidateBatchSha256;
        public final String baselineInputSha256;
        public final String candidateInputSha256;
        public final long baselineDurationMs;
        public final long candidateDurationMs;
        public final long allowedDurationMs;
        public final long durationDeltaMs;
        public final List<String> coveredTests;
        public final List<String> reasons;

        private Result(Verdict verdict, RunEvidence baseline, RunEvidence candidate,
                long allowedDurationMs, List<String> coveredTests, List<String> reasons) {
            this.verdict = verdict;
            this.baselineRunId = baseline.runId;
            this.candidateRunId = candidate.runId;
            this.toolId = baseline.toolId;
            this.toolVersion = baseline.toolVersion;
            this.seed = baseline.seed;
            this.environmentSha256 = baseline.environmentSha256;
            this.baselineBatchSha256 = baseline.candidateBatchSha256;
            this.candidateBatchSha256 = candidate.candidateBatchSha256;
            this.baselineInputSha256 = uniqueInputSha(baseline.checks);
            this.candidateInputSha256 = uniqueInputSha(candidate.checks);
            this.baselineDurationMs = baseline.durationMs;
            this.candidateDurationMs = candidate.durationMs;
            this.allowedDurationMs = allowedDurationMs;
            this.durationDeltaMs = candidate.durationMs - baseline.durationMs;
            this.coveredTests = Collections.unmodifiableList(new ArrayList<>(coveredTests));
            this.reasons = Collections.unmodifiableList(new ArrayList<>(reasons));
        }
    }

    private LaboratoryRegressionEngine() {}

    public static Result evaluate(RunEvidence baseline, RunEvidence candidate, Policy policy) {
        Objects.requireNonNull(baseline, "baseline");
        Objects.requireNonNull(candidate, "candidate");
        Objects.requireNonNull(policy, "policy");

        List<String> reasons = new ArrayList<>();
        List<String> covered = new ArrayList<>();

        if (!"PASS".equals(baseline.status)) {
            reasons.add("baseline run is not PASS");
        }
        if (!"PASS".equals(candidate.status)) {
            reasons.add("candidate run is not PASS");
        }
        if (!baseline.toolId.equals(candidate.toolId)
                || !baseline.toolVersion.equals(candidate.toolVersion)) {
            reasons.add("test harness identity differs");
        }
        if (baseline.seed != candidate.seed) {
            reasons.add("seed differs");
        }
        if (policy.requireSameEnvironment
                && !baseline.environmentSha256.equals(candidate.environmentSha256)) {
            reasons.add("test environment differs");
        }

        Map<String, CheckEvidence> baselineChecks = indexed(baseline.checks, reasons, "baseline");
        Map<String, CheckEvidence> candidateChecks = indexed(candidate.checks, reasons, "candidate");

        if (!baselineChecks.keySet().equals(candidateChecks.keySet())) {
            reasons.add("test case set differs");
        }

        for (String name : baselineChecks.keySet()) {
            CheckEvidence before = baselineChecks.get(name);
            CheckEvidence after = candidateChecks.get(name);
            if (after == null) continue;
            boolean comparable = true;
            if (!before.passed) {
                reasons.add("baseline check failed: " + name);
                comparable = false;
            }
            if (!after.passed) {
                reasons.add("candidate check failed: " + name);
                comparable = false;
            }
            if (!before.expectedOutput.equals(after.expectedOutput)) {
                reasons.add("expected output changed: " + name);
                comparable = false;
            }
            if (!before.toolInputSha256.equals(after.toolInputSha256)) {
                reasons.add("tool input differs: " + name);
                comparable = false;
            }
            if (comparable) covered.add(name);
        }

        long allowed = allowedDuration(baseline.durationMs, policy);
        if (candidate.durationMs > allowed) {
            reasons.add("duration regression");
        }

        Collections.sort(covered);
        Verdict verdict = reasons.isEmpty() ? Verdict.PASS : Verdict.FAIL;
        return new Result(verdict, baseline, candidate, allowed, covered, reasons);
    }

    private static Map<String, CheckEvidence> indexed(List<CheckEvidence> checks,
            List<String> reasons, String side) {
        Map<String, CheckEvidence> result = new TreeMap<>();
        for (CheckEvidence check : checks) {
            if (result.put(check.name, check) != null) {
                reasons.add("duplicate " + side + " check: " + check.name);
            }
        }
        return result;
    }

    private static String uniqueInputSha(List<CheckEvidence> checks) {
        String value = "";
        for (CheckEvidence check : checks) {
            if (value.isEmpty()) {
                value = check.inputSha256;
            } else if (!value.equals(check.inputSha256)) {
                return "";
            }
        }
        return value;
    }

    private static long allowedDuration(long baselineDurationMs, Policy policy) {
        long slowdown;
        if (baselineDurationMs == 0 || policy.maxSlowdownPercent == 0) {
            slowdown = 0;
        } else {
            long whole = baselineDurationMs / 100L;
            long remainder = baselineDurationMs % 100L;
            long wholePart = whole > Long.MAX_VALUE / policy.maxSlowdownPercent
                ? Long.MAX_VALUE : whole * policy.maxSlowdownPercent;
            long remainderPart =
                (remainder * policy.maxSlowdownPercent + 99L) / 100L;
            slowdown = saturatedAdd(wholePart, remainderPart);
        }
        long allowed = saturatedAdd(baselineDurationMs, slowdown);
        return saturatedAdd(allowed, policy.graceMs);
    }

    private static long saturatedAdd(long left, long right) {
        if (right > 0 && left > Long.MAX_VALUE - right) return Long.MAX_VALUE;
        return left + right;
    }
}
