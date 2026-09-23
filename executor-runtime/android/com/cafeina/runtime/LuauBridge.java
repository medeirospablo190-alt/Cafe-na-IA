package com.cafeina.runtime;

public final class LuauBridge {
    static {
        System.loadLibrary("cafeina_luau_jni");
    }

    private LuauBridge() {}

    public static native String nativeExecute(String source, int timeoutMs);

    public static native String nativeExecuteWithFiles(
        String source,
        int timeoutMs,
        String sandboxRoot
    );
}
