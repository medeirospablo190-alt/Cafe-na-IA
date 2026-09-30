package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Narrow capability surface intended for the future AI orchestrator.
 *
 * Exposed operations are deliberately limited to:
 *  1) list STABLE tools explicitly granted by the user;
 *  2) execute one granted tool with bounded tool_input.
 *
 * No registry mutation, approval, rollback, permission mutation, snapshot
 * access or source-code selection is available through this controller.
 */
public final class LaboratoryAiToolController {
    public interface Completion {
        void onFinished(Execution success, IOException failure);
    }

    public static final class Tool {
        public final String toolId;
        public final String version;
        public final List<String> capabilities;
        public final int maxRuntimeMs;
        public final int maxInputBytes;

        private Tool(LaboratoryToolRegistry.Descriptor descriptor) {
            this.toolId = descriptor.toolId;
            this.version = descriptor.version;
            this.capabilities = Collections.unmodifiableList(
                new ArrayList<>(descriptor.capabilities));
            this.maxRuntimeMs = descriptor.maxRuntimeMs;
            this.maxInputBytes = descriptor.maxInputBytes;
        }
    }

    public static final class Execution {
        public final String toolId;
        public final String toolVersion;
        public final String runId;
        public final String output;
        public final String firstReturn;
        public final long durationMs;

        private Execution(LaboratoryStableToolExecutor.Execution stable) {
            this.toolId = stable.toolId;
            this.toolVersion = stable.toolVersion;
            this.runId = stable.runId;
            this.output = stable.output;
            this.firstReturn = stable.firstReturn;
            this.durationMs = stable.durationMs;
        }
    }

    private static final ExecutorService VERIFY_IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private LaboratoryAiToolController() {}

    public static List<Tool> listAvailable(
            Context context, String projectId) throws IOException {
        if (context == null) throw new IllegalArgumentException("context missing");
        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(context.getFilesDir(), projectId);
        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(context.getFilesDir(), projectId);

        List<Tool> result = new ArrayList<>();
        for (LaboratoryAiPermissionStore.Grant grant : permissions.listActiveGrants()) {
            LaboratoryToolRegistry.Descriptor active =
                registry.activeStable(grant.toolId);
            if (active == null
                    || !grant.version.equals(active.version)
                    || !grant.artifactSha256.equals(active.artifactSha256)) {
                continue;
            }
            result.add(new Tool(active));
        }
        result.sort(Comparator.comparing(tool -> tool.toolId));
        return Collections.unmodifiableList(result);
    }

    /**
     * Must be invoked from a host-owned background thread.
     */
    public static LaboratorySandboxClient.Session executeInternal(
            Context context, String projectId, String toolId, String toolInput,
            Completion completion) throws IOException {
        if (context == null) throw new IllegalArgumentException("context missing");
        if (completion == null) throw new IllegalArgumentException("completion missing");
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "AI tool permission preflight must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(app.getFilesDir(), projectId);
        LaboratoryAiPermissionStore.Grant before = permissions.activeGrant(toolId);
        if (before == null) {
            throw new SecurityException(
                "tool is not explicitly granted to the AI for the active STABLE version");
        }

        return LaboratoryStableToolExecutor.executeInternal(
            app, projectId, toolId, toolInput, (stable, stableFailure) -> {
                if (stableFailure != null) {
                    completion.onFinished(null, stableFailure);
                    return;
                }
                VERIFY_IO.execute(() -> {
                    IOException failure = null;
                    try {
                        LaboratoryAiPermissionStore.Grant after =
                            new LaboratoryAiPermissionStore(
                                app.getFilesDir(), projectId).activeGrant(toolId);
                        if (after == null
                                || !before.eventId.equals(after.eventId)
                                || before.sequence != after.sequence
                                || !before.version.equals(after.version)
                                || !before.descriptorSha256.equals(
                                    after.descriptorSha256)
                                || !before.artifactSha256.equals(
                                    after.artifactSha256)
                                || !before.snapshotId.equals(after.snapshotId)) {
                            failure = new IOException(
                                "AI tool permission was revoked or changed during execution");
                        }
                    } catch (IOException invalidPermission) {
                        failure = new IOException(
                            "AI tool permission could not be revalidated",
                            invalidPermission);
                    }

                    final IOException deliveredFailure = failure;
                    MAIN.post(() -> {
                        if (deliveredFailure != null) {
                            completion.onFinished(null, deliveredFailure);
                        } else {
                            completion.onFinished(new Execution(stable), null);
                        }
                    });
                });
            });
    }
}
