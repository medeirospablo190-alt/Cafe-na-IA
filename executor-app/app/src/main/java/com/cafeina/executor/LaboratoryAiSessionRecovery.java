package com.cafeina.executor;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Process-recovery boundary for persisted AI sessions.
 *
 * A persisted ACTIVE/PAUSED session that is not present in the current
 * process live-session registry is marked INTERRUPTED. Recovery never resumes
 * work automatically. The user must explicitly close it or request a new
 * bounded session from the remaining budget.
 */
public final class LaboratoryAiSessionRecovery {
    private static final Object RECOVERY_LOCK = new Object();

    public static final class Item {
        public final String sessionId;
        public final String state;
        public final List<String> allowedToolIds;
        public final int invocationsUsed;
        public final int invocationsRemaining;
        public final int inputBytesUsed;
        public final int inputBytesRemaining;
        public final long remainingSessionMs;
        public final long startedAtEpochMs;
        public final long lastEventAtEpochMs;

        private Item(LaboratoryAiSessionStore.Summary summary) {
            this.sessionId = summary.sessionId;
            this.state = summary.state;
            this.allowedToolIds = Collections.unmodifiableList(
                new ArrayList<>(summary.allowedToolIds));
            this.invocationsUsed = summary.invocationsUsed;
            this.invocationsRemaining =
                Math.max(0, summary.maxInvocations - summary.invocationsUsed);
            this.inputBytesUsed = summary.inputBytesUsed;
            this.inputBytesRemaining =
                Math.max(0, summary.maxTotalInputBytes - summary.inputBytesUsed);
            long elapsedAtLastEvent = Math.max(
                0L, summary.lastEventAtEpochMs - summary.startedAtEpochMs);
            this.remainingSessionMs =
                Math.max(0L, summary.maxSessionMs - elapsedAtLastEvent);
            this.startedAtEpochMs = summary.startedAtEpochMs;
            this.lastEventAtEpochMs = summary.lastEventAtEpochMs;
        }

        public boolean canRequestRestart() {
            return invocationsRemaining > 0
                && inputBytesRemaining > 0
                && remainingSessionMs >= 1_000L;
        }

        public LaboratoryAiSessionController.Policy remainingPolicy() {
            if (!canRequestRestart()) {
                throw new IllegalStateException("interrupted session has no usable budget");
            }
            return new LaboratoryAiSessionController.Policy(
                allowedToolIds,
                invocationsRemaining,
                inputBytesRemaining,
                remainingSessionMs);
        }
    }

    private final LaboratoryAiSessionStore store;

    public LaboratoryAiSessionRecovery(File appFilesDirectory, String projectId) {
        store = new LaboratoryAiSessionStore(appFilesDirectory, projectId);
    }

    /**
     * Safe to call on application startup. Current-process sessions are
     * excluded through LaboratoryAiSessionController.isLiveSession().
     */
    public List<Item> markInterruptedOrphans() throws IOException {
        synchronized (RECOVERY_LOCK) {
            List<LaboratoryAiSessionStore.Summary> summaries = store.list();
            for (LaboratoryAiSessionStore.Summary summary : summaries) {
                if (!("ACTIVE".equals(summary.state) || "PAUSED".equals(summary.state))) {
                    continue;
                }
                if (LaboratoryAiSessionController.isLiveSession(summary.sessionId)) {
                    continue;
                }
                store.append(
                    summary.sessionId,
                    LaboratoryAiSessionStore.INTERRUPT,
                    "INTERRUPTED",
                    "",
                    "",
                    0,
                    "",
                    "PROCESS_SESSION_NOT_LIVE",
                    summary.invocationsUsed,
                    summary.inputBytesUsed);
            }
            return listActionableLocked();
        }
    }

    public List<Item> listActionable() throws IOException {
        synchronized (RECOVERY_LOCK) {
            return listActionableLocked();
        }
    }

    private List<Item> listActionableLocked() throws IOException {
        List<Item> result = new ArrayList<>();
        for (LaboratoryAiSessionStore.Summary summary : store.list()) {
            if ("INTERRUPTED".equals(summary.state)
                    || "RECOVERY_PENDING".equals(summary.state)) {
                result.add(new Item(summary));
            }
        }
        return Collections.unmodifiableList(result);
    }

    public Item readActionable(String sessionId) throws IOException {
        synchronized (RECOVERY_LOCK) {
            return readActionableLocked(sessionId);
        }
    }

    private Item readActionableLocked(String sessionId) throws IOException {
        for (Item item : listActionableLocked()) {
            if (item.sessionId.equals(sessionId)) return item;
        }
        throw new IOException("AI session is not waiting for recovery");
    }

    /**
     * Records explicit user intent to continue later as a NEW session.
     * It does not create or execute a session by itself.
     */
    public Item requestRestart(String sessionId) throws IOException {
        synchronized (RECOVERY_LOCK) {
            Item item = readActionableLocked(sessionId);
            if ("RECOVERY_PENDING".equals(item.state)) return item;
            if (!"INTERRUPTED".equals(item.state)) {
                throw new IOException("AI session is not interrupted");
            }
            if (!item.canRequestRestart()) {
                throw new IOException("interrupted session has no remaining usable budget");
            }

            store.append(
                item.sessionId,
                LaboratoryAiSessionStore.RECOVERY_REQUEST,
                "RECOVERY_PENDING",
                "",
                "",
                0,
                "",
                "USER_REQUESTED_NEW_SESSION",
                item.invocationsUsed,
                item.inputBytesUsed);
            return readActionableLocked(sessionId);
        }
    }

    /**
     * Explicitly terminates an interrupted or recovery-pending session.
     */
    public void close(String sessionId) throws IOException {
        synchronized (RECOVERY_LOCK) {
            Item item = readActionableLocked(sessionId);
            store.append(
                item.sessionId,
                LaboratoryAiSessionStore.RECOVERY_CLOSE,
                "FINISHED",
                "",
                "",
                0,
                "",
                "USER_CLOSED_INTERRUPTED_SESSION",
                item.invocationsUsed,
                item.inputBytesUsed);
        }
    }

    /**
     * Returns the policy that a future host/orchestrator may use to create a
     * NEW session after the user has explicitly requested recovery.
     */
    public LaboratoryAiSessionController.Policy pendingRestartPolicy(
            String sessionId) throws IOException {
        synchronized (RECOVERY_LOCK) {
            Item item = readActionableLocked(sessionId);
            if (!"RECOVERY_PENDING".equals(item.state)) {
                throw new IOException("session recovery has not been requested");
            }
            return item.remainingPolicy();
        }
    }
}
