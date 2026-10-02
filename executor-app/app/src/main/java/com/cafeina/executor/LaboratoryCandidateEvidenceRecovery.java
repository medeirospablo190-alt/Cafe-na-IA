package com.cafeina.executor;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Read-only recovery of a previously completed candidate suite.
 *
 * No aggregate log is written. Exact suite evidence is reconstructed from
 * existing per-case reports and accepted only when artifact, bound snapshot,
 * sandbox environment, seed, case name, input hash and expected-return hash all
 * still match the current suite definition.
 */
public final class LaboratoryCandidateEvidenceRecovery {
    public static final class Result {
        public final boolean ready;
        public final String toolId;
        public final String version;
        public final String artifactSha256;
        public final String snapshotId;
        public final String environmentSha256;
        public final List<String> runIds;
        public final List<String> matchedCaseNames;
        public final List<String> missingCaseNames;

        private Result(
                String toolId,
                String version,
                String artifactSha256,
                String snapshotId,
                String environmentSha256,
                List<String> runIds,
                List<String> matchedCaseNames,
                List<String> missingCaseNames) {
            this.ready = missingCaseNames.isEmpty()
                && !runIds.isEmpty();
            this.toolId = toolId;
            this.version = version;
            this.artifactSha256 = artifactSha256;
            this.snapshotId = snapshotId;
            this.environmentSha256 = environmentSha256;
            this.runIds = Collections.unmodifiableList(
                new ArrayList<>(runIds));
            this.matchedCaseNames = Collections.unmodifiableList(
                new ArrayList<>(matchedCaseNames));
            this.missingCaseNames = Collections.unmodifiableList(
                new ArrayList<>(missingCaseNames));
        }
    }

    private LaboratoryCandidateEvidenceRecovery() {}

    public static Result inspect(
            Context context,
            String projectId,
            String toolId,
            String version,
            List<LaboratoryCandidateTestSuiteRunner.TestCase> cases)
            throws IOException {
        if (context == null
                || projectId == null
                || toolId == null
                || version == null) {
            throw new IllegalArgumentException(
                "candidate evidence recovery input missing");
        }

        List<LaboratoryCandidateTestSuiteRunner.TestCase> requested =
            validateCases(cases);

        Context app = context.getApplicationContext();
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(
                app.getFilesDir(), projectId);
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(toolId, version);
        if (registry.stage(toolId, version)
                != LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
            throw new IOException(
                "candidate evidence recovery requires EXPERIMENTAL version");
        }

        Set<String> requestedNames = new HashSet<>();
        for (LaboratoryCandidateTestSuiteRunner.TestCase testCase :
                requested) {
            requestedNames.add(testCase.name);
        }
        if (!requestedNames.equals(
                new HashSet<>(descriptor.requiredTests))) {
            throw new IOException(
                "recovery suite must match descriptor requiredTests exactly");
        }

        LaboratoryToolArtifactStore.Binding binding =
            new LaboratoryToolArtifactStore(
                app.getFilesDir(), projectId)
                .readVerified(toolId, version);
        if (!descriptor.artifactSha256.equals(
                binding.artifactSha256)) {
            throw new IOException(
                "candidate recovery artifact does not match descriptor");
        }

        String environmentSha256 =
            LaboratorySandboxEnvironment.fingerprint(app);

        Map<String, String> runByCase =
            new LinkedHashMap<>();
        List<LaboratoryReportStore.Entry> reports =
            new LaboratoryReportStore(
                app.getFilesDir(), projectId)
                .list();

        // LaboratoryReportStore.list() is newest first. Keep the first exact
        // match for each case so recovery prefers the newest valid evidence.
        for (LaboratoryReportStore.Entry entry : reports) {
            if (runByCase.size() >= requested.size()) break;
            if (!"PASS".equals(entry.status)) continue;

            try {
                JSONObject report =
                    new JSONObject(entry.reportText);
                Match match = matchReport(
                    report,
                    descriptor,
                    binding,
                    environmentSha256,
                    requested);
                if (match == null
                        || runByCase.containsKey(match.caseName)) {
                    continue;
                }
                runByCase.put(match.caseName, entry.runId);
            } catch (Exception ignored) {
                // Recovery is optional/read-only. A malformed or unrelated
                // old report cannot become qualifying evidence.
            }
        }

        List<String> runIds = new ArrayList<>();
        List<String> matched = new ArrayList<>();
        List<String> missing = new ArrayList<>();
        for (LaboratoryCandidateTestSuiteRunner.TestCase testCase :
                requested) {
            String runId = runByCase.get(testCase.name);
            if (runId == null) {
                missing.add(testCase.name);
            } else {
                matched.add(testCase.name);
                runIds.add(runId);
            }
        }

        return new Result(
            descriptor.toolId,
            descriptor.version,
            descriptor.artifactSha256,
            binding.snapshotId,
            environmentSha256,
            runIds,
            matched,
            missing);
    }

    private static Match matchReport(
            JSONObject report,
            LaboratoryToolRegistry.Descriptor descriptor,
            LaboratoryToolArtifactStore.Binding binding,
            String environmentSha256,
            List<LaboratoryCandidateTestSuiteRunner.TestCase> cases)
            throws Exception {
        if (report.optInt("schemaVersion", 0) != 2
                || !"PASS".equals(report.optString("status"))
                || !"EXECUTED".equals(
                    report.optString("workerStatus"))
                || !report.optBoolean("snapshotVerified", false)
                || !descriptor.artifactSha256.equals(
                    report.optString("candidateBatchSha256"))
                || !binding.snapshotId.equals(
                    report.optString("candidateSnapshotId"))
                || !environmentSha256.equals(
                    report.optString("environmentSha256"))) {
            return null;
        }

        JSONArray checks = report.optJSONArray("checks");
        if (checks == null || checks.length() != 1) {
            return null;
        }
        JSONObject check = checks.getJSONObject(0);
        if (!check.optBoolean("passed", false)
                || !descriptor.artifactSha256.equals(
                    check.optString("inputSha256"))) {
            return null;
        }

        String caseName = check.optString("name");
        LaboratoryCandidateTestSuiteRunner.TestCase expected =
            findCase(cases, caseName);
        if (expected == null) return null;

        String inputSha =
            LaboratoryEngine.fingerprint(expected.toolInput)
                .substring(7, 71);
        String expectedSha =
            LaboratoryEngine.fingerprint(
                expected.expectedFirstReturn)
                .substring(7, 71);

        if (report.optLong("seed", Long.MIN_VALUE)
                    != expected.seed
                || !inputSha.equals(
                    report.optString("toolInputSha256"))
                || !inputSha.equals(
                    check.optString("toolInputSha256"))
                || !expectedSha.equals(
                    check.optString("expectedOutput"))) {
            return null;
        }

        return new Match(caseName);
    }

    private static LaboratoryCandidateTestSuiteRunner.TestCase
            findCase(
                List<LaboratoryCandidateTestSuiteRunner.TestCase> cases,
                String name) {
        for (LaboratoryCandidateTestSuiteRunner.TestCase testCase :
                cases) {
            if (testCase.name.equals(name)) return testCase;
        }
        return null;
    }

    private static List<LaboratoryCandidateTestSuiteRunner.TestCase>
            validateCases(
                List<LaboratoryCandidateTestSuiteRunner.TestCase> cases) {
        if (cases == null
                || cases.isEmpty()
                || cases.size()
                    > LaboratoryCandidateTestSuiteRunner.MAX_CASES) {
            throw new IllegalArgumentException(
                "invalid recovery suite case count");
        }
        Set<String> names = new HashSet<>();
        List<LaboratoryCandidateTestSuiteRunner.TestCase> copy =
            new ArrayList<>();
        for (LaboratoryCandidateTestSuiteRunner.TestCase testCase :
                cases) {
            if (testCase == null || !names.add(testCase.name)) {
                throw new IllegalArgumentException(
                    "invalid or duplicate recovery suite case");
            }
            copy.add(testCase);
        }
        return Collections.unmodifiableList(copy);
    }

    private static final class Match {
        final String caseName;

        Match(String caseName) {
            this.caseName = caseName;
        }
    }
}
