package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ServiceInfo;
import android.os.Process;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@RunWith(AndroidJUnit4.class)
public final class LaboratorySandboxInstrumentedTest {
    @Test
    public void workerHasIsolatedUidAndNoFilesystemCapability() throws Exception {
        Context app = InstrumentationRegistry.getInstrumentation().getTargetContext();
        ServiceInfo info = app.getPackageManager().getServiceInfo(
            new ComponentName(app, LaboratorySandboxService.class), 0);
        assertFalse("Laboratory service must not be exported", info.exported);
        assertTrue("Laboratory service must have an isolated Android UID",
            (info.flags & ServiceInfo.FLAG_ISOLATED_PROCESS) != 0);

        LaboratorySandboxClient.Result arithmetic = run(app, "return 2 + 2", 1000);
        assertEquals(arithmetic.error, "EXECUTED", arithmetic.status);
        assertEquals("4", arithmetic.firstReturn);
        assertNotEquals("Worker UID must differ from host UID",
            Process.myUid(), arithmetic.workerUid);

        LaboratorySandboxClient.Result denied = run(app, "return fs == nil", 1000);
        assertEquals(denied.error, "EXECUTED", denied.status);
        assertEquals("true", denied.firstReturn);
        assertNotEquals(Process.myUid(), denied.workerUid);
    }

    private static LaboratorySandboxClient.Result run(Context app, String source, int timeoutMs)
            throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<LaboratorySandboxClient.Result> outcome = new AtomicReference<>();
        LaboratorySandboxClient.execute(app, source, timeoutMs, result -> {
            outcome.set(result);
            done.countDown();
        });
        assertTrue("Isolated worker did not answer before host watchdog",
            done.await(30, TimeUnit.SECONDS));
        assertNotNull(outcome.get());
        return outcome.get();
    }
}
