package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ActivityInfo;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryAiTaskContractInstrumentedTest {
    private static final class Outcome {
        LaboratoryAiToolController.Execution execution;
        Throwable error;
    }

    @Test
    public void exactGoalIsLockedAndContractCreatesOnlyOneSession()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "taskgoal"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "goal-tool";
        prepareGrantedStable(app, project, toolId);

        ActivityInfo info = app.getPackageManager().getActivityInfo(
            new ComponentName(app, LaboratoryAiTaskContractsActivity.class), 0);
        assertFalse("Goal Lock Activity must remain private", info.exported);

        String exactGoal =
            "  Criar exatamente o resultado pedido.\n"
                + "Preservar esta segunda linha e os espaços finais.  ";
        LaboratoryAiSessionController.Policy policy =
            new LaboratoryAiSessionController.Policy(
                Collections.singletonList(toolId),
                3,
                256,
                30_000L);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                exactGoal,
                policy);

        assertEquals(exactGoal, contract.goalText);
        assertEquals(
            LaboratoryEngine.fingerprint(exactGoal).substring(7, 71),
            contract.goalSha256);
        assertEquals(Collections.singletonList(toolId), contract.allowedToolIds);
        assertFalse(contract.claimed);
        assertFalse(contract.resultRecorded);

        LaboratoryAiTaskAdmission.TaskHandles admitted =
            LaboratoryAiTaskAdmission.admit(
                app, project, contract.contractId);

        assertEquals(contract.contractId, admitted.ai.contractId());
        assertEquals(
            LaboratoryAiTaskContractStore.Mode.CREATION,
            admitted.ai.mode());
        assertEquals(exactGoal, admitted.ai.goal());
        assertEquals(contract.goalSha256, admitted.ai.goalSha256());
        assertEquals(admitted.host.sessionId(), admitted.ai.sessionId());
        assertEquals(1, admitted.ai.listAvailable().size());

        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(app.getFilesDir(), project);
        LaboratoryAiTaskContractStore.Contract after =
            store.read(contract.contractId);
        assertTrue(after.claimed);
        assertTrue(after.resultRecorded);
        LaboratoryAiTaskContractStore.Result result =
            store.readResult(contract.contractId);
        assertEquals("SESSION_CREATED", result.status);
        assertEquals(admitted.ai.sessionId(), result.sessionId);

        assertThrows(java.io.IOException.class, () ->
            LaboratoryAiTaskAdmission.admit(
                app, project, contract.contractId));

        Outcome run = execute(admitted.ai, toolId, "task-case");
        if (run.error != null) throw new AssertionError(run.error);
        assertNotNull(run.execution);
        assertEquals("task-case", run.execution.firstReturn);

        Path sessionRoot = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/ai-sessions/"
                + admitted.ai.sessionId());
        String manifest = new String(
            Files.readAllBytes(sessionRoot.resolve("manifest.json")),
            StandardCharsets.UTF_8);
        assertFalse(manifest.contains(exactGoal));
        assertFalse(manifest.contains("Criar exatamente"));

        Set<String> aiMethods = new HashSet<>();
        for (Method method :
                LaboratoryAiTaskAdmission.AiTaskHandle.class.getDeclaredMethods()) {
            aiMethods.add(method.getName());
        }
        assertTrue(aiMethods.contains("goal"));
        assertTrue(aiMethods.contains("listAvailable"));
        assertTrue(aiMethods.contains("execute"));
        assertFalse(aiMethods.contains("pause"));
        assertFalse(aiMethods.contains("resume"));
        assertFalse(aiMethods.contains("cancel"));
        assertFalse(aiMethods.contains("host"));

        admitted.host.cancel();
    }

    @Test
    public void tamperedGoalInvalidatesGoalLockBeforeAdmission() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "tasktamper"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "tamper-goal-tool";
        prepareGrantedStable(app, project, toolId);

        String originalGoal = "Objetivo original protegido.";
        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                originalGoal,
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    128,
                    30_000L));

        Path path = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + project + "/ai-task-contracts/"
                + contract.contractId + "/contract.json");
        String raw = new String(
            Files.readAllBytes(path), StandardCharsets.UTF_8);
        raw = raw.replace(
            originalGoal,
            "Objetivo adulterado e diferente.");
        Files.write(path, raw.getBytes(StandardCharsets.UTF_8));

        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(app.getFilesDir(), project);
        assertThrows(java.io.IOException.class, () ->
            store.read(contract.contractId));
        assertThrows(java.io.IOException.class, () ->
            LaboratoryAiTaskAdmission.admit(
                app, project, contract.contractId));
    }

    @Test
    public void failedAdmissionConsumesContractAndCannotBeReplayed()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "taskfail"
            + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "revoked-goal-tool";
        prepareGrantedStable(app, project, toolId);

        LaboratoryAiTaskContractStore.Contract contract =
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.LEARNING,
                "Estudar a ferramenta sem alterar o objetivo.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList(toolId),
                    2,
                    128,
                    30_000L));

        new LaboratoryAiPermissionStore(app.getFilesDir(), project)
            .revoke(toolId);

        assertThrows(SecurityException.class, () ->
            LaboratoryAiTaskAdmission.admit(
                app, project, contract.contractId));

        LaboratoryAiTaskContractStore store =
            new LaboratoryAiTaskContractStore(app.getFilesDir(), project);
        LaboratoryAiTaskContractStore.Contract after =
            store.read(contract.contractId);
        assertTrue(after.claimed);
        assertTrue(after.resultRecorded);

        LaboratoryAiTaskContractStore.Result result =
            store.readResult(contract.contractId);
        assertEquals("SESSION_FAILED", result.status);
        assertEquals("", result.sessionId);
        assertEquals("SecurityException", result.reason);

        assertThrows(java.io.IOException.class, () ->
            LaboratoryAiTaskAdmission.admit(
                app, project, contract.contractId));
    }

    @Test
    public void contractCannotIncludeToolNotGrantedToAi() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String project = "taskdeny"
            + UUID.randomUUID().toString().substring(0, 8);

        assertThrows(SecurityException.class, () ->
            LaboratoryAiTaskAdmission.createContract(
                app,
                project,
                LaboratoryAiTaskContractStore.Mode.CREATION,
                "Objetivo bloqueado.",
                new LaboratoryAiSessionController.Policy(
                    Collections.singletonList("not-granted-tool"),
                    1,
                    64,
                    10_000L)));
    }

    private static Outcome execute(
            LaboratoryAiTaskAdmission.AiTaskHandle ai,
            String toolId, String input) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Outcome> ref = new AtomicReference<>();

        new Thread(() -> {
            Outcome outcome = new Outcome();
            try {
                ai.execute(toolId, input, (success, failure) -> {
                    outcome.execution = success;
                    outcome.error = failure;
                    ref.set(outcome);
                    done.countDown();
                });
            } catch (Throwable error) {
                outcome.error = error;
                ref.set(outcome);
                done.countDown();
            }
        }, "task-goal-lock-test").start();

        assertTrue(done.await(30, TimeUnit.SECONDS));
        assertNotNull(ref.get());
        return ref.get();
    }

    private static void prepareGrantedStable(
            Context app, String project, String toolId) throws Exception {
        String version = "1.0.0";
        String source = "return tool_input";

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(app.getFilesDir(), project);
        LaboratoryToolRegistry.Descriptor descriptor =
            new LaboratoryToolRegistry.Descriptor(
                toolId,
                version,
                LaboratoryEngine.fingerprint(source).substring(7, 71),
                "AI_TOOL_WORKSHOP",
                Arrays.asList(
                    LaboratoryStableToolExecutor.REQUIRED_CAPABILITY,
                    "diagnostics"),
                Collections.singletonList("artifact"),
                "cafeina-lab-api-1",
                1000,
                4096);
        registry.registerExperimental(descriptor);

        LaboratorySnapshotStore snapshots =
            new LaboratorySnapshotStore(app.getFilesDir(), project);
        LaboratorySnapshotStore.Snapshot snapshot = snapshots.create(
            toolId, source.getBytes(StandardCharsets.UTF_8));
        new LaboratoryToolArtifactStore(app.getFilesDir(), project)
            .bindLuauSource(toolId, version, snapshot.id);

        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL,
            LaboratoryEngine.FINGERPRINT_VERSION,
            20260930L,
            1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "artifact", source, LaboratoryEngine.fingerprint(source))));
        LaboratoryEngine.Report evidence = LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), project, request,
            new LaboratoryEngine.Cancellation());
        registry.qualifyCandidate(
            toolId, version, Collections.singletonList(evidence.runId));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                toolId, version, System.currentTimeMillis());
        approvals.applyApprovedTransition(approval.receiptId);

        LaboratoryAiPermissionStore permissions =
            new LaboratoryAiPermissionStore(app.getFilesDir(), project);
        permissions.grantAfterDeviceCredential(
            toolId, System.currentTimeMillis());
    }
}
