package com.cafeina.executor;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Bounded AI work session with split host/AI handles.
 *
 * The AI handle can only list and execute tools already granted through
 * LaboratoryAiPermissionStore. The host handle alone can pause, resume, cancel
 * and inspect session state. No handle can mutate STABLE lifecycle or human
 * approvals.
 */
public final class LaboratoryAiSessionController {
    public enum State { ACTIVE, PAUSED, CANCELLED, FINISHED }

    public static final class Policy {
        public final List<String> allowedToolIds;
        public final int maxInvocations;
        public final int maxTotalInputBytes;
        public final long maxSessionMs;

        public Policy(List<String> allowedToolIds, int maxInvocations,
                int maxTotalInputBytes, long maxSessionMs) {
            if (allowedToolIds == null || allowedToolIds.isEmpty()
                    || allowedToolIds.size() > 32) {
                throw new IllegalArgumentException("invalid session tool allowlist");
            }
            List<String> copy = new ArrayList<>();
            for (String toolId : allowedToolIds) {
                if (toolId == null
                        || !toolId.matches("[a-z0-9][a-z0-9._-]{0,63}")
                        || copy.contains(toolId)) {
                    throw new IllegalArgumentException("invalid session tool id");
                }
                copy.add(toolId);
            }
            if (maxInvocations < 1 || maxInvocations > 64) {
                throw new IllegalArgumentException("invalid session invocation budget");
            }
            if (maxTotalInputBytes < 1 || maxTotalInputBytes > 256 * 1024) {
                throw new IllegalArgumentException("invalid session input budget");
            }
            if (maxSessionMs < 1_000L || maxSessionMs > 60L * 60L * 1000L) {
                throw new IllegalArgumentException("invalid session time budget");
            }
            this.allowedToolIds = Collections.unmodifiableList(copy);
            this.maxInvocations = maxInvocations;
            this.maxTotalInputBytes = maxTotalInputBytes;
            this.maxSessionMs = maxSessionMs;
        }
    }

    public static final class Snapshot {
        public final String sessionId;
        public final State state;
        public final int invocationsUsed;
        public final int invocationsRemaining;
        public final int inputBytesUsed;
        public final int inputBytesRemaining;
        public final long elapsedMs;
        public final long remainingMs;
        public final boolean hasActiveInvocation;

        private Snapshot(String sessionId, State state, int invocationsUsed,
                int maxInvocations, int inputBytesUsed, int maxInputBytes,
                long elapsedMs, long maxSessionMs, boolean active) {
            this.sessionId = sessionId;
            this.state = state;
            this.invocationsUsed = invocationsUsed;
            this.invocationsRemaining = Math.max(0, maxInvocations - invocationsUsed);
            this.inputBytesUsed = inputBytesUsed;
            this.inputBytesRemaining = Math.max(0, maxInputBytes - inputBytesUsed);
            this.elapsedMs = elapsedMs;
            this.remainingMs = Math.max(0L, maxSessionMs - elapsedMs);
            this.hasActiveInvocation = active;
        }
    }

    public interface Completion {
        void onFinished(LaboratoryAiToolController.Execution success,
            IOException failure);
    }

    public static final class Handles {
        public final AiHandle ai;
        public final HostHandle host;

        private Handles(AiHandle ai, HostHandle host) {
            this.ai = ai;
            this.host = host;
        }
    }

    public static final class AiHandle {
        private final Session session;

        private AiHandle(Session session) { this.session = session; }

        public List<LaboratoryAiToolController.Tool> listAvailable() throws IOException {
            return session.listForAi();
        }

        public LaboratorySandboxClient.Session execute(String toolId, String toolInput,
                Completion completion) throws IOException {
            return session.executeForAi(toolId, toolInput, completion);
        }

        public String sessionId() { return session.id; }
    }

    public static final class HostHandle {
        private final Session session;

        private HostHandle(Session session) { this.session = session; }

        public void pause() { session.pauseFromHost(); }

        public void resume() throws IOException { session.resumeFromHost(); }

        public void cancel() { session.cancelFromHost(); }

        public void complete() throws IOException { session.completeFromHost(); }

        public Snapshot snapshot() { return session.snapshot(); }

        public String sessionId() { return session.id; }
    }

    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final Set<String> LIVE_SESSION_IDS =
        Collections.synchronizedSet(new HashSet<>());

    private LaboratoryAiSessionController() {}

    static boolean isLiveSession(String sessionId) {
        return sessionId != null && LIVE_SESSION_IDS.contains(sessionId);
    }

    /**
     * Creates a session only if every tool in the task allowlist is currently
     * granted to the AI. The allowlist is frozen for the lifetime of the
     * session; permission revocation still takes effect immediately.
     */
    public static Handles create(Context context, String projectId, Policy policy)
            throws IOException {
        if (context == null || policy == null) {
            throw new IllegalArgumentException("session context or policy missing");
        }
        Context app = context.getApplicationContext();
        List<LaboratoryAiToolController.Tool> available =
            LaboratoryAiToolController.listAvailable(app, projectId);
        Set<String> granted = new HashSet<>();
        for (LaboratoryAiToolController.Tool tool : available) {
            granted.add(tool.toolId);
        }
        if (!granted.containsAll(policy.allowedToolIds)) {
            throw new SecurityException(
                "session allowlist includes a tool not granted to the AI");
        }

        Session session = new Session(app, projectId, policy);
        Handles handles = new Handles(new AiHandle(session), new HostHandle(session));
        try {
            LaboratoryAiLiveSessionRegistry.register(projectId, policy, handles.host);
        } catch (RuntimeException registrationFailure) {
            session.cancelFromHost();
            throw registrationFailure;
        }
        return handles;
    }

    private static final class Session {
        final Context app;
        final String projectId;
        final Policy policy;
        final String id = UUID.randomUUID().toString();
        final long startedAt = System.currentTimeMillis();
        final Runnable expireTask;
        final LaboratoryAiSessionStore audit;

        State state = State.ACTIVE;
        int invocationsUsed;
        int inputBytesUsed;
        boolean auditBroken;
        boolean terminalAudited;
        LaboratorySandboxClient.Session activeInvocation;

        Session(Context app, String projectId, Policy policy) throws IOException {
            this.app = app;
            this.projectId = projectId;
            this.policy = policy;
            this.audit = new LaboratoryAiSessionStore(app.getFilesDir(), projectId);
            LIVE_SESSION_IDS.add(id);
            try {
                this.audit.begin(id, startedAt, policy.allowedToolIds,
                    policy.maxInvocations, policy.maxTotalInputBytes,
                    policy.maxSessionMs);
            } catch (IOException creationFailure) {
                LIVE_SESSION_IDS.remove(id);
                throw creationFailure;
            }
            this.expireTask = this::expire;
            MAIN.postDelayed(expireTask, policy.maxSessionMs);
        }

        synchronized List<LaboratoryAiToolController.Tool> listForAi()
                throws IOException {
            updateExpiredLocked();
            if (state == State.CANCELLED || state == State.FINISHED) {
                return Collections.emptyList();
            }
            List<LaboratoryAiToolController.Tool> available =
                LaboratoryAiToolController.listAvailable(app, projectId);
            List<LaboratoryAiToolController.Tool> filtered = new ArrayList<>();
            for (LaboratoryAiToolController.Tool tool : available) {
                if (policy.allowedToolIds.contains(tool.toolId)) {
                    filtered.add(tool);
                }
            }
            return Collections.unmodifiableList(filtered);
        }

        LaboratorySandboxClient.Session executeForAi(String toolId, String toolInput,
                Completion completion) throws IOException {
            if (completion == null) {
                throw new IllegalArgumentException("session completion missing");
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                throw new IllegalStateException(
                    "AI session execution preflight must run off the UI thread");
            }

            final int inputBytes;
            final String inputSha256;
            synchronized (this) {
                updateExpiredLocked();
                if (state == State.PAUSED) throw new IOException("AI session is paused");
                if (state == State.CANCELLED) throw new IOException("AI session is cancelled");
                if (state == State.FINISHED) throw new IOException("AI session is finished");
                if (activeInvocation != null) {
                    throw new IOException("AI session already has an active invocation");
                }
                if (!policy.allowedToolIds.contains(toolId)) {
                    throw new SecurityException("tool is outside this session allowlist");
                }
                if (toolInput == null) {
                    throw new IllegalArgumentException("tool input missing");
                }
                inputBytes = toolInput.getBytes(StandardCharsets.UTF_8).length;
                if (invocationsUsed >= policy.maxInvocations) {
                    finishLocked("INVOCATION_BUDGET_EXHAUSTED");
                    throw new IOException("AI session invocation budget exhausted");
                }
                if (inputBytesUsed + inputBytes > policy.maxTotalInputBytes) {
                    throw new IOException("AI session input budget exceeded");
                }

                // Reserve budget before invoking the external controller. Failed
                // attempts still consume budget and cannot be retried for free.
                invocationsUsed++;
                inputBytesUsed += inputBytes;
                inputSha256 =
                    LaboratoryEngine.fingerprint(toolInput).substring(7, 71);
                try {
                    audit.append(id, LaboratoryAiSessionStore.INVOKE_REQUEST,
                        state.name(), toolId, inputSha256, inputBytes, "",
                        "REQUESTED", invocationsUsed, inputBytesUsed);
                } catch (IOException auditFailure) {
                    failAuditLocked();
                    throw new IOException(
                        "AI session audit failed before invocation", auditFailure);
                }
            }

            final AtomicBoolean completed = new AtomicBoolean(false);
            final LaboratorySandboxClient.Session launched;
            try {
                launched = LaboratoryAiToolController.executeInternal(
                    app, projectId, toolId, toolInput, (success, failure) -> {
                        completed.set(true);
                        synchronized (Session.this) {
                            activeInvocation = null;
                            updateExpiredLocked();
                            if (state == State.CANCELLED) {
                                failure = new IOException("AI session was cancelled");
                                success = null;
                            } else if (state == State.PAUSED) {
                                failure = new IOException(
                                    "AI session was paused during invocation");
                                success = null;
                            } else if (invocationsUsed >= policy.maxInvocations
                                    || inputBytesUsed >= policy.maxTotalInputBytes
                                    || elapsedLocked() >= policy.maxSessionMs) {
                                finishLocked("BUDGET_OR_TIME_EXHAUSTED");
                            }

                            String runId = success == null ? "" : success.runId;
                            String outcome = failure == null ? "PASS"
                                : state == State.CANCELLED ? "CANCELLED"
                                : state == State.PAUSED ? "PAUSED"
                                : "FAIL";
                            try {
                                audit.append(id, LaboratoryAiSessionStore.INVOKE_RESULT,
                                    state.name(), toolId, inputSha256, inputBytes,
                                    runId, outcome, invocationsUsed, inputBytesUsed);
                                LaboratoryAiDiagnostics.schedule(app, projectId, id);
                            } catch (IOException auditFailure) {
                                failAuditLocked();
                                failure = new IOException(
                                    "AI session result audit failed", auditFailure);
                                success = null;
                            }
                        }
                        completion.onFinished(success, failure);
                    });
            } catch (IOException | RuntimeException launchFailure) {
                synchronized (this) {
                    activeInvocation = null;
                    updateExpiredLocked();
                    try {
                        audit.append(id, LaboratoryAiSessionStore.INVOKE_RESULT,
                            state.name(), toolId, inputSha256, inputBytes, "",
                            "LAUNCH_FAILED", invocationsUsed, inputBytesUsed);
                        LaboratoryAiDiagnostics.schedule(app, projectId, id);
                    } catch (IOException auditFailure) {
                        failAuditLocked();
                        launchFailure.addSuppressed(auditFailure);
                    }
                    if (invocationsUsed >= policy.maxInvocations
                            || elapsedLocked() >= policy.maxSessionMs) {
                        finishLocked("BUDGET_OR_TIME_EXHAUSTED");
                    }
                }
                throw launchFailure;
            }

            synchronized (this) {
                if (completed.get()) {
                    activeInvocation = null;
                } else if (state == State.CANCELLED || state == State.PAUSED
                        || state == State.FINISHED) {
                    launched.cancel();
                } else {
                    activeInvocation = launched;
                }
            }
            return launched;
        }

        synchronized void pauseFromHost() {
            updateExpiredLocked();
            if (state == State.CANCELLED || state == State.FINISHED) return;
            state = State.PAUSED;
            try {
                audit.append(id, LaboratoryAiSessionStore.PAUSE, state.name(),
                    "", "", 0, "", "HOST_PAUSE", invocationsUsed, inputBytesUsed);
            } catch (IOException auditFailure) {
                failAuditLocked();
            }
            if (activeInvocation != null) activeInvocation.cancel();
        }

        synchronized void resumeFromHost() throws IOException {
            updateExpiredLocked();
            if (auditBroken) throw new IOException("AI session audit is unavailable");
            if (state == State.CANCELLED) throw new IOException("AI session is cancelled");
            if (state == State.FINISHED) throw new IOException("AI session is finished");
            if (state == State.ACTIVE) return;
            if (invocationsUsed >= policy.maxInvocations
                    || inputBytesUsed >= policy.maxTotalInputBytes
                    || elapsedLocked() >= policy.maxSessionMs) {
                finishLocked("BUDGET_OR_TIME_EXHAUSTED");
                throw new IOException("AI session budget is exhausted");
            }
            state = State.ACTIVE;
            try {
                audit.append(id, LaboratoryAiSessionStore.RESUME, state.name(),
                    "", "", 0, "", "HOST_RESUME", invocationsUsed, inputBytesUsed);
            } catch (IOException auditFailure) {
                failAuditLocked();
                throw new IOException("AI session audit failed on resume", auditFailure);
            }
        }

        synchronized void completeFromHost() throws IOException {
            updateExpiredLocked();
            if (auditBroken) {
                throw new IOException("AI session audit is unavailable");
            }
            if (state == State.CANCELLED) {
                throw new IOException("AI session is cancelled");
            }
            if (state == State.FINISHED) return;
            if (activeInvocation != null) {
                throw new IOException(
                    "AI session cannot complete while a tool invocation is active");
            }
            finishLocked("HOST_COMPLETED");
            if (auditBroken || !terminalAudited) {
                throw new IOException(
                    "AI session finished but completion audit failed");
            }
        }

        synchronized void cancelFromHost() {
            if (state == State.CANCELLED || state == State.FINISHED) return;
            state = State.CANCELLED;
            LIVE_SESSION_IDS.remove(id);
            MAIN.removeCallbacks(expireTask);
            if (activeInvocation != null) activeInvocation.cancel();
            try {
                audit.append(id, LaboratoryAiSessionStore.CANCEL, state.name(),
                    "", "", 0, "", "HOST_CANCEL", invocationsUsed, inputBytesUsed);
                terminalAudited = true;
                LaboratoryAiDiagnostics.schedule(app, projectId, id);
            } catch (IOException auditFailure) {
                auditBroken = true;
            }
        }

        synchronized Snapshot snapshot() {
            updateExpiredLocked();
            long elapsed = elapsedLocked();
            return new Snapshot(id, state, invocationsUsed, policy.maxInvocations,
                inputBytesUsed, policy.maxTotalInputBytes, elapsed,
                policy.maxSessionMs, activeInvocation != null);
        }

        synchronized void expire() {
            updateExpiredLocked();
        }

        private void updateExpiredLocked() {
            if ((state == State.ACTIVE || state == State.PAUSED)
                    && elapsedLocked() >= policy.maxSessionMs) {
                state = State.FINISHED;
                LIVE_SESSION_IDS.remove(id);
                MAIN.removeCallbacks(expireTask);
                if (activeInvocation != null) activeInvocation.cancel();
                auditTerminalLocked("TIME_EXPIRED");
            }
        }

        private long elapsedLocked() {
            return Math.max(0L, System.currentTimeMillis() - startedAt);
        }

        private void finishLocked(String reason) {
            if (state == State.CANCELLED || state == State.FINISHED) return;
            state = State.FINISHED;
            LIVE_SESSION_IDS.remove(id);
            MAIN.removeCallbacks(expireTask);
            auditTerminalLocked(reason);
        }

        private void auditTerminalLocked(String reason) {
            if (terminalAudited || auditBroken) return;
            try {
                audit.append(id, LaboratoryAiSessionStore.FINISH, state.name(),
                    "", "", 0, "", reason, invocationsUsed, inputBytesUsed);
                terminalAudited = true;
                LaboratoryAiDiagnostics.schedule(app, projectId, id);
            } catch (IOException auditFailure) {
                auditBroken = true;
            }
        }

        private void failAuditLocked() {
            auditBroken = true;
            if (state != State.FINISHED) state = State.CANCELLED;
            LIVE_SESSION_IDS.remove(id);
            MAIN.removeCallbacks(expireTask);
            if (activeInvocation != null) activeInvocation.cancel();
        }
    }
}
