package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiChatSessionStoreInstrumentedTest {
    @Test
    public void persistsConversationAndOperationalStateSeparately()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "chatstate" + UUID.randomUUID().toString().substring(0, 8);

        String contractId = UUID.randomUUID().toString();
        String scenarioId = UUID.randomUUID().toString();
        LaboratoryAiChatSessionStore.Entry user =
            LaboratoryAiChatSessionStore.Entry.create(
                LaboratoryAiChatSessionStore.Role.USER,
                "Oi, tudo bem?",
                true);
        LaboratoryAiChatSessionStore.Entry assistant =
            LaboratoryAiChatSessionStore.Entry.create(
                LaboratoryAiChatSessionStore.Role.ASSISTANT,
                "Tudo certo por aqui.",
                true);
        LaboratoryAiChatSessionStore.Entry operational =
            LaboratoryAiChatSessionStore.Entry.create(
                LaboratoryAiChatSessionStore.Role.ASSISTANT,
                "Testadora preparada, mas ainda não executada.",
                false);

        LaboratoryAiChatSessionStore store =
            new LaboratoryAiChatSessionStore(
                app.getFilesDir(), project);
        store.save(new LaboratoryAiChatSessionStore.Snapshot(
            System.currentTimeMillis(),
            Arrays.asList(user, assistant, operational),
            LaboratoryAiChatSessionStore.WorkflowState.TEST_PREPARED,
            contractId,
            scenarioId,
            "",
            "Aguardando confirmação"));

        LaboratoryAiChatSessionStore.Snapshot restored =
            store.load();
        assertEquals(3, restored.entries.size());
        assertEquals(
            LaboratoryAiChatSessionStore.WorkflowState.TEST_PREPARED,
            restored.workflowState);
        assertEquals(contractId, restored.contractId);
        assertEquals(scenarioId, restored.scenarioId);
        assertEquals("Aguardando confirmação", restored.statusDetail);
        assertTrue(restored.entries.get(0).modelContext);
        assertTrue(restored.entries.get(1).modelContext);
        assertFalse(restored.entries.get(2).modelContext);

        Path state = app.getFilesDir().toPath()
            .resolve("laboratory")
            .resolve("project-" + project)
            .resolve("ai-chat-session")
            .resolve("state.json");
        assertTrue(Files.isRegularFile(state));
        String raw = new String(
            Files.readAllBytes(state),
            StandardCharsets.UTF_8);
        assertTrue(raw.contains("Oi, tudo bem?"));
        assertTrue(raw.contains("TEST_PREPARED"));
        assertFalse(
            state.toString().toLowerCase(java.util.Locale.ROOT)
                .contains("knowledge"));
    }

    @Test
    public void clearDoesNotAffectOtherLaboratoryState()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "chatclear" + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiChatSessionStore store =
            new LaboratoryAiChatSessionStore(
                app.getFilesDir(), project);
        store.save(new LaboratoryAiChatSessionStore.Snapshot(
            System.currentTimeMillis(),
            java.util.Collections.singletonList(
                LaboratoryAiChatSessionStore.Entry.create(
                    LaboratoryAiChatSessionStore.Role.USER,
                    "mensagem local",
                    true)),
            LaboratoryAiChatSessionStore.WorkflowState.IDLE,
            "",
            "",
            "",
            ""));

        Path projectRoot = app.getFilesDir().toPath()
            .resolve("laboratory")
            .resolve("project-" + project);
        Path sentinel = projectRoot.resolve("unrelated-state.txt");
        Files.write(
            sentinel,
            "preservar".getBytes(StandardCharsets.UTF_8));

        store.clear();

        assertTrue(Files.isRegularFile(sentinel));
        assertTrue(store.load().entries.isEmpty());
        assertEquals(
            LaboratoryAiChatSessionStore.WorkflowState.IDLE,
            store.load().workflowState);
    }
}
