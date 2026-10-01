package com.cafeina.runtime;

import java.io.File;
import java.io.IOException;

/**
 * Experimental app-private bridge to the pinned llama.cpp runtime.
 *
 * This bridge owns model lifetime only. It has no access to Laboratory AI
 * execution handles, permissions, Goal Lock state, or tool APIs.
 */
public final class LlamaBridge {
    static {
        System.loadLibrary("cafeina_llama_jni");
    }

    private LlamaBridge() {}

    public static String version() {
        return nativeVersion();
    }

    public static Session open(File modelFile) throws IOException {
        if (modelFile == null
                || !modelFile.isFile()
                || !modelFile.canRead()) {
            throw new IOException("local model file is missing or unreadable");
        }
        long handle = nativeOpen(modelFile.getAbsolutePath());
        if (handle == 0L) {
            throw new IOException("llama.cpp could not load local model");
        }
        return new Session(handle);
    }

    public static final class Session implements AutoCloseable {
        private long handle;

        private Session(long handle) {
            this.handle = handle;
        }

        public synchronized String description() throws IOException {
            ensureOpen();
            String value = nativeDescription(handle);
            if (value == null || value.isEmpty()) {
                throw new IOException("local model description unavailable");
            }
            return value;
        }

        public synchronized long modelSizeBytes() throws IOException {
            ensureOpen();
            long value = nativeModelSizeBytes(handle);
            if (value < 0L) {
                throw new IOException("local model size unavailable");
            }
            return value;
        }

        public synchronized boolean isOpen() {
            return handle != 0L;
        }

        @Override
        public synchronized void close() {
            if (handle == 0L) return;
            nativeClose(handle);
            handle = 0L;
        }

        private void ensureOpen() throws IOException {
            if (handle == 0L) {
                throw new IOException("local model session is closed");
            }
        }
    }

    private static native String nativeVersion();
    private static native long nativeOpen(String modelPath);
    private static native String nativeDescription(long handle);
    private static native long nativeModelSizeBytes(long handle);
    private static native void nativeClose(long handle);
}
