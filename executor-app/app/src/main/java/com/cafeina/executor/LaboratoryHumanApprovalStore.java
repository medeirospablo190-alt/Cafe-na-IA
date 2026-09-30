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
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.stream.Stream;

/**
 * Create-only receipts for explicit user review decisions.
 *
 * IMPORTANT: a receipt means "approved by the user for future activation".
 * It does NOT execute the tool, grant new capabilities, modify project data or
 * switch a version to STABLE by itself. The activation path is intentionally
 * absent from this class.
 *
 * The UI that calls recordDeviceCredentialApproval() must first receive
 * RESULT_OK from Android's device-credential confirmation screen. This is an
 * application policy boundary, not protection against root or arbitrary code
 * already running with the app UID.
 */
public final class LaboratoryHumanApprovalStore {
    private static final String MAGIC = "CAFEINA_LAB_HUMAN_APPROVAL";
    private static final String FORMAT = "1";
    private static final String AUTH_METHOD = "ANDROID_DEVICE_CREDENTIAL";
    private static final int MAX_RECEIPT_BYTES = 1536;
    private static final int MAX_APPROVALS = 64;

    private final Path laboratoryRoot;
    private final Path projectRoot;
    private final Path approvalRoot;
    private final LaboratoryToolRegistry registry;

    public static final class Approval {
        public final String toolId;
        public final String version;
        public final String manifestSha256;
        public final String evidenceRunId;
        public final String sourceSha256;
        public final long approvedAtEpochMs;
        public final String authenticationMethod;
        public final String receiptSha256;

        private Approval(String toolId, String version, String manifestSha,
                String evidenceRunId, String sourceSha, long approvedAt,
                String authMethod, String receiptSha) {
            this.toolId = toolId;
            this.version = version;
            this.manifestSha256 = manifestSha;
            this.evidenceRunId = evidenceRunId;
            this.sourceSha256 = sourceSha;
            this.approvedAtEpochMs = approvedAt;
            this.authenticationMethod = authMethod;
            this.receiptSha256 = receiptSha;
        }
    }

    public LaboratoryHumanApprovalStore(File appFilesDirectory, String projectId) {
        if (appFilesDirectory == null || projectId == null
                || (!projectId.isEmpty() && !ProjectStore.isValidId(projectId))) {
            throw new IllegalArgumentException("invalid human approval project");
        }
        Path appRoot = appFilesDirectory.toPath().toAbsolutePath().normalize();
        laboratoryRoot = appRoot.resolve("laboratory");
        projectRoot = laboratoryRoot.resolve(projectId.isEmpty()
            ? "legacy" : "project-" + projectId);
        approvalRoot = projectRoot.resolve("tools").resolve("approvals");
        registry = new LaboratoryToolRegistry(appFilesDirectory, projectId);
    }

    /**
     * Only call after Android confirms the user's device credential.
     * The candidate is re-read and re-validated here immediately before writing.
     */
    synchronized Approval recordDeviceCredentialApproval(
            String toolId, String version, long authenticatedAtEpochMs) throws IOException {
        long now = System.currentTimeMillis();
        if (authenticatedAtEpochMs <= 0 || authenticatedAtEpochMs > now + 10_000L
                || now - authenticatedAtEpochMs > 60_000L) {
            throw new IOException("device authentication is missing or stale");
        }
        LaboratoryToolRegistry.Tool tool = registry.read(toolId, version);
        if (tool.state != LaboratoryToolRegistry.State.CANDIDATE
                || tool.evidenceRunId.isEmpty()) {
            throw new IOException("only evidence-backed candidates can be approved");
        }
        ensureWritable();
        if (countReceipts() >= MAX_APPROVALS) {
            throw new IOException("approval limit reached; existing decisions were preserved");
        }
        Path target = approvalRoot.resolve(key(toolId, version) + ".approval");
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("this tool version already has an approval decision");
        }

        String payload = lines(MAGIC, FORMAT, tool.id, tool.version,
            tool.manifestSha256, tool.evidenceRunId, tool.sourceSha256,
            Long.toString(authenticatedAtEpochMs), AUTH_METHOD);
        String receiptHash = sha256(payload);
        writeNew(target, payload + receiptHash + "\n");
        return read(toolId, version);
    }

    public synchronized boolean isApproved(String toolId, String version) throws IOException {
        if (!Files.exists(approvalRoot, LinkOption.NOFOLLOW_LINKS)) return false;
        Path receipt = approvalRoot.resolve(key(toolId, version) + ".approval");
        if (!Files.exists(receipt, LinkOption.NOFOLLOW_LINKS)) return false;
        read(toolId, version);
        return true;
    }

    public synchronized Approval read(String toolId, String version) throws IOException {
        LaboratoryToolRegistry.Tool tool = registry.read(toolId, version);
        if (tool.state != LaboratoryToolRegistry.State.CANDIDATE) {
            throw new IOException("approval is only valid while tool remains a candidate");
        }
        requireExistingDirectory();
        Path path = approvalRoot.resolve(key(toolId, version) + ".approval");
        String[] fields = parse(path);
        if (!tool.id.equals(fields[2]) || !tool.version.equals(fields[3])
                || !tool.manifestSha256.equals(fields[4])
                || !tool.evidenceRunId.equals(fields[5])
                || !tool.sourceSha256.equals(fields[6])
                || !AUTH_METHOD.equals(fields[8])) {
            throw new IOException("approval receipt no longer matches candidate evidence");
        }
        final long approvedAt;
        try {
            approvedAt = Long.parseLong(fields[7]);
        } catch (NumberFormatException bad) {
            throw new IOException("approval timestamp is invalid", bad);
        }
        if (approvedAt <= 0 || approvedAt > System.currentTimeMillis() + 10_000L) {
            throw new IOException("approval timestamp is outside accepted bounds");
        }
        return new Approval(tool.id, tool.version, tool.manifestSha256,
            tool.evidenceRunId, tool.sourceSha256, approvedAt, fields[8], fields[9]);
    }

    public synchronized List<Approval> list() throws IOException {
        if (!Files.exists(approvalRoot, LinkOption.NOFOLLOW_LINKS)) {
            return Collections.emptyList();
        }
        requireExistingDirectory();
        List<Approval> approvals = new ArrayList<>();
        try (Stream<Path> stream = Files.list(approvalRoot)) {
            List<Path> paths = new ArrayList<>();
            stream.forEach(paths::add);
            if (paths.size() > MAX_APPROVALS) {
                throw new IOException("approval vault exceeds entry budget");
            }
            for (Path path : paths) {
                String name = path.getFileName().toString();
                if (!name.endsWith(".approval")) {
                    throw new IOException("unexpected file in approval vault");
                }
                String k = name.substring(0, name.length() - ".approval".length());
                int split = k.lastIndexOf('@');
                if (split <= 0 || split == k.length() - 1) {
                    throw new IOException("invalid approval filename");
                }
                approvals.add(read(k.substring(0, split), k.substring(split + 1)));
            }
        }
        approvals.sort(Comparator.comparingLong((Approval a) -> a.approvedAtEpochMs)
            .reversed().thenComparing(a -> a.toolId).thenComparing(a -> a.version));
        return Collections.unmodifiableList(approvals);
    }

    private void ensureWritable() throws IOException {
        ensureSafeDir(laboratoryRoot);
        ensureSafeDir(projectRoot);
        ensureSafeDir(projectRoot.resolve("tools"));
        ensureSafeDir(approvalRoot);
    }

    private void requireExistingDirectory() throws IOException {
        for (Path path : new Path[]{laboratoryRoot, projectRoot,
                projectRoot.resolve("tools"), approvalRoot}) {
            if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    || Files.isSymbolicLink(path)) {
                throw new IOException("approval directory missing or unsafe");
            }
        }
    }

    private int countReceipts() throws IOException {
        try (Stream<Path> stream = Files.list(approvalRoot)) {
            return (int) stream.limit(MAX_APPROVALS + 1).count();
        }
    }

    private static String[] parse(Path path) throws IOException {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)
                || Files.size(path) < 1 || Files.size(path) > MAX_RECEIPT_BYTES) {
            throw new IOException("approval receipt missing, linked or oversized");
        }
        byte[] raw = Files.readAllBytes(path);
        String serialized = new String(raw, StandardCharsets.UTF_8);
        if (!java.util.Arrays.equals(raw, serialized.getBytes(StandardCharsets.UTF_8))) {
            throw new IOException("approval receipt is not valid UTF-8");
        }
        String[] fields = serialized.split("\n", -1);
        if (fields.length != 11 || !MAGIC.equals(fields[0])
                || !FORMAT.equals(fields[1]) || !fields[10].isEmpty()) {
            throw new IOException("approval receipt format is invalid");
        }
        String canonical = serialized.substring(0,
            serialized.length() - fields[9].length() - 1);
        if (!fields[9].matches("[0-9a-f]{64}")
                || !sha256(canonical).equals(fields[9])) {
            throw new IOException("approval receipt integrity check failed");
        }
        return fields;
    }

    private static void writeNew(Path destination, String content) throws IOException {
        byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_RECEIPT_BYTES) {
            throw new IOException("approval receipt exceeds size limit");
        }
        try (FileChannel output = FileChannel.open(destination,
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer buffer = ByteBuffer.wrap(bytes);
            while (buffer.hasRemaining()) output.write(buffer);
            output.force(true);
        }
    }

    private static void ensureSafeDir(Path path) throws IOException {
        if (!Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
            try {
                Files.createDirectory(path);
            } catch (java.nio.file.FileAlreadyExistsException concurrent) {
                // Revalidate below.
            }
        }
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                || Files.isSymbolicLink(path)) {
            throw new IOException("unsafe approval directory");
        }
    }

    private static String key(String id, String version) {
        return id + "@" + version;
    }

    private static String lines(String... fields) {
        StringBuilder out = new StringBuilder();
        for (String field : fields) out.append(field).append('\n');
        return out.toString();
    }

    private static String sha256(String text) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                text.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte value : digest) {
                hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
