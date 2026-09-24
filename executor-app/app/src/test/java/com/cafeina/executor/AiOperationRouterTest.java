package com.cafeina.executor;

import static org.junit.Assert.*;
import java.util.Arrays;
import java.util.Collections;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public final class AiOperationRouterTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();

    @Test public void projectInfoIsReadOnlyAndProjectScoped() throws Exception {
        ProjectStore projects = new ProjectStore(temp.newFolder("projects").toPath());
        projects.create("alpha");
        AiOperationRouter router = AiOperationRouter.forProjects(projects);
        AiCapabilitySet granted = new AiCapabilitySet(Collections.singleton(AiOperationRouter.PROJECT_READ));
        CafeinaAiCore.Response result = router.dispatch(
            request("alpha", "operation:project.info", AiOperationRouter.PROJECT_READ), granted);
        assertTrue(result.message.contains("alpha"));
        assertEquals(Collections.singletonList(AiOperationRouter.PROJECT_READ), result.usedCapabilities);
        assertThrows(IllegalStateException.class, () -> router.dispatch(
            request("other", "operation:project.info", AiOperationRouter.PROJECT_READ), granted));
        assertEquals(Collections.singletonList("alpha"), projects.listProjectIds());
    }

    @Test public void missingPermissionFailsBeforeOperationRuns() {
        final boolean[] called = {false};
        AiOperationRouter router = new AiOperationRouter().register("test.read", "test.read", request -> {
            called[0] = true;
            return new CafeinaAiCore.Response("ok", Collections.emptyList());
        });
        assertThrows(SecurityException.class, () -> router.dispatch(
            request("alpha", "operation:test.read"), new AiCapabilitySet(Collections.singleton("test.read"))));
        assertThrows(SecurityException.class, () -> router.dispatch(
            request("alpha", "operation:test.read", "test.read"), AiCapabilitySet.none()));
        assertFalse(called[0]);
    }

    @Test public void unknownAndDuplicateOperationsFailExplicitly() {
        AiOperationRouter router = new AiOperationRouter();
        assertThrows(IllegalArgumentException.class, () -> router.dispatch(
            request("alpha", "operation:unknown"), AiCapabilitySet.none()));
        router.register("test.read", "test.read", request ->
            new CafeinaAiCore.Response("ok", Collections.emptyList()));
        assertThrows(IllegalArgumentException.class, () -> router.register(
            "test.read", "test.read", request -> new CafeinaAiCore.Response("bad", Collections.emptyList())));
    }

    private static CafeinaAiCore.Request request(String project, String message, String... capabilities) {
        return new CafeinaAiCore.Request(project, message, Arrays.asList(capabilities));
    }
}
