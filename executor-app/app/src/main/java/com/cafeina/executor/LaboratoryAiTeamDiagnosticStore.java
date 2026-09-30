package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

/**
 * Latest deterministic diagnostic summary per AI-team member.
 *
 * Inputs are already-sanitized session diagnostics plus immutable team
 * attribution. No raw task data is read or persisted.
 */
public final class LaboratoryAiTeamDiagnosticStore {
    public static final int MAX_REPORTS = LaboratoryAiTeamRegistry.MAX_MEMBERS;
    public static final int MAX_REPORT_BYTES = 24 * 1024;

    public static final class Report {
        public final String diagnosticId;
        public final String agentId;
        public final String displayName;
        public final String role;
        public final long analyzedAtEpochMs;
        public final int sessionCount;
        public final int healthySessions;
        public final int attentionSessions;
        public final int failureSessions;
        public final int failedInvocations;
        public final int cancelledInvocations;
        public final int pauseCount;
        public final int averageInvocationUsePercent;
        public final int averageInputUsePercent;
        public final String trend;
        public final String latestSessionId;
        public final String latestSeverity;
        public final List<String> recurrentSignals;
        public final List<String> recommendationCodes;

        Report(String diagnosticId, String agentId, String displayName,
                String role, long analyzedAtEpochMs, int sessionCount,
                int healthySessions, int attentionSessions, int failureSessions,
                int failedInvocations, int cancelledInvocations, int pauseCount,
                int averageInvocationUsePercent, int averageInputUsePercent,
                String trend, String latestSessionId, String latestSeverity,
                List<String> recurrentSignals,
                List<String> recommendationCodes) {
            this.diagnosticId = diagnosticId;
            this.agentId = agentId;
            this.displayName = displayName;
            this.role = role;
            this.analyzedAtEpochMs = analyzedAtEpochMs;
            this.sessionCount = sessionCount;
            this.healthySessions = healthySessions;
            this.attentionSessions = attentionSessions;
            this.failureSessions = failureSessions;
            this.failedInvocations = failedInvocations;
            this.cancelledInvocations = cancelledInvocations;
            this.pauseCount = pauseCount;
            this.averageInvocationUsePercent = averageInvocationUsePercent;
            this.averageInputUsePercent = averageInputUsePercent;
            this.trend = trend;
            this.latestSessionId = latestSessionId;
            this.latestSeverity = latestSeverity;
            this.recurrentSignals = Collections.unmodifiableList(
                new ArrayList<>(recurrentSignals));
            this.recommendationCodes = Collections.unmodifiableList(
                new ArrayList<>(recommendationCodes));
        }
    }

    private final Path root;

    public LaboratoryAiTeamDiagnosticStore(
            File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI-team diagnostic project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path projectRoot = appRoot.resolve("laboratory").resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-team-diagnostics");
    }

    public synchronized void save(Report report) throws IOException {
        validate(report);
        ensureRoot();
        Path target = root.resolve(report.agentId + ".json");
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)
                && countReports() >= MAX_REPORTS) {
            throw new IOException("AI-team diagnostic limit reached");
        }
        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("diagnosticId", report.diagnosticId);
            json.put("agentId", report.agentId);
            json.put("displayName", report.displayName);
            json.put("role", report.role);
            json.put("analyzedAtEpochMs", report.analyzedAtEpochMs);
            json.put("sessionCount", report.sessionCount);
            json.put("healthySessions", report.healthySessions);
            json.put("attentionSessions", report.attentionSessions);
            json.put("failureSessions", report.failureSessions);
            json.put("failedInvocations", report.failedInvocations);
            json.put("cancelledInvocations", report.cancelledInvocations);
            json.put("pauseCount", report.pauseCount);
            json.put("averageInvocationUsePercent",
                report.averageInvocationUsePercent);
            json.put("averageInputUsePercent",
                report.averageInputUsePercent);
            json.put("trend", report.trend);
            json.put("latestSessionId", report.latestSessionId);
            json.put("latestSeverity", report.latestSeverity);
            json.put("recurrentSignals",
                new JSONArray(report.recurrentSignals));
            json.put("recommendationCodes",
                new JSONArray(report.recommendationCodes));
            json.put("recordSha256", recordSha(report));
            writeAtomic(target, json.toString());
        } catch (JSONException error) {
            throw new IOException("could not encode AI-team diagnostic", error);
        }
    }

    public synchronized Report read(String agentId) throws IOException {
        validateAgentId(agentId);
        ensureRoot();
        return readFile(root.resolve(agentId + ".json"));
    }

    public synchronized List<Report> list() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Report> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_REPORTS) {
                throw new IOException("AI-team diagnostic history exceeds limit");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".json") || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected AI-team diagnostic entry");
                }
                validateAgentId(name.substring(0, name.length() - 5));
                result.add(readFile(path));
            }
        }
        result.sort(Comparator
            .comparingInt((Report report) -> severityRank(report.latestSeverity))
            .reversed()
            .thenComparing(report -> report.displayName)
            .thenComparing(report -> report.agentId));
        return Collections.unmodifiableList(result);
    }

    private Report readFile(Path path) throws IOException {
        if (!root.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_REPORT_BYTES) {
            throw new IOException(
                "AI-team diagnostic record missing, unsafe or too large");
        }
        try {
            JSONObject json = new JSONObject(
                new String(Files.readAllBytes(path), StandardCharsets.UTF_8));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI-team diagnostic schema");
            }
            Report report = new Report(
                json.getString("diagnosticId"),
                json.getString("agentId"),
                json.getString("displayName"),
                json.getString("role"),
                json.getLong("analyzedAtEpochMs"),
                json.getInt("sessionCount"),
                json.getInt("healthySessions"),
                json.getInt("attentionSessions"),
                json.getInt("failureSessions"),
                json.getInt("failedInvocations"),
                json.getInt("cancelledInvocations"),
                json.getInt("pauseCount"),
                json.getInt("averageInvocationUsePercent"),
                json.getInt("averageInputUsePercent"),
                json.getString("trend"),
                json.optString("latestSessionId"),
                json.optString("latestSeverity"),
                strings(json.getJSONArray("recurrentSignals")),
                strings(json.getJSONArray("recommendationCodes")));
            validate(report);
            String stored = json.getString("recordSha256");
            if (!validSha(stored) || !stored.equals(recordSha(report))) {
                throw new IOException("AI-team diagnostic integrity failed");
            }
            return report;
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI-team diagnostic record", error);
        }
    }

    private static void validate(Report report) {
        if (report == null
                || !report.diagnosticId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                || !report.diagnosticId.equals(report.agentId)
                || !report.agentId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                || report.displayName == null
                || report.displayName.trim().isEmpty()
                || report.displayName.length() > 80
                || !validRole(report.role)
                || report.analyzedAtEpochMs <= 0
                || report.sessionCount < 0
                || report.healthySessions < 0
                || report.attentionSessions < 0
                || report.failureSessions < 0
                || report.healthySessions + report.attentionSessions
                    + report.failureSessions != report.sessionCount
                || report.failedInvocations < 0
                || report.cancelledInvocations < 0
                || report.pauseCount < 0
                || report.averageInvocationUsePercent < 0
                || report.averageInvocationUsePercent > 100
                || report.averageInputUsePercent < 0
                || report.averageInputUsePercent > 100
                || !validTrend(report.trend)
                || (report.sessionCount == 0
                    && (!report.latestSessionId.isEmpty()
                        || !report.latestSeverity.isEmpty()))
                || (report.sessionCount > 0
                    && (!validUuid(report.latestSessionId)
                        || severityRank(report.latestSeverity) < 0))
                || !validCodes(report.recurrentSignals)
                || !validCodes(report.recommendationCodes)) {
            throw new IllegalArgumentException(
                "invalid AI-team diagnostic report");
        }
    }

    private static boolean validCodes(List<String> values) {
        if (values == null || values.size() > 32) return false;
        List<String> seen = new ArrayList<>();
        for (String value : values) {
            if (value == null
                    || !value.matches("[A-Z0-9_]{1,64}")
                    || seen.contains(value)) {
                return false;
            }
            seen.add(value);
        }
        return true;
    }

    private static boolean validRole(String role) {
        return LaboratoryAiTeamRegistry.ROLE_TESTER.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_DIAGNOSTIC.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_CREATOR.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_REVIEWER.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_RESEARCHER.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_ORCHESTRATOR.equals(role)
            || LaboratoryAiTeamRegistry.ROLE_SPECIALIST.equals(role);
    }

    private static boolean validTrend(String trend) {
        return "INSUFFICIENT_DATA".equals(trend)
            || "STABLE".equals(trend)
            || "IMPROVING".equals(trend)
            || "DEGRADING".equals(trend);
    }

    static int severityRank(String severity) {
        if ("HEALTHY".equals(severity)) return 0;
        if ("ATTENTION".equals(severity)) return 1;
        if ("FAILURE".equals(severity)) return 2;
        return -1;
    }

    private static void validateAgentId(String value) {
        if (value == null
                || !value.matches("[a-z0-9][a-z0-9._-]{0,63}")) {
            throw new IllegalArgumentException("invalid AI-team agent id");
        }
    }

    private static boolean validUuid(String value) {
        try {
            return value != null
                && java.util.UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private void ensureRoot() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            Path parent = root.getParent();
            if (!Files.isDirectory(parent, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(parent)) {
                throw new IOException("AI-team diagnostic parent missing or unsafe");
            }
            try {
                Files.createDirectory(root);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(root)) {
            throw new IOException("unsafe AI-team diagnostic directory");
        }
    }

    private int countReports() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            return (int) stream
                .filter(path -> path.getFileName().toString().endsWith(".json"))
                .limit(MAX_REPORTS + 1L).count();
        }
    }

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            values.add(array.getString(i));
        }
        return values;
    }

    private static void writeAtomic(Path target, String raw) throws IOException {
        byte[] bytes = raw.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_REPORT_BYTES) {
            throw new IOException("AI-team diagnostic exceeds size limit");
        }
        Path temporary = target.getParent().resolve(
            "." + target.getFileName() + ".tmp-" + java.util.UUID.randomUUID());
        boolean complete = false;
        try {
            Files.write(temporary, bytes);
            try {
                Files.move(temporary, target,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException unavailable) {
                Files.move(temporary, target,
                    StandardCopyOption.REPLACE_EXISTING);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private static String recordSha(Report report) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, report.diagnosticId);
        field(canonical, report.agentId);
        field(canonical, report.displayName);
        field(canonical, report.role);
        field(canonical, Long.toString(report.analyzedAtEpochMs));
        field(canonical, Integer.toString(report.sessionCount));
        field(canonical, Integer.toString(report.healthySessions));
        field(canonical, Integer.toString(report.attentionSessions));
        field(canonical, Integer.toString(report.failureSessions));
        field(canonical, Integer.toString(report.failedInvocations));
        field(canonical, Integer.toString(report.cancelledInvocations));
        field(canonical, Integer.toString(report.pauseCount));
        field(canonical, Integer.toString(report.averageInvocationUsePercent));
        field(canonical, Integer.toString(report.averageInputUsePercent));
        field(canonical, report.trend);
        field(canonical, report.latestSessionId);
        field(canonical, report.latestSeverity);
        list(canonical, report.recurrentSignals);
        list(canonical, report.recommendationCodes);
        return sha256(canonical.toString());
    }

    private static void field(StringBuilder out, String value) {
        String safe = value == null ? "" : value;
        out.append(safe.length()).append(':').append(safe);
    }

    private static void list(StringBuilder out, List<String> values) {
        out.append(values.size()).append('[');
        for (String value : values) field(out, value);
        out.append(']');
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(64);
            for (byte b : digest) {
                out.append(String.format(Locale.ROOT, "%02x", b & 0xff));
            }
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static boolean validSha(String value) {
        return value != null && value.matches("[0-9a-f]{64}");
    }
}
