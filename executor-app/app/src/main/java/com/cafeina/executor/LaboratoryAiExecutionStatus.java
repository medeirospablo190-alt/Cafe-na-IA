package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
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

        public final int promptTokens;
        public final int promptTokensProcessed;
        public final int generatedTokens;
        public final int maxGeneratedTokens;
        public final long contextSetupMs;
        public final long promptEvalMs;
        public final long tokenGenerationMs;
        public final long generationTimeLimitMs;
        public final long estimatedRemainingMs;

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
                String terminalReason,
                int promptTokens,
                int promptTokensProcessed,
                int generatedTokens,
                int maxGeneratedTokens,
                long contextSetupMs,
                long promptEvalMs,
                long tokenGenerationMs,
                long generationTimeLimitMs,
                long estimatedRemainingMs) {
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
            this.promptTokens = promptTokens;
            this.promptTokensProcessed = promptTokensProcessed;
            this.generatedTokens = generatedTokens;
            this.maxGeneratedTokens = maxGeneratedTokens;
            this.contextSetupMs = contextSetupMs;
            this.promptEvalMs = promptEvalMs;
            this.tokenGenerationMs = tokenGenerationMs;
            this.generationTimeLimitMs = generationTimeLimitMs;
            this.estimatedRemainingMs = estimatedRemainingMs;
        }

        public boolean terminal() {
            return state != State.RUNNING;
        }

        public double promptTokensPerSecond() {
            if (promptTokensProcessed <= 0 || promptEvalMs <= 0L) return 0.0;
            return promptTokensProcessed * 1000.0 / promptEvalMs;
        }

        public double generatedTokensPerSecond() {
            if (generatedTokens <= 0 || tokenGenerationMs <= 0L) return 0.0;
            return generatedTokens * 1000.0 / tokenGenerationMs;
        }
    }

    public interface Listener {
        void onStatusChanged(Snapshot snapshot);
    }

    public static final class Tracker {
        private static final int MAX_DETAIL_CHARS = 240;
        private static final int MAX_HISTORY_EVENTS = 64;

        private final String executionId = UUID.randomUUID().toString();
        private final String contractId;
        private final long startedAtEpochMs = System.currentTimeMillis();
        private final Listener listener;
        private final List<Snapshot> history = new ArrayList<>();

        private int promptTokens;
        private int promptTokensProcessed;
        private int generatedTokens;
        private int maxGeneratedTokens;
        private long contextSetupMs;
        private long promptEvalMs;
        private long tokenGenerationMs;
        private long generationTimeLimitMs;
        private long estimatedRemainingMs;

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
            remember(current);
            publish(current);
        }

        public synchronized Snapshot snapshot() {
            return current;
        }

        public synchronized List<Snapshot> history() {
            return Collections.unmodifiableList(
                new ArrayList<>(history));
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
                estimatedRemainingMs = estimateRemainingMs(phase);
                current = build(
                    State.RUNNING,
                    phase,
                    safe(detail),
                    attempt,
                    maxAttempts,
                    "");
                remember(current);
                changed = current;
            }
            publish(changed);
        }

        public void updateNativePhase(
                int nativePhase,
                int attempt,
                int maxAttempts) {
            Phase mapped = mapNativePhase(nativePhase);
            if (mapped == null) return;
            update(
                mapped,
                nativeDetail(mapped),
                attempt,
                maxAttempts);
        }

        /**
         * Updates live performance counters without adding a new persisted
         * timeline event on every poll. Phase transitions and terminal states
         * remain in history; the current snapshot carries the freshest metrics.
         */
        public void updateNativeTelemetry(
                int nativePhase,
                int promptTokens,
                int promptTokensProcessed,
                int generatedTokens,
                int maxGeneratedTokens,
                long contextSetupMs,
                long promptEvalMs,
                long tokenGenerationMs,
                long generationTimeLimitMs,
                int attempt,
                int maxAttempts) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                validateAttempt(attempt, maxAttempts);
                validateTelemetry(
                    promptTokens,
                    promptTokensProcessed,
                    generatedTokens,
                    maxGeneratedTokens,
                    contextSetupMs,
                    promptEvalMs,
                    tokenGenerationMs,
                    generationTimeLimitMs);

                this.promptTokens = promptTokens;
                this.promptTokensProcessed = promptTokensProcessed;
                this.generatedTokens = generatedTokens;
                this.maxGeneratedTokens = maxGeneratedTokens;
                this.contextSetupMs = contextSetupMs;
                this.promptEvalMs = promptEvalMs;
                this.tokenGenerationMs = tokenGenerationMs;
                this.generationTimeLimitMs = generationTimeLimitMs;

                Phase mapped = mapNativePhase(nativePhase);
                Phase nextPhase = mapped == null ? current.phase : mapped;
                String nextDetail = mapped == null
                    ? current.detail
                    : nativeDetail(mapped);
                int nextAttempt = attempt > 0 ? attempt : current.attempt;
                int nextMaxAttempts =
                    maxAttempts > 0 ? maxAttempts : current.maxAttempts;

                estimatedRemainingMs = estimateRemainingMs(nextPhase);
                current = build(
                    State.RUNNING,
                    nextPhase,
                    nextDetail,
                    nextAttempt,
                    nextMaxAttempts,
                    "");
                changed = current;
            }
            publish(changed);
        }

        public void complete(String detail, int attempt, int maxAttempts) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                validateAttempt(attempt, maxAttempts);
                estimatedRemainingMs = 0L;
                current = build(
                    State.COMPLETED,
                    Phase.COMPLETED,
                    safe(detail),
                    attempt,
                    maxAttempts,
                    "");
                remember(current);
                changed = current;
            }
            publish(changed);
        }

        public void fail(String reason) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                estimatedRemainingMs = 0L;
                current = build(
                    State.FAILED,
                    current.phase,
                    current.detail,
                    current.attempt,
                    current.maxAttempts,
                    safe(reason));
                remember(current);
                changed = current;
            }
            publish(changed);
        }

        public void cancel(String reason) {
            Snapshot changed;
            synchronized (this) {
                if (current.terminal()) return;
                estimatedRemainingMs = 0L;
                current = build(
                    State.CANCELLED,
                    current.phase,
                    current.detail,
                    current.attempt,
                    current.maxAttempts,
                    safe(reason));
                remember(current);
                changed = current;
            }
            publish(changed);
        }

        private void remember(Snapshot snapshot) {
            if (snapshot == null) return;
            if (history.size() < MAX_HISTORY_EVENTS) {
                history.add(snapshot);
                return;
            }
            if (snapshot.terminal() && !history.isEmpty()) {
                history.set(history.size() - 1, snapshot);
            }
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
                terminalReason,
                promptTokens,
                promptTokensProcessed,
                generatedTokens,
                maxGeneratedTokens,
                contextSetupMs,
                promptEvalMs,
                tokenGenerationMs,
                generationTimeLimitMs,
                estimatedRemainingMs);
        }

        private long estimateRemainingMs(Phase phase) {
            if (phase == Phase.MODEL_PROMPT
                    && promptTokens > 0
                    && promptTokensProcessed > 0
                    && promptTokensProcessed < promptTokens
                    && promptEvalMs > 0L) {
                long remaining = promptTokens - promptTokensProcessed;
                return boundedEstimate(
                    promptEvalMs,
                    remaining,
                    promptTokensProcessed);
            }

            if (phase == Phase.MODEL_TOKENS
                    && maxGeneratedTokens > 0
                    && generatedTokens > 0
                    && generatedTokens < maxGeneratedTokens
                    && tokenGenerationMs > 0L) {
                long remaining =
                    maxGeneratedTokens - generatedTokens;
                return boundedEstimate(
                    tokenGenerationMs,
                    remaining,
                    generatedTokens);
            }
            return 0L;
        }

        private long boundedEstimate(
                long elapsed,
                long remainingUnits,
                long completedUnits) {
            if (elapsed <= 0L
                    || remainingUnits <= 0L
                    || completedUnits <= 0L) {
                return 0L;
            }
            double value =
                elapsed * (double) remainingUnits / completedUnits;
            long estimate = value >= Long.MAX_VALUE
                ? Long.MAX_VALUE
                : Math.max(0L, Math.round(value));
            if (generationTimeLimitMs > 0L) {
                estimate = Math.min(
                    estimate,
                    generationTimeLimitMs);
            }
            return estimate;
        }

        private void publish(Snapshot snapshot) {
            if (listener == null || snapshot == null) return;
            try {
                listener.onStatusChanged(snapshot);
            } catch (RuntimeException ignored) {
                // Status UI must never control planner execution.
            }
        }

        private static Phase mapNativePhase(int nativePhase) {
            switch (nativePhase) {
                case 1:
                    return Phase.MODEL_CONTEXT;
                case 2:
                    return Phase.MODEL_PROMPT;
                case 3:
                    return Phase.MODEL_TOKENS;
                default:
                    return null;
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

        private static void validateTelemetry(
                int promptTokens,
                int promptTokensProcessed,
                int generatedTokens,
                int maxGeneratedTokens,
                long contextSetupMs,
                long promptEvalMs,
                long tokenGenerationMs,
                long generationTimeLimitMs) {
            if (promptTokens < 0
                    || promptTokensProcessed < 0
                    || promptTokensProcessed > promptTokens
                    || generatedTokens < 0
                    || maxGeneratedTokens < 0
                    || generatedTokens > maxGeneratedTokens
                    || contextSetupMs < 0L
                    || promptEvalMs < 0L
                    || tokenGenerationMs < 0L
                    || generationTimeLimitMs < 0L) {
                throw new IllegalArgumentException(
                    "invalid execution telemetry");
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
