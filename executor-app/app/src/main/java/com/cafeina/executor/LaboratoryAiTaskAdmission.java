package com.cafeina.executor;

import android.content.Context;
import android.os.Looper;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Host-side admission boundary for immutable task contracts.
 *
 * The future AI receives AiTaskHandle: exact locked goal + the narrow AiHandle.
 * HostHandle remains separate and never becomes part of the model surface.
 */
public final class LaboratoryAiTaskAdmission {
    public static final class TaskHandles {
        public final AiTaskHandle ai;
        public final LaboratoryAiSessionController.HostHandle host;

        private TaskHandles(AiTaskHandle ai,
                LaboratoryAiSessionController.HostHandle host) {
            this.ai = ai;
            this.host = host;
        }
    }

    public static final class AiTaskHandle {
        private final LaboratoryAiTaskContractStore.Contract contract;
        private final LaboratoryAiSessionController.AiHandle tools;

        private AiTaskHandle(LaboratoryAiTaskContractStore.Contract contract,
                LaboratoryAiSessionController.AiHandle tools) {
            this.contract = contract;
            this.tools = tools;
        }

        public String contractId() { return contract.contractId; }

        public LaboratoryAiTaskContractStore.Mode mode() { return contract.mode; }

        public String goal() { return contract.goalText; }

        public String goalSha256() { return contract.goalSha256; }

        public String sessionId() { return tools.sessionId(); }

        public List<LaboratoryAiToolController.Tool> listAvailable()
                throws IOException {
            return tools.listAvailable();
        }

        public LaboratorySandboxClient.Session execute(
                String toolId, String toolInput,
                LaboratoryAiSessionController.Completion completion)
                throws IOException {
            return tools.execute(toolId, toolInput, completion);
        }
    }

    private LaboratoryAiTaskAdmission() {}

    /**
     * Host-only contract creation. All listed tools must already be granted to
     * the AI at creation time. Admission revalidates this later.
     */
    public static LaboratoryAiTaskContractStore.Contract createContract(
            Context context, String projectId,
            LaboratoryAiTaskContractStore.Mode mode,
            String goalText,
            LaboratoryAiSessionController.Policy policy) throws IOException {
        if (context == null || policy == null) {
            throw new IllegalArgumentException("task context or policy missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "AI task contract creation must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        Set<String> granted = new HashSet<>();
        for (LaboratoryAiToolController.Tool tool :
                LaboratoryAiToolController.listAvailable(app, projectId)) {
            granted.add(tool.toolId);
        }
        if (!granted.containsAll(policy.allowedToolIds)) {
            throw new SecurityException(
                "task contract includes a tool not explicitly granted to the AI");
        }

        return new LaboratoryAiTaskContractStore(
            app.getFilesDir(), projectId).create(mode, goalText, policy);
    }

    /**
     * One-use admission. Claim is written before session creation. If anything
     * fails after claim, the old contract cannot be replayed; the host must
     * create a new contract.
     */
    public static TaskHandles admit(
            Context context, String projectId, String contractId)
            throws IOException {
        if (context == null) {
            throw new IllegalArgumentException("task context missing");
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                "AI task admission must run off the UI thread");
        }

        Context app = context.getApplicationContext();
        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(app.getFilesDir(), projectId);
        LaboratoryAiTaskContractStore.Contract contract = store.read(contractId);
        LaboratoryAiTaskContractStore.Claim claim = store.claim(contractId);

        LaboratoryAiSessionController.Handles session;
        try {
            session = LaboratoryAiSessionController.create(
                app, projectId, contract.policy());
        } catch (IOException | RuntimeException creationFailure) {
            recordFailureBestEffort(
                store, contractId, claim.claimId, creationFailure);
            throw creationFailure;
        }

        try {
            store.recordResult(
                contractId,
                claim.claimId,
                "SESSION_CREATED",
                session.host.sessionId(),
                "");
        } catch (IOException resultFailure) {
            session.host.cancel();
            throw new IOException(
                "task session created but admission result could not be persisted; "
                    + "session was cancelled",
                resultFailure);
        }

        return new TaskHandles(
            new AiTaskHandle(contract, session.ai),
            session.host);
    }

    private static void recordFailureBestEffort(
            LaboratoryAiTaskContractStore store,
            String contractId, String claimId, Throwable failure) {
        String reason = failure == null
            ? "UNKNOWN_FAILURE"
            : failure.getClass().getSimpleName();
        if (reason.length() > 256) reason = reason.substring(0, 256);
        try {
            store.recordResult(
                contractId, claimId, "SESSION_FAILED", "", reason);
        } catch (Exception auditFailure) {
            if (failure != null) failure.addSuppressed(auditFailure);
        }
    }
}
