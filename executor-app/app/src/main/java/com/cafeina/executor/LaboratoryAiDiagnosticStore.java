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
 * Latest deterministic diagnostic snapshot for each AI session.
 *
 * The store contains only bounded counters, state/reason codes and
 * recommendations. Raw prompts, tool inputs, returns, stdout and errors are
 * never persisted here.
 */
public final class LaboratoryAiDiagnosticStore {
    public static final int MAX_REPORTS = 64;
    public static final int MAX_REPORT_BYTES = 16 * 1024;

    public static final class Report {
        public final String diagnosticId;
        public final String sessionId;
        public final long analyzedAtEpochMs;
        public final String state;
        public final String terminalReason;
        public final String severity;
        public final int eventCount;
        public final int invocationResults;
        public final int failedInvocations;
        public final int cancelledInvocations;
        public final int pauseCount;
        public final int invocationUsePercent;
        public final int inputUsePercent;
        public final List<String> recommendationCodes;

        Report(String diagnosticId, String sessionId, long analyzedAtEpochMs,
                String state, String terminalReason, String severity,
                int eventCount, int invocationResults, int failedInvocations,
                int cancelledInvocations, int pauseCount,
                int invocationUsePercent, int inputUsePercent,
                List<String> recommendationCodes) {
            this.diagnosticId = diagnosticId;
            this.sessionId = sessionId;
            this.analyzedAtEpochMs = analyzedAtEpochMs;
            this.state = state;
            this.terminalReason = terminalReason;
            this.severity = severity;
            this.eventCount = eventCount;
            this.invocationResults = invocationResults;
            this.failedInvocations = failedInvocations;
            this.cancelledInvocations = cancelledInvocations;
            this.pauseCount = pauseCount;
            this.invocationUsePercent = invocationUsePercent;
            this.inputUsePercent = inputUsePercent;
            this.recommendationCodes = Collections.unmodifiableList(
                new ArrayList<>(recommendationCodes));
        }
    }

    private final Path root;

    public LaboratoryAiDiagnosticStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid AI diagnostic project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        Path projectRoot = appRoot.resolve("laboratory").resolve(
            projectId.isEmpty() ? "legacy" : "project-" + projectId);
        root = projectRoot.resolve("ai-diagnostics");
    }

    public synchronized void save(Report report) throws IOException {
        validate(report);
        ensureRoot();

        Path target = root.resolve(report.sessionId + ".json");
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)
                && countReports() >= MAX_REPORTS) {
            throw new IOException(
                "AI diagnostic limit reached; existing history was preserved");
        }

        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("diagnosticId", report.diagnosticId);
            json.put("sessionId", report.sessionId);
            json.put("analyzedAtEpochMs", report.analyzedAtEpochMs);
            json.put("state", report.state);
            json.put("terminalReason", report.terminalReason);
            json.put("severity", report.severity);
            json.put("eventCount", report.eventCount);
            json.put("invocationResults", report.invocationResults);
            json.put("failedInvocations", report.failedInvocations);
            json.put("cancelledInvocations", report.cancelledInvocations);
            json.put("pauseCount", report.pauseCount);
            json.put("invocationUsePercent", report.invocationUsePercent);
            json.put("inputUsePercent", report.inputUsePercent);
            json.put("recommendationCodes",
                new JSONArray(report.recommendationCodes));
            json.put("recordSha256", recordSha(report));
            writeAtomic(target, json.toString());
        } catch (JSONException error) {
            throw new IOException("could not encode AI diagnostic", error);
        }
    }

    public synchronized Report read(String sessionId) throws IOException {
        validateSessionId(sessionId);
        ensureRoot();
        return readFile(root.resolve(sessionId + ".json"));
    }

    public synchronized List<Report> list() throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Report> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            List<Path> files = new ArrayList<>();
            stream.forEach(files::add);
            if (files.size() > MAX_REPORTS) {
                throw new IOException("AI diagnostic history exceeds limit");
            }
            for (Path path : files) {
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                        || Files.isSymbolicLink(path)
                        || !path.getFileName().toString()
                            .matches("[0-9a-fA-F-]{36}\\.json")) {
                    throw new IOException("unexpected AI diagnostic entry");
                }
                result.add(readFile(path));
            }
        }
        result.sort(Comparator
            .comparingLong((Report report) -> report.analyzedAtEpochMs)
            .reversed()
            .thenComparing(report -> report.sessionId));
        return Collections.unmodifiableList(result);
    }

    private Report readFile(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_REPORT_BYTES) {
            throw new IOException("AI diagnostic record missing, unsafe or too large");
        }
        try {
            JSONObject json = new JSONObject(
                new String(Files.readAllBytes(path), StandardCharsets.UTF_8));
            if (json.getInt("schemaVersion") != 1) {
                throw new IOException("unsupported AI diagnostic schema");
            }
            List<String> recommendations = strings(
                json.getJSONArray("recommendationCodes"));
            Report report = new Report(
                json.getString("diagnosticId"),
                json.getString("sessionId"),
                json.getLong("analyzedAtEpochMs"),
                json.getString("state"),
                json.optString("terminalReason"),
                json.getString("severity"),
                json.getInt("eventCount"),
                json.getInt("invocationResults"),
                json.getInt("failedInvocations"),
                json.getInt("cancelledInvocations"),
                json.getInt("pauseCount"),
                json.getInt("invocationUsePercent"),
                json.getInt("inputUsePercent"),
                recommendations);
            validate(report);
            String stored = json.getString("recordSha256");
            if (!validSha(stored) || !stored.equals(recordSha(report))) {
                throw new IOException("AI diagnostic integrity failed");
            }
            return report;
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid AI diagnostic record", error);
        }
    }

    private void ensureRoot() throws IOException {
        Path laboratoryRoot = root.getParent().getParent();
        Path projectRoot = root.getParent();
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(root);
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("unsafe AI diagnostic directory");
            }
            return;
        }
        Files.createDirectories(path);
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("could not create safe AI diagnostic directory");
        }
    }

    private int countReports() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(root)) {
            return (int) stream
                .filter(path -> Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS))
                .limit(MAX_REPORTS + 1L).count();
        }
    }

    private static void writeAtomic(Path target, String text) throws IOException {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 1 || bytes.length > MAX_REPORT_BYTES) {
            throw new IOException("AI diagnostic record is too large");
        }
        Path temp = target.resolveSibling(
            target.getFileName().toString() + ".tmp");
        Files.write(temp, bytes);
        try {
            Files.move(temp, target, StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING);
        } catch (AtomicMoveNotSupportedException ignored) {
            Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING);
        } finally {
            Files.deleteIfExists(temp);
        }
    }

    private static void validate(Report report) {
        if (report == null) throw new IllegalArgumentException("diagnostic missing");
        validateSessionId(report.sessionId);
        if (!report.diagnosticId.equals(report.sessionId)
                || report.analyzedAtEpochMs <= 0
                || !report.state.matches("[A-Z_]{2,32}")
                || report.terminalReason == null
                || report.terminalReason.length() > 64
                || !report.severity.matches("HEALTHY|ATTENTION|FAILURE")
                || report.eventCount < 1
                || report.eventCount > LaboratoryAiSessionStore.MAX_EVENTS_PER_SESSION
                || report.invocationResults < 0
                || report.invocationResults > 64
                || report.failedInvocations < 0
                || report.failedInvocations > report.invocationResults
                || report.cancelledInvocations < 0
                || report.cancelledInvocations > report.invocationResults
                || report.pauseCount < 0
                || report.pauseCount > LaboratoryAiSessionStore.MAX_EVENTS_PER_SESSION
                || report.invocationUsePercent < 0
                || report.invocationUsePercent > 100
                || report.inputUsePercent < 0
                || report.inputUsePercent > 100
                || report.recommendationCodes == null
                || report.recommendationCodes.isEmpty()
                || report.recommendationCodes.size() > 8) {
            throw new IllegalArgumentException("invalid AI diagnostic");
        }
        for (String code : report.recommendationCodes) {
            if (code == null || !code.matches("[A-Z0-9_]{2,64}")) {
                throw new IllegalArgumentException(
                    "invalid AI diagnostic recommendation");
            }
        }
    }

    private static void validateSessionId(String sessionId) {
        if (sessionId == null
                || !sessionId.matches(
                    "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                    + "[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")) {
            throw new IllegalArgumentException("invalid AI diagnostic session");
        }
    }

    private static List<String> strings(JSONArray array) throws JSONException {
        List<String> result = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            result.add(array.getString(i));
        }
        return result;
    }

    private static String recordSha(Report report) {
        StringBuilder canonical = new StringBuilder()
            .append(report.diagnosticId).append('\n')
            .append(report.sessionId).append('\n')
            .append(report.analyzedAtEpochMs).append('\n')
            .append(report.state).append('\n')
            .append(report.terminalReason).append('\n')
            .append(report.severity).append('\n')
            .append(report.eventCount).append('\n')
            .append(report.invocationResults).append('\n')
            .append(report.failedInvocations).append('\n')
            .append(report.cancelledInvocations).append('\n')
            .append(report.pauseCount).append('\n')
            .append(report.invocationUsePercent).append('\n')
            .append(report.inputUsePercent);
        for (String code : report.recommendationCodes) {
            canonical.append('\n').append(code);
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest(
                canonical.toString().getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte value : bytes) {
                hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static boolean validSha(String value) {
        return value != null && value.matches("[0-9a-f]{64}");
    }
}
