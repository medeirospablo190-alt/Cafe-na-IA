package com.cafeina.executor;

/** Immutable mission checkpoint; storage and permissions remain host-owned. */
public final class AiMissionSnapshot {
    public final String id;
    public final String projectId;
    public final String goal;
    public final AiMissionState state;

    public AiMissionSnapshot(String id, String projectId, String goal, AiMissionState state) {
        this.id = require(id, "id");
        this.projectId = require(projectId, "projectId");
        this.goal = require(goal, "goal");
        if (state == null) throw new IllegalArgumentException("state is required");
        this.state = state;
    }

    private static String require(String value, String field) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }
}
