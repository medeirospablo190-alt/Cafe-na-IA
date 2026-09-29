package com.cafeina.executor;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.Process;
import android.os.RemoteException;

import java.util.Objects;
import java.util.UUID;

/**
 * Host-side asynchronous sandbox client. Only the isolated service receives
 * the source. Callbacks run on the Android main thread; each session is
 * single-use and has a host-owned watchdog independent from native Luau.
 */
public final class LaboratorySandboxClient {
    public interface Callback {
        void onFinished(Result result);
    }

    public static final class Result {
        public final String runId;
        public final String sourceSha256;
        public final long startedAtEpochMs;
        public final long durationMs;
        public final int workerUid;
        public final String status;
        public final String output;
        public final String error;
        public final String firstReturn;

        private Result(String id, String hash, long started, long duration, int workerUid,
                String status, String output, String error, String firstReturn) {
            this.runId = id;
            this.sourceSha256 = hash;
            this.startedAtEpochMs = started;
            this.durationMs = duration;
            this.workerUid = workerUid;
            this.status = status;
            this.output = output;
            this.error = error;
            this.firstReturn = firstReturn;
        }
    }

    public static Session execute(Context context, String source, int timeoutMs,
            Callback callback) {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(callback, "callback");
        if (source == null || source.length() > LaboratorySandboxService.MAX_SOURCE_CHARS
                || timeoutMs < 1 || timeoutMs > LaboratorySandboxService.MAX_TIMEOUT_MS) {
            throw new IllegalArgumentException("sandbox request exceeds limits");
        }
        Session session = new Session(context.getApplicationContext(), source,
            timeoutMs, callback);
        session.main.post(session::start);
        return session;
    }

    private LaboratorySandboxClient() {}

    public static final class Session implements ServiceConnection {
        private final Context context;
        private final String source;
        private final int timeoutMs;
        private final Callback callback;
        private final Handler main = new Handler(Looper.getMainLooper());
        private final String id = UUID.randomUUID().toString();
        private final String hash;
        private final long started = System.currentTimeMillis();
        private final Messenger inbound;
        private Messenger outbound;
        private boolean bound;
        private boolean finished;
        private String stoppingReason;

        private Session(Context context, String source, int timeoutMs, Callback callback) {
            this.context = context;
            this.source = source;
            this.timeoutMs = timeoutMs;
            this.callback = callback;
            this.hash = LaboratoryEngine.fingerprint(source).substring(7, 71);
            this.inbound = new Messenger(new Handler(Looper.getMainLooper(), message -> {
                handleResult(message);
                return true;
            }));
        }

        public String runId() { return id; }

        /** Safe from any thread. Does not depend on model cooperation. */
        public void cancel() { main.post(() -> stop("CANCELLED")); }

        private void start() {
            if (finished || stoppingReason != null) return;
            // Includes service start-up time; does not depend on worker timers.
            main.postDelayed(() -> stop("TIMEOUT"), timeoutMs + 20_000L);
            try {
                Intent intent = new Intent(context, LaboratorySandboxService.class);
                bound = context.bindService(intent, this, Context.BIND_AUTO_CREATE);
                if (!bound) finish("BIND_FAILED", -1, "", "Isolated service unavailable", "");
            } catch (SecurityException error) {
                finish("BIND_FAILED", -1, "", "Isolated service access denied", "");
            }
        }

        @Override
        public void onServiceConnected(ComponentName component, IBinder binder) {
            if (finished || stoppingReason != null) return;
            outbound = new Messenger(binder);
            Bundle data = new Bundle();
            data.putString(LaboratorySandboxService.RUN_ID, id);
            data.putString(LaboratorySandboxService.SOURCE, source);
            data.putInt(LaboratorySandboxService.TIMEOUT_MS, timeoutMs);
            Message message = Message.obtain(null, LaboratorySandboxService.RUN);
            message.setData(data);
            message.replyTo = inbound;
            try {
                outbound.send(message);
            } catch (RemoteException error) {
                finish("PROCESS_DIED", -1, "", "Isolated service disconnected", "");
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName component) {
            finish(stoppingReason != null ? stoppingReason : "PROCESS_DIED",
                -1, "", "Isolated worker exited", "");
        }

        @Override
        public void onBindingDied(ComponentName component) {
            finish(stoppingReason != null ? stoppingReason : "PROCESS_DIED",
                -1, "", "Isolated binding died", "");
        }

        @Override
        public void onNullBinding(ComponentName component) {
            finish("BIND_FAILED", -1, "", "Isolated worker refused binding", "");
        }

        private void handleResult(Message message) {
            if (message.what != LaboratorySandboxService.RESULT
                    || finished || stoppingReason != null) return;
            Bundle data = message.getData();
            if (!id.equals(data.getString(LaboratorySandboxService.RUN_ID))) return;
            int workerUid = data.getInt(LaboratorySandboxService.WORKER_UID, -1);
            if (workerUid < 0 || workerUid == Process.myUid()) {
                finish("ISOLATION_FAILED", workerUid, "",
                    "Worker does not have a distinct isolated UID", "");
                return;
            }
            String status = data.getString(LaboratorySandboxService.STATUS, "WORKER_ERROR");
            if (!("EXECUTED".equals(status) || "LUAU_ERROR".equals(status)
                    || "WORKER_ERROR".equals(status) || "REJECTED".equals(status))) {
                status = "WORKER_ERROR";
            }
            finish(status, workerUid,
                bounded(data.getString(LaboratorySandboxService.OUTPUT)),
                bounded(data.getString(LaboratorySandboxService.ERROR)),
                bounded(data.getString(LaboratorySandboxService.RETURN_VALUE)));
        }

        private void stop(String reason) {
            if (finished || stoppingReason != null) return;
            stoppingReason = reason;
            if (outbound != null) {
                Message abort = Message.obtain(null, LaboratorySandboxService.ABORT);
                Bundle data = new Bundle();
                data.putString(LaboratorySandboxService.RUN_ID, id);
                abort.setData(data);
                try { outbound.send(abort); } catch (RemoteException ignored) { }
            }
            // Give the isolated main thread time to process ABORT and kill itself.
            main.postDelayed(() -> finish(reason, -1, "", "Isolated run stopped", ""), 250);
        }

        private void finish(String status, int workerUid, String output,
                String error, String firstReturn) {
            if (finished) return;
            finished = true;
            if (bound) {
                context.unbindService(this);
                bound = false;
            }
            Result result = new Result(id, hash, started,
                Math.max(0, System.currentTimeMillis() - started), workerUid,
                status, output, error, firstReturn);
            callback.onFinished(result);
        }

        private static String bounded(String value) {
            if (value == null) return "";
            return value.length() <= LaboratorySandboxService.MAX_RESPONSE_CHARS
                ? value : value.substring(0, LaboratorySandboxService.MAX_RESPONSE_CHARS);
        }
    }
}
