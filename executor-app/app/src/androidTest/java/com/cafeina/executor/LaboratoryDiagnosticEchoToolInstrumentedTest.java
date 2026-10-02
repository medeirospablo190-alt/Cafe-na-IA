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

import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratoryDiagnosticEchoToolInstrumentedTest {
    @Test
    public void bootstrapLifecycleSeparatesCandidateStableAndAiPermission()
            throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation()
            .getTargetContext();
        String project =
            "echotool" + UUID.randomUUID().toString().substring(0, 8);

        LaboratoryDiagnosticEchoTool.State prepared =
            LaboratoryDiagnosticEchoTool.prepareExperimental(
                app.getFilesDir(),
                project);
        assertTrue(prepared.registered);
        assertTrue(prepared.artifactBound);
        assertEquals(
            LaboratoryToolRegistry.Stage.EXPERIMENTAL,
            prepared.stage);

        LaboratoryToolRegistry registry =
            new LaboratoryToolRegistry(
                app.getFilesDir(),
                project);
        LaboratoryToolRegistry.Descriptor descriptor =
            registry.readDescriptor(
                LaboratoryDiagnosticEchoTool.TOOL_ID,
                LaboratoryDiagnosticEchoTool.VERSION);
        assertEquals(
            LaboratoryDiagnosticEchoTool.sourceSha256(),
            descriptor.artifactSha256);
        assertTrue(descriptor.capabilities.contains(
            LaboratoryStableToolExecutor.REQUIRED_CAPABILITY));
        assertEquals(
            3,
            descriptor.requiredTests.size());

        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratoryCandidateTestSuiteRunner.Result>
            suiteResult = new AtomicReference<>();
        AtomicReference<java.io.IOException> suiteFailure =
            new AtomicReference<>();

        LaboratoryCandidateTestSuiteRunner.run(
            app,
            project,
            LaboratoryDiagnosticEchoTool.TOOL_ID,
            LaboratoryDiagnosticEchoTool.VERSION,
            LaboratoryDiagnosticEchoTool.suiteCases(),
            new LaboratoryCandidateTestSuiteRunner.Control(),
            null,
            (result, failure) -> {
                suiteResult.set(result);
                suiteFailure.set(failure);
                done.countDown();
            });

        assertTrue(
            "candidate suite timed out",
            done.await(45, TimeUnit.SECONDS));
        assertNull(suiteFailure.get());

        LaboratoryCandidateTestSuiteRunner.Result suite =
            suiteResult.get();
        assertNotNull(suite);
        assertEquals(
            LaboratoryCandidateTestSuiteRunner.Status.PASS,
            suite.status);
        assertEquals(3, suite.totalCases);
        assertEquals(3, suite.passed);
        assertEquals(0, suite.failed);
        assertTrue(suite.qualifiesRequiredEvidence());
        assertEquals(3, suite.runIds.size());

        LaboratoryDiagnosticEchoTool.State candidate =
            LaboratoryDiagnosticEchoTool.qualifyCandidate(
                app.getFilesDir(),
                project,
                suite);
        assertEquals(
            LaboratoryToolRegistry.Stage.CANDIDATE,
            candidate.stage);
        assertFalse(candidate.activeStable);
        assertFalse(candidate.aiGranted);

        assertNull(
            registry.activeStable(
                LaboratoryDiagnosticEchoTool.TOOL_ID));
        assertNull(
            new LaboratoryAiPermissionStore(
                app.getFilesDir(),
                project)
                .activeGrant(
                    LaboratoryDiagnosticEchoTool.TOOL_ID));

        assertFalse(
            LaboratoryAiToolController.listAvailable(
                app,
                project).stream().anyMatch(tool ->
                    LaboratoryDiagnosticEchoTool.TOOL_ID
                        .equals(tool.toolId)));

        LaboratoryHumanApprovalStore approvals =
            new LaboratoryHumanApprovalStore(
                app.getFilesDir(),
                project);
        LaboratoryHumanApprovalStore.Approval approval =
            approvals.recordDeviceCredentialApproval(
                LaboratoryHumanApprovalStore.ACTIVATE_STABLE,
                LaboratoryDiagnosticEchoTool.TOOL_ID,
                LaboratoryDiagnosticEchoTool.VERSION,
                System.currentTimeMillis());
        approvals.applyApprovedTransition(
            approval.receiptId);

        LaboratoryDiagnosticEchoTool.State stable =
            LaboratoryDiagnosticEchoTool.inspect(
                app.getFilesDir(),
                project);
        assertEquals(
            LaboratoryToolRegistry.Stage.STABLE,
            stable.stage);
        assertTrue(stable.activeStable);
        assertFalse(stable.aiGranted);
        assertFalse(
            LaboratoryAiToolController.listAvailable(
                app,
                project).stream().anyMatch(tool ->
                    LaboratoryDiagnosticEchoTool.TOOL_ID
                        .equals(tool.toolId)));

        new LaboratoryAiPermissionStore(
            app.getFilesDir(),
            project)
            .grantAfterDeviceCredential(
                LaboratoryDiagnosticEchoTool.TOOL_ID,
                System.currentTimeMillis());

        LaboratoryDiagnosticEchoTool.State granted =
            LaboratoryDiagnosticEchoTool.inspect(
                app.getFilesDir(),
                project);
        assertTrue(granted.activeStable);
        assertTrue(granted.aiGranted);
        assertTrue(
            LaboratoryAiToolController.listAvailable(
                app,
                project).stream().anyMatch(tool ->
                    LaboratoryDiagnosticEchoTool.TOOL_ID
                        .equals(tool.toolId)));
    }
}
