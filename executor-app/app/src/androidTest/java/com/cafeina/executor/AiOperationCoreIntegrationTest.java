package com.cafeina.executor;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import org.junit.Test;

/** Verifies that the real AI core dispatches known operations without invoking a model. */
public final class AiOperationCoreIntegrationTest {
    @Test public void knownOperationDoesNotInvokeModel() throws Exception {
        Context app = ApplicationProvider.getApplicationContext();
        Path root = Files.createTempDirectory(app.getCacheDir().toPath(), "ai-operations-");
        ProjectStore projects = new ProjectStore(root.resolve("projects"));
        projects.create("alpha");
        CafeinaKnowledgeDatabase db = new CafeinaKnowledgeDatabase(app);
        try {
            final boolean[] modelCalled = {false};
            AiModelProvider model = (request, context, capabilities) -> {
                modelCalled[0] = true;
                return new CafeinaAiCore.Response("model", Collections.emptyList());
            };
            AiCapabilitySet granted = new AiCapabilitySet(Collections.singleton(AiOperationRouter.PROJECT_READ));
            DefaultCafeinaAiCore core = new DefaultCafeinaAiCore(
                new AiContextAssembler(new KnowledgeRepository(db)),
                model, granted, AiOperationRouter.forProjects(projects));
            CafeinaAiCore.Response result = core.handle(new CafeinaAiCore.Request(
                "alpha", "operation:project.info", Collections.singletonList(AiOperationRouter.PROJECT_READ)));
            assertTrue(result.message.contains("alpha"));
            assertFalse(modelCalled[0]);
            assertThrows(SecurityException.class, () -> core.handle(new CafeinaAiCore.Request(
                "alpha", "operation:project.info", Collections.emptyList())));
            assertThrows(IllegalArgumentException.class, () -> core.handle(new CafeinaAiCore.Request(
                "alpha", "operation:unknown", Collections.emptyList())));
            assertFalse(modelCalled[0]);
            DefaultCafeinaAiCore legacyCore = new DefaultCafeinaAiCore(
                new AiContextAssembler(new KnowledgeRepository(db)), model, granted);
            assertThrows(IllegalStateException.class, () -> legacyCore.handle(new CafeinaAiCore.Request(
                "alpha", "operation:project.info", Collections.singletonList(AiOperationRouter.PROJECT_READ))));
            assertFalse(modelCalled[0]);
        } finally {
            db.close();
        }
    }
}
