package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Locale;
import java.util.Objects;

/**
 * Records an explicit in-app human review of a tested candidate version.
 *
 * This is a human workflow record, NOT an authorization token and NOT an
 * execution/stable-promotion gate. No method in this class grants runtime
 * capabilities. Code already running under the host app UID could forge a
 * file; the future privilege controller must not trust this record alone.
 */
public final class LaboratoryReviewDecisionStore {
    private static final String MAGIC = "CAFEINA_LAB_HUMAN_REVIEW";
    private static final String FORMAT = "1";
    private static final int MAX_BYTES = 1024;

    public enum Decision { CONTINUE_TESTING, REJECT_FOR_NOW }

    public static final class Entry {
        public final String toolId;
        public final String version;
        public final String manifestSha256;
        public final String sourceSha256;
        public final String snapshotId;
        public final String evidenceRunId;
        public final String evidenceSha256;
        public final Decision decision;
        public final long decidedAtEpochMs;

        private Entry(String toolId, String version, String manifestSha,
                String sourceSha, String snapshotId, String evidenceId,
                String evidenceSha, Decision decision, long at) {
            this.toolId = toolId;
            this.version = version;
            this.manifestSha256 = manifestSha;
            this.sourceSha256 = sourceSha;
            this.snapshotId = snapshotId;
            this.evidenceRunId = evidenceId;
            this.evidenceSha256 = evidenceSha;
            this.decision = decision;
            this.decidedAtEpochMs = at;
        }
    }

    private final LaboratoryToolRegistry registry;
    private final LaboratoryReportStore reports;
    private final Path labRoot;
    private final Path projectRoot;
    private final Path reviewRoot;

    public LaboratoryReviewDecisionStore(File appFilesDir, String projectId) {
        if (appFilesDir == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid laboratory review project");
        }
        Path app = appFilesDir.toPath().toAbsolutePath().normalize();
        labRoot = app.resolve("laboratory");
        projectRoot = labRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        reviewRoot = projectRoot.resolve("human-reviews");
        registry = new LaboratoryToolRegistry(appFilesDir, projectId);
        reports = new LaboratoryReportStore(appFilesDir, projectId);
    }

    /**
     * Only invoke from a visible, explicit UI confirmation. This is an audit
     * decision about further testing, never automatic STABLE promotion.
     */
    synchronized Entry recordDecision(String toolId, String version, Decision decision)
            throws IOException {
        Objects.requireNonNull(decision, "review decision");
        LaboratoryToolRegistry.Tool tool = registry.read(toolId, version);
        if (tool.state != LaboratoryToolRegistry.State.CANDIDATE) {
            throw new IOException("only a tested candidate can be reviewed");
        }
        String evidence = reports.read(tool.evidenceRunId);
        ensureWritable();
        Path target = reviewRoot.resolve(key(tool) + ".decision");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("this version already has a human review decision");
        }
        long now = System.currentTimeMillis();
        String evidenceHash = sha256(evidence);
        String payload = lines(MAGIC, FORMAT, tool.id, tool.version,
            tool.manifestSha256, tool.sourceSha256, tool.snapshotId,
            tool.evidenceRunId, evidenceHash, decision.name(),
            Long.toString(now));
        String text = payload + sha256(payload) + "\n";
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_BYTES) throw new IOException("review record exceeds budget");
        // Android app-data storage can reject hard links. CREATE_NEW reserves
        // this name without replacing a prior decision; interrupted writes
        // remain visibly corrupt and require manual recovery.
        try (FileChannel file = FileChannel.open(target,
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer data = ByteBuffer.wrap(bytes);
            while (data.hasRemaining()) file.write(data);
            file.force(true);
        }
        return new Entry(tool.id, tool.version, tool.manifestSha256,
            tool.sourceSha256, tool.snapshotId, tool.evidenceRunId,
            evidenceHash, decision, now);
    }

    public synchronized Entry read(String toolId, String version) throws IOException {
        LaboratoryToolRegistry.Tool tool = registry.read(toolId, version);
        if (tool.state != LaboratoryToolRegistry.State.CANDIDATE) {
            return null;
        }
        if (!Files.exists(labRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(projectRoot, LinkOption.NOFOLLOW_LINKS)
                || !Files.exists(reviewRoot, LinkOption.NOFOLLOW_LINKS)) {
            return null;
        }
        requireSafeDirectory(labRoot);
        requireSafeDirectory(projectRoot);
        requireSafeDirectory(reviewRoot);
        Path target = reviewRoot.resolve(key(tool) + ".decision");
        if (!Files.exists(target, LinkOption.NOFOLLOW_LINKS)) return null;
        if (!Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(target)
                || Files.size(target) < 1 || Files.size(target) > MAX_BYTES) {
            throw new IOException("human review record is missing, linked or oversized");
        }
        byte[] raw = Files.readAllBytes(target);
        String text = new String(raw, StandardCharsets.UTF_8);
        if (!Arrays.equals(raw, text.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("human review record has invalid UTF-8");
        }
        String[] f = text.split("\n", -1);
        if (f.length != 13 || !MAGIC.equals(f[0]) || !FORMAT.equals(f[1])
                || !f[12].isEmpty()) {
            throw new IOException("human review record format is invalid");
        }
        String payload = text.substring(0, text.length() - f[11].length() - 1);
        if (!f[11].matches("[0-9a-f]{64}") || !sha256(payload).equals(f[11])) {
            throw new IOException("human review record integrity failed");
        }
        final Decision decision;
        final long decided;
        try {
            decision = Decision.valueOf(f[9]);
            decided = Long.parseLong(f[10]);
        } catch (IllegalArgumentException invalid) {
            throw new IOException("invalid human review decision", invalid);
        }
        if (!tool.id.equals(f[2]) || !tool.version.equals(f[3])
                || !tool.manifestSha256.equals(f[4])
                || !tool.sourceSha256.equals(f[5])
                || !tool.snapshotId.equals(f[6])
                || !tool.evidenceRunId.equals(f[7])
                || decided <= 0) {
            throw new IOException("human review decision does not match candidate");
        }
        String evidence = reports.read(tool.evidenceRunId);
        if (!sha256(evidence).equals(f[8])) {
            throw new IOException("reviewed evidence changed after human decision");
        }
        return new Entry(tool.id, tool.version, f[4], f[5], f[6],
            f[7], f[8], decision, decided);
    }

    private static String key(LaboratoryToolRegistry.Tool tool) {
        return tool.id + "@" + tool.version;
    }

    private void ensureWritable() throws IOException {
        ensureSafeDirectory(labRoot);
        ensureSafeDirectory(projectRoot);
        ensureSafeDirectory(reviewRoot);
    }

    private static void ensureSafeDirectory(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Validate below.
            }
        }
        requireSafeDirectory(path);
    }

    private static void requireSafeDirectory(Path path) throws IOException {
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe human review directory");
        }
    }

    private static String lines(String... values) {
        StringBuilder out = new StringBuilder();
        for (String item : values) out.append(item).append('\n');
        return out.toString();
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                value.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte number : digest) {
                hex.append(String.format(Locale.ROOT, "%02x", number & 255));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
