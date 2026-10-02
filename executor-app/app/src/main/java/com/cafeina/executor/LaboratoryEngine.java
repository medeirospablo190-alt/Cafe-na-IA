package com.cafeina.executor;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Offline, deterministic laboratory harness. It does not execute generated code.
 * Only compiled-in, explicitly allowlisted probes can run in the host process.
 * Future candidate code must use a separate, isolated execution worker.
 */
public final class LaboratoryEngine {
    public static final String FINGERPRINT_TOOL = "source-fingerprint";
    public static final String FINGERPRINT_VERSION = "1.0.0";
    public static final String WORLD_CONTACT_TOOL = LaboratoryTestWorld.TOOL_ID;
    public static final String WORLD_CONTACT_VERSION = LaboratoryTestWorld.TOOL_VERSION;
    public static final int MAX_CASES = 16;
    public static final int MAX_SOURCE_CHARS = 16 * 1024;
    public static final int MAX_TOTAL_SOURCE_CHARS = 96 * 1024;
    public static final int MAX_RUNTIME_MS = 10_000;

    public enum Status { PASS, FAIL, CANCELLED, TIMEOUT }

    public static final class Cancellation {
        private final AtomicBoolean cancelled = new AtomicBoolean();
        public void cancel() { cancelled.set(true); }
        public boolean isCancelled() { return cancelled.get(); }
    }

    public static final class TestCase {
        public final String name;
        public final String candidateSource;
        public final String expectedOutput;

        public TestCase(String name, String candidateSource, String expectedOutput) {
            if (name == null || !name.matches("[a-zA-Z0-9_-]{1,64}")) {
                throw new IllegalArgumentException("invalid laboratory test name");
            }
            if (candidateSource == null || candidateSource.length() > MAX_SOURCE_CHARS) {
                throw new IllegalArgumentException("laboratory input exceeds limit");
            }
            if (expectedOutput == null || expectedOutput.length() > 256) {
                throw new IllegalArgumentException("invalid expected output");
            }
            this.name = name;
            this.candidateSource = candidateSource;
            this.expectedOutput = expectedOutput;
        }
    }

    public static final class Request {
        public final String toolId;
        public final String toolVersion;
        public final long seed;
        public final int timeoutMs;
        public final List<TestCase> cases;

        public Request(String toolId, String toolVersion, long seed, int timeoutMs,
                List<TestCase> cases) {
            boolean fingerprint = FINGERPRINT_TOOL.equals(toolId)
                && FINGERPRINT_VERSION.equals(toolVersion);
            boolean world = WORLD_CONTACT_TOOL.equals(toolId)
                && WORLD_CONTACT_VERSION.equals(toolVersion);
            if (!fingerprint && !world) {
                throw new IllegalArgumentException("tool is not allowlisted for host laboratory");
            }
            if (timeoutMs < 1 || timeoutMs > MAX_RUNTIME_MS) {
                throw new IllegalArgumentException("invalid laboratory timeout");
            }
            if (cases == null || cases.isEmpty() || cases.size() > MAX_CASES) {
                throw new IllegalArgumentException("invalid laboratory test count");
            }
            int total = 0;
            for (TestCase test : cases) {
                Objects.requireNonNull(test, "laboratory test");
                if (world) LaboratoryTestWorld.parseProbe(test.candidateSource);
                total += test.candidateSource.length();
                if (total > MAX_TOTAL_SOURCE_CHARS) {
                    throw new IllegalArgumentException("laboratory batch exceeds input budget");
                }
            }
            this.toolId = toolId;
            this.toolVersion = toolVersion;
            this.seed = seed;
            this.timeoutMs = timeoutMs;
            this.cases = Collections.unmodifiableList(new ArrayList<>(cases));
        }
    }

    public static final class Check {
        public final String name;
        public final boolean passed;
        public final String actualOutput;
        public final String expectedOutput;
        public final String inputSha256;
        public final String reason;

        private Check(String name, boolean passed, String actualOutput,
                String expectedOutput, String inputSha256, String reason) {
            this.name = name;
            this.passed = passed;
            this.actualOutput = actualOutput;
            this.expectedOutput = expectedOutput;
            this.inputSha256 = inputSha256;
            this.reason = reason;
        }
    }

    public static final class Report {
        public final String runId;
        public final String toolId;
        public final String toolVersion;
        public final String stage;
        public final long seed;
        public final long startedAtEpochMs;
        public final long durationMs;
        public final String candidateBatchSha256;
        public final String environmentSha256;
        public final Status status;
        public final int passed;
        public final int failed;
        public final List<Check> checks;

        private Report(String runId, Request request, long started, long duration,
                String batchHash, Status status, int passed, int failed, List<Check> checks) {
            this.runId = runId;
            this.toolId = request.toolId;
            this.toolVersion = request.toolVersion;
            this.stage = "EXPERIMENTAL";
            this.seed = request.seed;
            this.startedAtEpochMs = started;
            this.durationMs = duration;
            this.candidateBatchSha256 = batchHash;
            this.environmentSha256 =
                hostEnvironmentSha256(request);
            this.status = status;
            this.passed = passed;
            this.failed = failed;
            this.checks = Collections.unmodifiableList(new ArrayList<>(checks));
        }
    }

    private LaboratoryEngine() {}

    /**
     * No file system, network, Android app data or runtime bridge is passed to
     * this harness. Allowlisted probes fingerprint bounded inputs or query an
     * immutable geometry fixture. Neither executes candidate source code.
     */
    public static Report run(Request request, Cancellation cancellation) {
        Objects.requireNonNull(request, "request");
        Objects.requireNonNull(cancellation, "cancellation");
        String id = UUID.randomUUID().toString();
        long started = System.currentTimeMillis();
        long startNanos = System.nanoTime();
        String batchHash = batchHash(request);
        List<Check> checks = new ArrayList<>();
        int passed = 0;
        int failed = 0;
        Status status = Status.PASS;

        for (TestCase test : request.cases) {
            if (cancellation.isCancelled()) {
                status = Status.CANCELLED;
                break;
            }
            if (elapsedMs(startNanos) >= request.timeoutMs) {
                status = Status.TIMEOUT;
                break;
            }
            String actual = WORLD_CONTACT_TOOL.equals(request.toolId)
                ? LaboratoryTestWorld.contact(test.candidateSource).outputLine()
                : fingerprint(test.candidateSource);
            boolean matches = actual.equals(test.expectedOutput);
            if (matches) passed++;
            else failed++;
            checks.add(new Check(test.name, matches, actual, test.expectedOutput,
                sha256(test.candidateSource.getBytes(StandardCharsets.UTF_8)),
                matches ? "expected output matched" : "expected output mismatch"));
            if (cancellation.isCancelled()) {
                status = Status.CANCELLED;
                break;
            }
            if (elapsedMs(startNanos) >= request.timeoutMs) {
                status = Status.TIMEOUT;
                break;
            }
        }

        if (status == Status.PASS && failed > 0) status = Status.FAIL;
        return new Report(id, request, started, elapsedMs(startNanos),
            batchHash, status, passed, failed, checks);
    }

    static String hostEnvironmentSha256(
            Request request) {
        StringBuilder identity = new StringBuilder()
            .append("CAFEINA_HOST_LAB_V1|")
            .append(request.toolId)
            .append("|")
            .append(request.toolVersion);
        if (WORLD_CONTACT_TOOL.equals(request.toolId)) {
            identity.append("|fixture=")
                .append(LaboratoryTestWorld.fixtureSha256());
        }
        return sha256(
            identity.toString().getBytes(StandardCharsets.UTF_8));
    }

    /** Stable, source-only fingerprint. This is not a Luau correctness verdict. */
    public static String fingerprint(String source) {
        Objects.requireNonNull(source, "source");
        if (source.length() > MAX_SOURCE_CHARS) {
            throw new IllegalArgumentException("laboratory input exceeds limit");
        }
        byte[] bytes = source.getBytes(StandardCharsets.UTF_8);
        int lines = 1;
        for (int i = 0; i < source.length(); i++) {
            if (source.charAt(i) == '\n') lines++;
        }
        return "sha256:" + sha256(bytes) + ";bytes:" + bytes.length + ";lines:" + lines;
    }

    private static String batchHash(Request request) {
        MessageDigest digest = digest();
        for (TestCase test : request.cases) {
            byte[] bytes = test.candidateSource.getBytes(StandardCharsets.UTF_8);
            digest.update((byte) (bytes.length >>> 24));
            digest.update((byte) (bytes.length >>> 16));
            digest.update((byte) (bytes.length >>> 8));
            digest.update((byte) bytes.length);
            digest.update(bytes);
        }
        return hex(digest.digest());
    }

    private static long elapsedMs(long startedNanos) {
        return (System.nanoTime() - startedNanos) / 1_000_000L;
    }

    private static String sha256(byte[] bytes) {
        return hex(digest().digest(bytes));
    }

    private static MessageDigest digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            out.append(String.format(Locale.ROOT, "%02x", value & 0xff));
        }
        return out.toString();
    }
}
