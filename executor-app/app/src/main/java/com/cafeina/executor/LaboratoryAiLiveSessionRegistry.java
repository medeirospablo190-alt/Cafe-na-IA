package com.cafeina.executor;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Host-only in-memory registry for AI sessions that are alive in this process.
 *
 * The future AI receives only AiHandle; this registry stores HostHandle
 * references for user/host UI control. Nothing is persisted here. If the
 * process dies, recovery is handled by LaboratoryAiSessionRecovery instead.
 */
final class LaboratoryAiLiveSessionRegistry {
    static final class Info {
        final String sessionId;
        final String projectId;
        final List<String> allowedToolIds;
        final LaboratoryAiSessionController.Snapshot snapshot;

        private Info(String sessionId, String projectId,
                List<String> allowedToolIds,
                LaboratoryAiSessionController.Snapshot snapshot) {
            this.sessionId = sessionId;
            this.projectId = projectId;
            this.allowedToolIds = Collections.unmodifiableList(
                new ArrayList<>(allowedToolIds));
            this.snapshot = snapshot;
        }
    }

    private static final class Entry {
        final String projectId;
        final List<String> allowedToolIds;
        final LaboratoryAiSessionController.HostHandle host;

        Entry(String projectId, LaboratoryAiSessionController.Policy policy,
                LaboratoryAiSessionController.HostHandle host) {
            this.projectId = projectId;
            this.allowedToolIds = Collections.unmodifiableList(
                new ArrayList<>(policy.allowedToolIds));
            this.host = host;
        }
    }

    private static final Object LOCK = new Object();
    private static final Map<String, Entry> ENTRIES = new LinkedHashMap<>();

    private LaboratoryAiLiveSessionRegistry() {}

    static void register(String projectId,
            LaboratoryAiSessionController.Policy policy,
            LaboratoryAiSessionController.HostHandle host) {
        if (projectId == null || policy == null || host == null) {
            throw new IllegalArgumentException("invalid live session registration");
        }
        synchronized (LOCK) {
            String sessionId = host.sessionId();
            if (ENTRIES.containsKey(sessionId)) {
                throw new IllegalStateException("live session already registered");
            }
            ENTRIES.put(sessionId, new Entry(projectId, policy, host));
        }
    }

    static void unregister(String sessionId) {
        if (sessionId == null) return;
        synchronized (LOCK) {
            ENTRIES.remove(sessionId);
        }
    }

    static List<Info> list(String projectId) {
        if (projectId == null) {
            throw new IllegalArgumentException("project id missing");
        }
        synchronized (LOCK) {
            pruneTerminalLocked();
            List<Info> result = new ArrayList<>();
            for (Map.Entry<String, Entry> item : ENTRIES.entrySet()) {
                Entry entry = item.getValue();
                if (!projectId.equals(entry.projectId)) continue;
                result.add(new Info(
                    item.getKey(),
                    entry.projectId,
                    entry.allowedToolIds,
                    entry.host.snapshot()));
            }
            result.sort(Comparator.comparing(info -> info.sessionId));
            return Collections.unmodifiableList(result);
        }
    }

    static LaboratoryAiSessionController.Snapshot pause(
            String projectId, String sessionId) throws IOException {
        Entry entry = require(projectId, sessionId);
        entry.host.pause();
        LaboratoryAiSessionController.Snapshot snapshot = entry.host.snapshot();
        if (snapshot.state != LaboratoryAiSessionController.State.PAUSED) {
            unregister(sessionId);
            throw new IOException(
                "AI session could not enter PAUSED state");
        }
        return snapshot;
    }

    static LaboratoryAiSessionController.Snapshot resume(
            String projectId, String sessionId) throws IOException {
        Entry entry = require(projectId, sessionId);
        entry.host.resume();
        LaboratoryAiSessionController.Snapshot snapshot = entry.host.snapshot();
        if (snapshot.state != LaboratoryAiSessionController.State.ACTIVE) {
            unregister(sessionId);
            throw new IOException(
                "AI session could not return to ACTIVE state");
        }
        return snapshot;
    }

    static void cancel(String projectId, String sessionId) throws IOException {
        Entry entry = require(projectId, sessionId);
        entry.host.cancel();
        unregister(sessionId);
    }

    static BulkResult pauseAll(String projectId) {
        return bulk(projectId, true, false);
    }

    static BulkResult resumeAll(String projectId) {
        return bulk(projectId, false, false);
    }

    static BulkResult cancelAll(String projectId) {
        return bulk(projectId, false, true);
    }

    static final class BulkResult {
        final int attempted;
        final int changed;
        final List<String> failures;

        BulkResult(int attempted, int changed, List<String> failures) {
            this.attempted = attempted;
            this.changed = changed;
            this.failures = Collections.unmodifiableList(
                new ArrayList<>(failures));
        }

        boolean complete() {
            return failures.isEmpty();
        }
    }

    private static BulkResult bulk(String projectId,
            boolean pause, boolean cancel) {
        List<Info> current = list(projectId);
        int attempted = 0;
        int changed = 0;
        List<String> failures = new ArrayList<>();
        for (Info info : current) {
            LaboratoryAiSessionController.State state = info.snapshot.state;
            boolean eligible = cancel
                || (pause && state == LaboratoryAiSessionController.State.ACTIVE)
                || (!pause && !cancel
                    && state == LaboratoryAiSessionController.State.PAUSED);
            if (!eligible) continue;
            attempted++;
            try {
                if (cancel) {
                    cancel(projectId, info.sessionId);
                } else if (pause) {
                    pause(projectId, info.sessionId);
                } else {
                    resume(projectId, info.sessionId);
                }
                changed++;
            } catch (Exception error) {
                failures.add(info.sessionId + ": "
                    + (error.getMessage() == null
                        ? error.getClass().getSimpleName()
                        : error.getMessage()));
            }
        }
        return new BulkResult(attempted, changed, failures);
    }

    private static Entry require(String projectId, String sessionId)
            throws IOException {
        if (projectId == null || sessionId == null) {
            throw new IllegalArgumentException("project or session id missing");
        }
        synchronized (LOCK) {
            pruneTerminalLocked();
            Entry entry = ENTRIES.get(sessionId);
            if (entry == null || !projectId.equals(entry.projectId)) {
                throw new IOException("live AI session is not available in this project");
            }
            return entry;
        }
    }

    private static void pruneTerminalLocked() {
        List<String> remove = new ArrayList<>();
        for (Map.Entry<String, Entry> item : ENTRIES.entrySet()) {
            LaboratoryAiSessionController.State state =
                item.getValue().host.snapshot().state;
            if (state == LaboratoryAiSessionController.State.CANCELLED
                    || state == LaboratoryAiSessionController.State.FINISHED) {
                remove.add(item.getKey());
            }
        }
        for (String sessionId : remove) ENTRIES.remove(sessionId);
    }
}
