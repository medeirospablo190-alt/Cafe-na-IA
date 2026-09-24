package com.cafeina.executor;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import java.nio.file.Files;
import java.nio.file.Path;

public final class AiMissionLifecycleCoordinatorTest {
    private Context context;
    private CafeinaKnowledgeDatabase database;
    private AiMissionCheckpointRepository checkpoints;
    private AiMissionLifecycleCoordinator lifecycle;
    private Path root;
    private ProjectStore projects;

    @Before public void setUp() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        database = new CafeinaKnowledgeDatabase(context);
        checkpoints = new AiMissionCheckpointRepository(database);
        root = Files.createTempDirectory("cafeina-missions-");
        projects = new ProjectStore(root);
        projects.create("project-a");
        lifecycle = new AiMissionLifecycleCoordinator(projects, checkpoints, () -> 100);
    }

    @After public void tearDown() throws Exception {
        database.close();
        context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);
        if (root != null) {
            try (java.util.stream.Stream<Path> paths = Files.walk(root)) {
                paths.sorted((a, b) -> b.getNameCount() - a.getNameCount()).forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (Exception ignored) { }
                });
            }
        }
    }

    @Test public void persistsEveryLiveTransitionAndReopensTerminalMission() throws Exception {
        AiMission created = lifecycle.create("m", "project-a", "goal");
        AiMission running = lifecycle.transition(created, AiMission::start);
        assertEquals(AiMissionState.RUNNING, checkpoints.load("project-a", "m").state);
        AiMission completed = lifecycle.transition(running, AiMission::complete);
        assertEquals(AiMissionState.COMPLETED, completed.state());
        database.close();
        database = new CafeinaKnowledgeDatabase(context);
        checkpoints = new AiMissionCheckpointRepository(database);
        lifecycle = new AiMissionLifecycleCoordinator(projects, checkpoints, () -> 101);
        assertEquals(AiMissionState.COMPLETED, lifecycle.restore("project-a", "m").state());
    }

    @Test public void interruptedRunningIsDurablyPausedBeforeResume() throws Exception {
        AiMission running = lifecycle.transition(lifecycle.create("m", "project-a", "goal"), AiMission::start);
        assertEquals(AiMissionState.RUNNING, running.state());
        AiMission recovered = lifecycle.restore("project-a", "m");
        assertEquals(AiMissionState.WAITING_USER, recovered.state());
        assertEquals(AiMissionState.WAITING_USER, checkpoints.load("project-a", "m").state);
        assertThrows(IllegalStateException.class, () -> lifecycle.transition(running, AiMission::complete));
        AiMission resumed = lifecycle.transition(recovered, AiMission::resume);
        assertEquals(AiMissionState.RUNNING, resumed.state());
    }

    @Test public void rejectsUnknownProjectAndDuplicateIdentity() throws Exception {
        assertThrows(java.io.IOException.class, () -> lifecycle.create("m", "missing", "goal"));
        lifecycle.create("m", "project-a", "goal");
        assertThrows(IllegalStateException.class, () -> lifecycle.create("m", "project-a", "goal"));
    }
}
