package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryStableToolExecutorInstrumentedTest {
    private static final class Prepared {
        LaboratoryToolRegistry.Tool tool;
        Throwable error;
    }

    private static final class Executed {
        LaboratoryStableToolExecutor.Execution success;
        Throwable error;
    }

    @Test
    public void stableGateExecutesOnlyActiveApprovedVersionAndAuditsWithoutRawData()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String projectId = "stable-use-" + UUID.randomUUID().toString().substring(0, 8);
        String toolId = "upper-tool";
        String version = "0.1.0";
        String source = "if tool_input == 'bad private input' then "
            + "error('secret runtime error') end return string.upper(tool_input)";

        Prepared prepared = prepare(app, projectId, toolId, version, source, "");
        if (prepared.error != null) throw new AssertionError(prepared.error);
        assertNotNull(prepared.tool);

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(app.getFilesDir(), projectId);
        approvals.recordDeviceCredentialApproval(
            toolId, version, System.currentTimeMillis());

        LaboratoryStableActivationStore stable =
            new LaboratoryStableActivationStore(app.getFilesDir(), projectId);
        stable.activateApproved(toolId, version, System.currentTimeMillis());

        String privateInput = "hello private stable input";
        Executed good = execute(app, projectId, toolId, privateInput);
        if (good.error != null) throw new AssertionError(good.error);
        assertNotNull(good.success);
        assertEquals("HELLO PRIVATE STABLE INPUT", good.success.firstReturn);
        assertEquals(toolId, good.success.toolId);
        assertEquals(version, good.success.toolVersion);
        assertTrue(good.success.audit.usable);
        assertTrue(good.success.audit.selectionVerified);
        assertEquals("EXECUTED", good.success.audit.workerStatus);

        LaboratoryStableUseStore uses =
            new LaboratoryStableUseStore(app.getFilesDir(), projectId);
        assertEquals(1, uses.list().size());
        LaboratoryStableUseStore.Use saved = uses.read(good.success.runId);
        assertEquals(good.success.audit.inputSha256, saved.inputSha256);
        assertEquals(prepared.tool.sourceSha256, saved.sourceSha256);

        Path receipt = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + projectId + "/stable-tool-uses/"
                + good.success.runId + ".use");
        String raw = new String(Files.readAllBytes(receipt), StandardCharsets.UTF_8);
        assertFalse(raw.contains(privateInput));
        assertFalse(raw.contains("HELLO PRIVATE STABLE INPUT"));
        assertFalse(raw.contains(source));

        // Worker/runtime failures are audited but their output is not delivered
        // as a usable tool result to the future AI caller.
        Executed bad = execute(app, projectId, toolId, "bad private input");
        assertNull(bad.success);
        assertNotNull(bad.error);
        assertTrue(bad.error.getMessage().contains("LUAU_ERROR"));
        assertEquals(2, uses.list().size());
        LaboratoryStableUseStore.Use failed = uses.list().stream()
            .filter(item -> !item.runId.equals(saved.runId))
            .findFirst().get();
        assertFalse(failed.usable);
        assertEquals("LUAU_ERROR", failed.workerStatus);
        String failedRaw = new String(Files.readAllBytes(
            app.getFilesDir().toPath().resolve(
                "laboratory/project-" + projectId + "/stable-tool-uses/"
                    + failed.runId + ".use")), StandardCharsets.UTF_8);
        assertFalse(failedRaw.contains("bad private input"));
        assertFalse(failedRaw.contains("secret runtime error"));

        stable.deactivate(toolId, System.currentTimeMillis());
        Executed disabled = execute(app, projectId, toolId, "should never run");
        assertNull(disabled.success);
        assertNotNull(disabled.error);
        assertTrue(disabled.error.getMessage().contains("no active STABLE"));
        assertEquals("No audit should be created for preflight denial", 2, uses.list().size());
    }

    private static Prepared prepare(Context app, String projectId,
            String toolId, String version, String source, String expected) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Prepared> ref = new AtomicReference<>();
        new Thread(() -> {
            Prepared out = new Prepared();
            try {
                LaboratoryToolWorkshop.testNewVersion(app, projectId, toolId, version,
                    source, expected, 777L, 1000,
                    (execution, tool, awaitingReview, error) -> {
                        out.tool = tool;
                        if (error != null) out.error = error;
                        else if (!awaitingReview) {
                            out.error = new AssertionError(
                                "prepared STABLE tool did not reach CANDIDATE");
                        }
                        ref.set(out);
                        done.countDown();
                    });
            } catch (Throwable error) {
                out.error = error;
                ref.set(out);
                done.countDown();
            }
        }, "stable-use-prepare").start();
        assertTrue("tool preparation timed out", done.await(45, TimeUnit.SECONDS));
        return ref.get();
    }

    private static Executed execute(Context app, String projectId,
            String toolId, String input) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Executed> ref = new AtomicReference<>();
        new Thread(() -> {
            Executed out = new Executed();
            try {
                LaboratoryStableToolExecutor.executeInternal(
                    app, projectId, toolId, input, (success, error) -> {
                        out.success = success;
                        out.error = error;
                        ref.set(out);
                        done.countDown();
                    });
            } catch (Throwable error) {
                out.error = error;
                ref.set(out);
                done.countDown();
            }
        }, "stable-use-executor").start();
        assertTrue("stable execution timed out", done.await(45, TimeUnit.SECONDS));
        assertNotNull(ref.get());
        return ref.get();
    }
}
