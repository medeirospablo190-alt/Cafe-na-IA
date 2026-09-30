package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.UUID;

/**
 * All probes use compiled-in tools and synthetic fixture inputs. This suite
 * does not open the user's World, editor, scripts, or isolated Luau worker.
 */
@RunWith(AndroidJUnit4.class)
public final class LaboratorySuiteInstrumentedTest {
    private static LaboratoryEngine.Request fingerprint(String value) {
        return new LaboratoryEngine.Request(
            LaboratoryEngine.FINGERPRINT_TOOL, LaboratoryEngine.FINGERPRINT_VERSION,
            9001, 1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "fingerprint", value, LaboratoryEngine.fingerprint(value))));
    }

    private static LaboratoryEngine.Request world(String probe, String expected) {
        return new LaboratoryEngine.Request(
            LaboratoryEngine.WORLD_CONTACT_TOOL, LaboratoryEngine.WORLD_CONTACT_VERSION,
            9001, 1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "world-contact", probe, expected)));
    }

    private static String project(String name) {
        return name + "-" + UUID.randomUUID().toString().substring(0, 8);
    }

    @Test
    public void batchReplayAndRegressionKeepIndependentEvidence() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String scope = project("suite");
        LaboratorySuiteStore store = new LaboratorySuiteStore(app.getFilesDir(), scope);
        LaboratoryEngine.Request clean = fingerprint("synthetic fixture A");
        LaboratoryEngine.Request firstWorld =
            world("0,20,-4200,100,100,100", "solids=Chao;zones=ZonaVerde");
        LaboratoryEngine.Cancellation cancel = new LaboratoryEngine.Cancellation();

        LaboratorySuiteRunner.Plan batchPlan = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH, Arrays.asList(clean, firstWorld),
            Collections.emptyList());
        LaboratorySuiteStore.Summary batch = LaboratorySuiteRunner.runInternal(
            app.getFilesDir(), scope, batchPlan, cancel);
        assertEquals(LaboratorySuiteStore.Status.PASS, batch.status);
        assertEquals(2, batch.passed);
        assertEquals(0, batch.failed);
        assertEquals(2, batch.reportIds.size());
        assertEquals(batchPlan.planSha256, store.read(batch.suiteId).planSha256);

        LaboratorySuiteStore.Summary replay = LaboratorySuiteRunner.runInternal(
            app.getFilesDir(), scope, new LaboratorySuiteRunner.Plan(
                LaboratorySuiteRunner.Mode.REPLAY, Arrays.asList(clean, firstWorld),
                Collections.emptyList()), new LaboratoryEngine.Cancellation());
        assertEquals(LaboratorySuiteStore.Status.PASS, replay.status);
        assertEquals(2, replay.passed);
        assertEquals(4, replay.reportIds.size());
        assertFalse(replay.reportIds.get(0).equals(replay.reportIds.get(1)));

        LaboratoryReportStore reports =
            new LaboratoryReportStore(app.getFilesDir(), scope);
        LaboratoryEngine.Report baseline = LaboratoryRunner.runApprovedBuiltIn(
            app.getFilesDir(), scope, firstWorld, new LaboratoryEngine.Cancellation());
        LaboratorySuiteRunner.Plan regressionPlan = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.REGRESSION,
            Collections.singletonList(firstWorld),
            Collections.singletonList(baseline.runId));
        LaboratorySuiteStore.Summary regression = LaboratorySuiteRunner.runInternal(
            app.getFilesDir(), scope, regressionPlan,
            new LaboratoryEngine.Cancellation());
        assertEquals(LaboratorySuiteStore.Status.PASS, regression.status);
        assertEquals(1, regression.passed);
        assertEquals(1, regression.reportIds.size());
        assertEquals("world-contact",
            reports.list().stream().filter(r -> r.runId.equals(baseline.runId))
                .findFirst().get().toolId);

        // The new run can pass its own expectations yet FAIL regression if
        // the fixture input differs from the reference run.
        LaboratoryEngine.Request changed =
            world("0,1650,0,340,825,340", "solids=PortaEvento;zones=-");
        LaboratorySuiteStore.Summary difference = LaboratorySuiteRunner.runInternal(
            app.getFilesDir(), scope, new LaboratorySuiteRunner.Plan(
                LaboratorySuiteRunner.Mode.REGRESSION,
                Collections.singletonList(changed),
                Collections.singletonList(baseline.runId)),
            new LaboratoryEngine.Cancellation());
        assertEquals(LaboratorySuiteStore.Status.FAIL, difference.status);
        assertEquals("REGRESSION_DIFFERENCE", difference.reason);
        assertEquals(0, difference.passed);
        assertEquals(1, difference.failed);
        assertEquals(1, difference.reportIds.size());
        assertEquals("PASS", reports.list().stream()
            .filter(r -> r.runId.equals(difference.reportIds.get(0)))
            .findFirst().get().status);
        assertEquals(4, store.list().size());
        assertTrue(new LaboratorySuiteStore(app.getFilesDir(),
            project("unrelated")).list().isEmpty());
    }

    @Test
    public void cancellationAndInterruptedRunsNeverShowPass() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String scope = project("cancel-suite");
        LaboratorySuiteStore store = new LaboratorySuiteStore(app.getFilesDir(), scope);
        LaboratorySuiteRunner.Plan plan = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH, Collections.singletonList(fingerprint("fixture")),
            Collections.emptyList());
        LaboratoryEngine.Cancellation cancelled = new LaboratoryEngine.Cancellation();
        cancelled.cancel();
        LaboratorySuiteStore.Summary end = LaboratorySuiteRunner.runInternal(
            app.getFilesDir(), scope, plan, cancelled);
        assertEquals(LaboratorySuiteStore.Status.CANCELLED, end.status);
        assertTrue(end.reportIds.isEmpty());

        LaboratorySuiteStore.Summary started = store.begin(
            plan.mode.name(), plan.planSha256, plan.requests.size(),
            Collections.emptyList());
        assertEquals(LaboratorySuiteStore.Status.RUNNING_OR_INTERRUPTED,
            store.read(started.suiteId).status);
        assertEquals(2, store.list().size());
    }

    @Test
    public void modifiedSuiteEvidenceFailsClosedAndIsNotDeleted() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String scope = project("corrupt-suite");
        LaboratorySuiteRunner.Plan plan = new LaboratorySuiteRunner.Plan(
            LaboratorySuiteRunner.Mode.BATCH, Collections.singletonList(fingerprint("fixture")),
            Collections.emptyList());
        LaboratorySuiteStore store = new LaboratorySuiteStore(app.getFilesDir(), scope);
        LaboratorySuiteStore.Summary done = LaboratorySuiteRunner.runInternal(
            app.getFilesDir(), scope, plan, new LaboratoryEngine.Cancellation());
        assertEquals(LaboratorySuiteStore.Status.PASS, done.status);
        Path target = app.getFilesDir().toPath().resolve(
            "laboratory/project-" + scope + "/suites/" + done.suiteId + ".done");
        byte[] bytes = Files.readAllBytes(target);
        bytes[bytes.length - 2] ^= 1;
        Files.write(target, bytes);
        assertThrows(IOException.class, () -> store.read(done.suiteId));
        assertThrows(IOException.class, store::list);
        assertTrue(Files.exists(target));
    }
}
