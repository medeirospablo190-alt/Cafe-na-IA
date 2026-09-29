package com.cafeina.executor;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.Process;
import android.os.RemoteException;
import android.os.SystemClock;

import com.cafeina.runtime.LuauBridge;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Must run with android:isolatedProcess=true. Receives bounded source by
 * Messenger, executes native Luau WITHOUT the filesystem capability, and
 * returns bounded results. It does not access app private directories.
 *
 * Only one run is allowed per service instance. ABORT kills this isolated
 * process, including a VM that has stopped responding to its native timeout.
 */
public final class LaboratorySandboxService extends Service {
    static final int RUN = 1;
    static final int ABORT = 2;
    static final int RESULT = 3;
    static final String RUN_ID = "run_id";
    static final String SOURCE = "source";
    static final String TIMEOUT_MS = "timeout_ms";
    static final String STATUS = "status";
    static final String OUTPUT = "output";
    static final String ERROR = "error";
    static final String RETURN_VALUE = "return_value";
    static final String WORKER_UID = "worker_uid";
    static final String ELAPSED_MS = "elapsed_ms";
    static final int MAX_SOURCE_CHARS = 16 * 1024;
    static final int MAX_TIMEOUT_MS = 3000;
    static final int MAX_RESPONSE_CHARS = 2048;

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private Messenger messenger;
    private boolean busy;
    private String activeRunId;

    @Override
    public void onCreate() {
        super.onCreate();
        messenger = new Messenger(new Handler(Looper.getMainLooper(), this::handle));
    }

    @Override
    public IBinder onBind(Intent intent) {
        return messenger.getBinder();
    }

    private boolean handle(Message message) {
        if (message.what == ABORT) {
            Bundle request = message.getData();
            if (busy && activeRunId != null
                    && activeRunId.equals(request.getString(RUN_ID))) {
                Process.killProcess(Process.myPid());
            }
            return true;
        }
        if (message.what != RUN) return false;
        Messenger reply = message.replyTo;
        if (reply == null) return true;
        Bundle request = message.getData();
        String id = request.getString(RUN_ID, "");
        String source = request.getString(SOURCE);
        int timeoutMs = request.getInt(TIMEOUT_MS, 0);

        if (busy || !validId(id) || source == null
                || source.length() > MAX_SOURCE_CHARS || timeoutMs < 1
                || timeoutMs > MAX_TIMEOUT_MS) {
            respond(reply, id, "REJECTED", "", "Invalid or busy sandbox request", "", 0);
            return true;
        }
        busy = true;
        activeRunId = id;
        final long started = SystemClock.elapsedRealtime();
        worker.execute(() -> {
            String status = "WORKER_ERROR";
            String output = "";
            String error = "";
            String returnValue = "";
            try {
                // Crucial: nativeExecute DOES NOT grant the Luau fs capability.
                String raw = LuauBridge.nativeExecute(source, timeoutMs);
                if (raw == null || raw.length() > 128 * 1024) {
                    error = "Worker produced an oversized result";
                } else {
                    JSONObject result = new JSONObject(raw);
                    status = result.optBoolean("ok", false) ? "EXECUTED" : "LUAU_ERROR";
                    output = bounded(result.optString("output", ""));
                    error = bounded(result.optString("error", ""));
                    JSONArray returns = result.optJSONArray("returns");
                    if (returns != null && returns.length() > 0) {
                        returnValue = bounded(returns.optString(0, ""));
                    }
                }
            } catch (Throwable failure) {
                error = "Isolated worker failed: " + failure.getClass().getSimpleName();
            }
            respond(reply, id, status, output, error, returnValue,
                SystemClock.elapsedRealtime() - started);
        });
        return true;
    }

    private static void respond(Messenger reply, String id, String status,
            String output, String error, String returnValue, long elapsedMs) {
        Bundle data = new Bundle();
        data.putString(RUN_ID, id);
        data.putString(STATUS, status);
        data.putString(OUTPUT, bounded(output));
        data.putString(ERROR, bounded(error));
        data.putString(RETURN_VALUE, bounded(returnValue));
        data.putInt(WORKER_UID, Process.myUid());
        data.putLong(ELAPSED_MS, elapsedMs);
        Message result = Message.obtain(null, RESULT);
        result.setData(data);
        try {
            reply.send(result);
        } catch (RemoteException ignored) {
            // The host went away; do not write results into app-private storage.
        }
    }

    private static boolean validId(String id) {
        try {
            return id != null && UUID.fromString(id).toString().equals(id);
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static String bounded(String text) {
        if (text == null) return "";
        return text.length() <= MAX_RESPONSE_CHARS
            ? text : text.substring(0, MAX_RESPONSE_CHARS);
    }

    @Override
    public void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
