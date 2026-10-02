package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Collections;
import java.util.List;
import java.util.UUID;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiActionTimelineInstrumentedTest {
    @Test
    public void timelineJoinsExistingAuditsInChronologicalOrder()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "timeline" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "timeline.tool";

        LaboratoryAiTaskContractStore contracts =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project);
        LaboratoryAiTaskContractStore.Contract contract =
            contracts.create(
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Validar a linha do tempo derivada.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    1024,
                    30_000L));

        LaboratoryAiExecutionStatus.Tracker planner =
            new LaboratoryAiExecutionStatus.Tracker(
                contract.contractId,
                null);
        planner.update(
            LaboratoryAiExecutionStatus.Phase.PLANNING,
            "Montando plano",
            1,
            1);
        planner.complete("Plano validado", 1, 1);
        new LaboratoryAiExecutionHistoryStore(
            app.getFilesDir(), project)
            .saveExecution(planner.history());

        LaboratoryAiTaskContractStore.Claim claim =
            contracts.claim(contract.contractId);

        String sessionId = UUID.randomUUID().toString();
        LaboratoryAiSessionStore sessions =
            new LaboratoryAiSessionStore(
                app.getFilesDir(), project);
        sessions.begin(
            sessionId,
            System.currentTimeMillis(),
            Collections.singletonList(toolId),
            2,
            1024,
            30_000L);

        LaboratoryAiTeamRegistry team =
            new LaboratoryAiTeamRegistry(
                app.getFilesDir(), project);
        team.registerMember(
            "test-agent",
            "IA de Teste",
            LaboratoryAiTeamRegistry.ROLE_TESTER);
        team.bindSession(
            sessionId,
            "test-agent",
            contract.contractId);

        sessions.append(
            sessionId,
            LaboratoryAiSessionStore.INVOKE_REQUEST,
            "ACTIVE",
            toolId,
            repeat("a", 64),
            12,
            "",
            "REQUESTED",
            1,
            12);
        sessions.append(
            sessionId,
            LaboratoryAiSessionStore.INVOKE_RESULT,
            "ACTIVE",
            toolId,
            repeat("a", 64),
            12,
            UUID.randomUUID().toString(),
            "PASS",
            1,
            12);
        sessions.append(
            sessionId,
            LaboratoryAiSessionStore.FINISH,
            "FINISHED",
            "",
            "",
            0,
            "",
            "PASS",
            1,
            12);

        contracts.recordResult(
            contract.contractId,
            claim.claimId,
            "SESSION_CREATED",
            sessionId,
            "TEST_COMPLETED");

        LaboratoryAiActionTimeline.Snapshot timeline =
            LaboratoryAiActionTimeline.inspect(
                app.getFilesDir(),
                project,
                contract.contractId,
                "");

        assertEquals(contract.contractId, timeline.contractId);
        assertTrue(timeline.items.size() >= 8);

        long previous = 0L;
        boolean sawGoal = false;
        boolean sawPlanner = false;
        boolean sawInvoke = false;
        boolean sawFinish = false;
        boolean sawResult = false;

        for (LaboratoryAiActionTimeline.Item item : timeline.items) {
            assertTrue(item.atEpochMs >= previous);
            previous = item.atEpochMs;

            if ("GOAL_LOCK_CREATED".equals(item.code)) {
                sawGoal = true;
            }
            if (item.code.startsWith("PLANNER_")) {
                sawPlanner = true;
            }
            if ("SESSION_INVOKE_REQUEST".equals(item.code)) {
                sawInvoke = true;
                assertTrue(item.detail.contains(toolId));
            }
            if ("SESSION_FINISH".equals(item.code)) {
                sawFinish = true;
            }
            if ("CONTRACT_RESULT".equals(item.code)) {
                sawResult = true;
            }
        }

        assertTrue(sawGoal);
        assertTrue(sawPlanner);
        assertTrue(sawInvoke);
        assertTrue(sawFinish);
        assertTrue(sawResult);
    }

    @Test
    public void timelineUsesCheckpointWhenPlannerHasNoTerminalHistory()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "timelinecp" + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryAiTaskContractStore.Contract contract =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(), project)
                .create(
                    LaboratoryAiTaskContractStore.Mode.LEARNING,
                    "Manter último ponto do planejador.",
                    new LaboratoryAiSessionController.Policy(
                        Collections.singletonList("timeline.tool"),
                        1,
                        256,
                        30_000L));

        LaboratoryAiExecutionStatus.Tracker planner =
            new LaboratoryAiExecutionStatus.Tracker(
                contract.contractId,
                null);
        planner.update(
            LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT,
            "Processando prompt",
            1,
            1);
        planner.updateNativeTelemetry(
            2,
            100,
            44,
            0,
            64,
            20L,
            1_000L,
            0L,
            30_000L,
            1,
            1);

        new LaboratoryAiPlannerCheckpointStore(
            app.getFilesDir(), project)
            .write(planner.snapshot());

        LaboratoryAiActionTimeline.Snapshot timeline =
            LaboratoryAiActionTimeline.inspect(
                app.getFilesDir(),
                project,
                contract.contractId,
                "");

        boolean sawCheckpoint = false;
        for (LaboratoryAiActionTimeline.Item item : timeline.items) {
            if (item.code.startsWith("PLANNER_CHECKPOINT_")) {
                sawCheckpoint = true;
                assertTrue(item.detail.contains("44/100"));
            }
        }
        assertTrue(sawCheckpoint);
    }

    private static String repeat(String value, int count) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < count; i++) out.append(value);
        return out.toString();
    }
}
