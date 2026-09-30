package com.cafeina.executor;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
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
import java.util.UUID;

/**
 * Immutable private catalog of deterministic test-agent scenarios.
 *
 * Raw fixture input/expected values are task data, not diagnostic reports, and
 * remain only in app-private storage. Test-agent reports continue to persist
 * hashes only.
 */
public final class LaboratoryAiTestScenarioStore {
    public static final int MAX_SCENARIOS = 128;
    public static final int MAX_SCENARIO_BYTES = 96 * 1024;
    public static final int MAX_NAME_CHARS = 80;

    public static final class Scenario {
        public final String scenarioId;
        public final String name;
        public final long createdAtEpochMs;
        public final boolean stopOnFailure;
        public final int stepCount;
        public final String scenarioSha256;
        public final LaboratoryAiTestAgent.Plan plan;

        private Scenario(String scenarioId, String name, long createdAtEpochMs,
                boolean stopOnFailure, String scenarioSha256,
                LaboratoryAiTestAgent.Plan plan) {
            this.scenarioId = scenarioId;
            this.name = name;
            this.createdAtEpochMs = createdAtEpochMs;
            this.stopOnFailure = stopOnFailure;
            this.stepCount = plan.steps.size();
            this.scenarioSha256 = scenarioSha256;
            this.plan = plan;
        }
    }

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path scenarioRoot;

    public LaboratoryAiTestScenarioStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid test-scenario project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        scenarioRoot = projectRoot.resolve("ai-test-scenarios");
    }

    public synchronized Scenario create(String name,
            LaboratoryAiTestAgent.Plan plan) throws IOException {
        String safeName = validateName(name);
        if (plan == null) throw new IllegalArgumentException("test scenario plan missing");

        ensureRoot();
        if (countScenarios() >= MAX_SCENARIOS) {
            throw new IOException(
                "test-scenario limit reached; existing scenarios preserved");
        }

        String scenarioId = UUID.randomUUID().toString();
        long createdAt = System.currentTimeMillis();
        String scenarioSha = scenarioSha(
            scenarioId, safeName, createdAt, plan);

        try {
            JSONObject json = new JSONObject();
            json.put("schemaVersion", 1);
            json.put("scenarioId", scenarioId);
            json.put("name", safeName);
            json.put("createdAtEpochMs", createdAt);
            json.put("stopOnFailure", plan.stopOnFailure);
            JSONArray steps = new JSONArray();
            for (LaboratoryAiTestAgent.Step step : plan.steps) {
                JSONObject item = new JSONObject();
                item.put("name", step.name);
                item.put("toolId", step.toolId);
                item.put("input", step.input);
                item.put("expectedFirstReturn", step.expectedFirstReturn);
                steps.put(item);
            }
            json.put("steps", steps);
            json.put("scenarioSha256", scenarioSha);
            writeNew(scenarioRoot.resolve(scenarioId + ".json"), json);
        } catch (JSONException error) {
            throw new IOException("could not encode test scenario", error);
        }
        return read(scenarioId);
    }

    public synchronized Scenario read(String scenarioId) throws IOException {
        if (!validUuid(scenarioId)) {
            throw new IllegalArgumentException("invalid test scenario id");
        }
        ensureRoot();
        Path path = scenarioRoot.resolve(scenarioId + ".json");
        try {
            JSONObject json = new JSONObject(readSafe(path));
            if (json.getInt("schemaVersion") != 1
                    || !scenarioId.equals(json.getString("scenarioId"))) {
                throw new IOException("test scenario identity mismatch");
            }
            String name = validateName(json.getString("name"));
            long createdAt = json.getLong("createdAtEpochMs");
            boolean stopOnFailure = json.getBoolean("stopOnFailure");
            JSONArray stepsJson = json.getJSONArray("steps");
            if (createdAt <= 0
                    || stepsJson.length() < 1
                    || stepsJson.length() > LaboratoryAiTestAgent.MAX_STEPS) {
                throw new IOException("test scenario metadata invalid");
            }

            List<LaboratoryAiTestAgent.Step> steps = new ArrayList<>();
            for (int i = 0; i < stepsJson.length(); i++) {
                JSONObject item = stepsJson.getJSONObject(i);
                steps.add(new LaboratoryAiTestAgent.Step(
                    item.getString("name"),
                    item.getString("toolId"),
                    item.getString("input"),
                    item.getString("expectedFirstReturn")));
            }
            LaboratoryAiTestAgent.Plan plan =
                new LaboratoryAiTestAgent.Plan(steps, stopOnFailure);
            String storedSha = json.getString("scenarioSha256");
            String expectedSha =
                scenarioSha(scenarioId, name, createdAt, plan);
            if (!validSha(storedSha) || !storedSha.equals(expectedSha)) {
                throw new IOException("test scenario integrity failed");
            }
            return new Scenario(
                scenarioId, name, createdAt, stopOnFailure, storedSha, plan);
        } catch (JSONException | IllegalArgumentException error) {
            throw new IOException("invalid test scenario", error);
        }
    }

    public synchronized List<Scenario> list() throws IOException {
        if (!Files.exists(scenarioRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        ensureRoot();
        List<Scenario> result = new ArrayList<>();
        try (java.util.stream.Stream<Path> stream = Files.list(scenarioRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_SCENARIOS) {
                throw new IOException("test-scenario directory exceeds limit");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".json")
                        || !validUuid(name.substring(0, name.length() - 5))
                        || Files.isSymbolicLink(path)) {
                    throw new IOException("unexpected test-scenario entry");
                }
                result.add(read(name.substring(0, name.length() - 5)));
            }
        }
        result.sort(Comparator
            .comparingLong((Scenario scenario) -> scenario.createdAtEpochMs)
            .reversed()
            .thenComparing(scenario -> scenario.scenarioId));
        return Collections.unmodifiableList(result);
    }

    private void ensureRoot() throws IOException {
        ensureSafeDirectory(laboratoryRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(scenarioRoot);
    }

    private int countScenarios() throws IOException {
        try (java.util.stream.Stream<Path> stream = Files.list(scenarioRoot)) {
            return (int) stream
                .filter(path -> {
                    String name = path.getFileName().toString();
                    return name.endsWith(".json")
                        && validUuid(name.substring(0, name.length() - 5));
                })
                .limit(MAX_SCENARIOS + 1L)
                .count();
        }
    }

    private static String validateName(String name) {
        if (name == null) throw new IllegalArgumentException("scenario name missing");
        String value = name.trim();
        if (value.isEmpty() || value.length() > MAX_NAME_CHARS) {
            throw new IllegalArgumentException("scenario name empty or too large");
        }
        return value;
    }

    private String readSafe(Path path) throws IOException {
        if (!scenarioRoot.equals(path.getParent())
                || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1
                || Files.size(path) > MAX_SCENARIO_BYTES) {
            throw new IOException("test scenario missing, unsafe or too large");
        }
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }

    private static void writeNew(Path destination, JSONObject json)
            throws IOException, JSONException {
        if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("test scenario already exists");
        }
        byte[] bytes = json.toString(2).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_SCENARIO_BYTES) {
            throw new IOException("test scenario exceeds size budget");
        }

        Path temporary = destination.getParent().resolve(
            "." + destination.getFileName() + ".tmp-" + UUID.randomUUID());
        boolean complete = false;
        try {
            Files.createFile(temporary);
            try (FileOutputStream output = new FileOutputStream(
                    temporary.toFile(), false)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                throw new IOException("test scenario already exists");
            }
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException unavailable) {
                Files.move(temporary, destination);
            }
            complete = true;
        } finally {
            if (!complete) Files.deleteIfExists(temporary);
        }
    }

    private static String scenarioSha(String scenarioId, String name,
            long createdAt, LaboratoryAiTestAgent.Plan plan) {
        StringBuilder canonical = new StringBuilder();
        field(canonical, scenarioId);
        field(canonical, name);
        field(canonical, Long.toString(createdAt));
        field(canonical, Boolean.toString(plan.stopOnFailure));
        field(canonical, Integer.toString(plan.steps.size()));
        for (LaboratoryAiTestAgent.Step step : plan.steps) {
            field(canonical, step.name);
            field(canonical, step.toolId);
            field(canonical, step.input);
            field(canonical, step.expectedFirstReturn);
        }
        return sha256(canonical.toString());
    }

    private static void field(StringBuilder out, String value) {
        String safe = value == null ? "" : value;
        out.append(safe.length()).append(':').append(safe);
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe test-scenario directory");
        }
    }

    private static boolean validUuid(String value) {
        try {
            return value != null && UUID.fromString(value).toString().equals(value);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static boolean validSha(String value) {
        return value != null && value.matches("[0-9a-f]{64}");
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
}
