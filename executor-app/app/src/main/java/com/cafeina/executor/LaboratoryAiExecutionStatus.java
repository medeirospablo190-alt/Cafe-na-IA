package com.cafeina.executor;

import java.util.UUID;

/**
 * Immutable execution status contract shared by planner UI and diagnostics.
 *
 * The tracker is host-side only. It does not grant permissions, consume a
 * Goal Lock, execute tools, or expose execution handles to the model.
 */
public final class LaboratoryAiExecutionStatus {
    public enum State {
        RUNNING,
        COMPLETED,
        FAILED,
        CANCELLED
    }

    public enum Phase {
        PREPARING,
        MODEL_ADMISSION,
        PREFLIGHT,
        MODEL_OPEN,
        RUNTIME_METADATA,
        PLANNING,
        MODEL_CONTEXT,
        MODEL_PROMPT,
        MODEL_TOKENS,
        VALIDATING,
        COMPLETED
    }

    public static final class Snapshot {
        public final String executionId;
        public final String contractId;
        public final long startedAtEpochMs;
        public final long updatedAtEpochMs;
        public final long elapsedMs;
        public final State state;
        public final Phase phase;
        public final String detail;
        public final int attempt;
        public final int maxAttempts;
        public final String terminalReason;

        private Snapshot(
                String executionId,
                String contractId,
                long startedAtEpochMs,
                long updatedAtEpochMs,
                State state,
                Phase phase,
                String detail,
                int attempt,
                int maxAttempts,
                String terminalReason) {
            this.executionId = executionId;
            this.contractId = contractId;
            this.startedAtEpochMs = startedAtEpochMs;
            this.updatedAtEpochMs = updatedAtEpochMs;
            this.elapsedMs = Math.max(0L, updatedAtEpochMs - startedAtEpochMs);
            this.state = state;
            this.phase = phase;
            this.detail = detail;
            this.attempt = attempt;
            this.maxAttempts = maxAttempts;
            this.terminalReason = terminalReason;
        }

        public boolean terminal() {
            return state != State.RUNNING;
        }
    }

    public interface Listener {
        void onStatusChanged(Snapshot snapshot);
    }

    public static final class Tracker {
        private static final int MAX_DETAIL_CHARS = 240;

        private final String executionId = UUID.randomUUID().toString();
        private final String contractId;
        private final long startedAtEpochMs = System.currentTimeMillis();
        private final Listener listener;

        private Snapshot current;

        public Tracker(String contractId, Listener listener) {
            if (contractId == null || contractId.isEmpty()) {
                throw new IllegalArgumentException(
                    "execution status contract id missing");
            }
            this.contractId = contractId;
            this.listener = listener;
            current = build(
                State.RUNNING,
                Phase.PREPARING,
                "Preparando execução do planejador",
                0,
                0,
                "");
            publish(current);
        }

        public synchronized Snapshot snapshot() {
            return current;
        }

        public void update(Phase phase, String detail) {
            update(phase, detail, 0, 0);
        }

        public void update(
                Phase phase,
                String detail,
                int attempt,
                int maxAttempts) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                if (phase == null || phase == Phase.COMPLETED) {
                    throw new IllegalArgumentException(
                        "invalid running execution phase");
                }
                validateAttempt(attempt, maxAttempts);
                current = build(
                    State.RUNNING,
                    phase,
                    safe(detail),
                    attempt,
                    maxAttempts,
                    "");
                changed = current;
            }
            publish(changed);
        }

        public void updateNativePhase(
                int nativePhase,
                int attempt,
                int maxAttempts) {
            Phase mapped;
            switch (nativePhase) {
                case 1:
                    mapped = Phase.MODEL_CONTEXT;
                    break;
                case 2:
                    mapped = Phase.MODEL_PROMPT;
                    break;
                case 3:
                    mapped = Phase.MODEL_TOKENS;
                    break;
                default:
                    return;
            }
            update(
                mapped,
                nativeDetail(mapped),
                attempt,
                maxAttempts);
        }

        public void complete(String detail, int attempt, int maxAttempts) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                validateAttempt(attempt, maxAttempts);
                current = build(
                    State.COMPLETED,
                    Phase.COMPLETED,
                    safe(detail),
                    attempt,
                    maxAttempts,
                    "");
                changed = current;
            }
            publish(changed);
        }

        public void fail(String reason) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                current = build(
                    State.FAILED,
                    current.phase,
                    current.detail,
                    current.attempt,
                    current.maxAttempts,
                    safe(reason));
                changed = current;
            }
            publish(changed);
        }

        public void cancel(String reason) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                current = build(
                    State.CANCELLED,
                    current.phase,
                    current.detail,
                    current.attempt,
                    current.maxAttempts,
                    safe(reason));
                changed = current;
            }
            publish(changed);
        }

        private Snapshot build(
                State state,
                Phase phase,
                String detail,
                int attempt,
                int maxAttempts,
                String terminalReason) {
            return new Snapshot(
                executionId,
                contractId,
                startedAtEpochMs,
                System.currentTimeMillis(),
                state,
                phase,
                detail,
                attempt,
                maxAttempts,
                terminalReason);
        }

        private void publish(Snapshot snapshot) {
            if (listener == null || snapshot == null) return;
            try {
                listener.onStatusChanged(snapshot);
            } catch (RuntimeException ignored) {
                // Status UI must never control planner execution.
            }
        }

        private static void validateAttempt(int attempt, int maxAttempts) {
            if (attempt < 0 || maxAttempts < 0
                    || attempt > maxAttempts
                    || (attempt > 0 && maxAttempts == 0)) {
                throw new IllegalArgumentException(
                    "invalid execution status attempt");
            }
        }

        private static String safe(String value) {
            if (value == null) return "";
            String trimmed = value.trim();
            if (trimmed.length() <= MAX_DETAIL_CHARS) return trimmed;
            return trimmed.substring(0, MAX_DETAIL_CHARS);
        }

        private static String nativeDetail(Phase phase) {
            switch (phase) {
                case MODEL_CONTEXT:
                    return "Preparando contexto do modelo local";
                case MODEL_PROMPT:
                    return "Processando prompt no modelo local";
                case MODEL_TOKENS:
                    return "Gerando tokens do plano";
                default:
                    return "Executando modelo local";
            }
        }
    }

    private LaboratoryAiExecutionStatus() {}
}
