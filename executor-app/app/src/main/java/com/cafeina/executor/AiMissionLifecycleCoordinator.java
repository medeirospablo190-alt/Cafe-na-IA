package com.cafeina.executor;

import java.io.IOException;

/**
 * Host-owned mission lifecycle boundary. Every transition is persisted before
 * the updated mission is returned to the caller. This class never executes effects.
 */
public final class AiMissionLifecycleCoordinator {
    public interface Clock { long now(); }
    public interface Transition { void apply(AiMission mission); }

    private final ProjectStore projects;
    private final AiMissionCheckpointRepository checkpoints;
    private final Clock clock;

    public AiMissionLifecycleCoordinator(ProjectStore projects,
            AiMissionCheckpointRepository checkpoints, Clock clock) {
        if (projects == null || checkpoints == null || clock == null) {
            throw new IllegalArgumentException("projects, checkpoints and clock are required");
        }
        this.projects = projects;
        this.checkpoints = checkpoints;
        this.clock = clock;
    }

    public synchronized AiMission create(String id, String projectId, String goal) throws IOException {
        requireProject(projectId);
        AiMission mission = new AiMission(id, projectId, goal);
        if (checkpoints.load(projectId, id) != null) {
            throw new IllegalStateException("mission already exists");
        }
        checkpoints.save(mission.snapshot(), clock.now());
        return mission;
    }

    /**
     * An interrupted RUNNING checkpoint is deliberately returned paused.
     * It is not written back until the host explicitly chooses a transition.
     */
    public synchronized AiMission restore(String projectId, String missionId) throws IOException {
        requireProject(projectId);
        AiMissionSnapshot stored = checkpoints.load(projectId, missionId);
        if (stored == null) return null;
        AiMission recovered = AiMission.restore(stored);
        if (stored.state == AiMissionState.RUNNING) {
            checkpoints.save(recovered.snapshot(), clock.now());
        }
        return recovered;
    }

    /**
     * Read the persisted state, apply one legal transition and persist it.
     * Never trust a stale in-memory mission as the authority.
     */
    public synchronized AiMission transition(AiMission mission, Transition transition) throws IOException {
        if (mission == null || transition == null) {
            throw new IllegalArgumentException("mission and transition are required");
        }
        requireProject(mission.projectId);
        AiMissionSnapshot stored = checkpoints.load(mission.projectId, mission.id);
        if (stored == null || !stored.goal.equals(mission.goal) || stored.state != mission.state()) {
            throw new IllegalStateException("mission is missing or stale; restore and reconcile first");
        }
        AiMission candidate = AiMission.restore(mission.snapshot());
        // A live RUNNING mission must not be mistaken for a process-recovery snapshot.
        if (mission.state() == AiMissionState.RUNNING) {
            candidate = mission.copyForLiveTransition();
        }
        transition.apply(candidate);
        checkpoints.save(candidate.snapshot(), clock.now());
        return candidate;
    }

    private void requireProject(String projectId) throws IOException {
        if (!ProjectStore.isValidId(projectId)) throw new IllegalArgumentException("invalid project id");
        projects.open(projectId);
    }
}
