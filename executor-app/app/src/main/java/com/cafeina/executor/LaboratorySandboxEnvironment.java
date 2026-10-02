package com.cafeina.executor;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Build;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Locale;

/**
 * Privacy-safe identity of the isolated candidate execution harness.
 *
 * It intentionally excludes device model, serials, account data, paths and
 * user content. The hash changes when the app build, Android SDK, ABI set or
 * sandbox protocol limits change.
 */
public final class LaboratorySandboxEnvironment {
    private static final String PROTOCOL = "CAFEINA_ISOLATED_LUAU_V1";

    private LaboratorySandboxEnvironment() {}

    public static String fingerprint(Context context) {
        if (context == null) {
            throw new IllegalArgumentException(
                "sandbox environment context missing");
        }

        Context app = context.getApplicationContext();
        String versionName = "";
        long versionCode = 0L;
        try {
            PackageInfo info = app.getPackageManager()
                .getPackageInfo(app.getPackageName(), 0);
            versionName =
                info.versionName == null ? "" : info.versionName;
            if (Build.VERSION.SDK_INT >= 28) {
                versionCode = info.getLongVersionCode();
            } else {
                versionCode = info.versionCode;
            }
        } catch (Exception ignored) {
            // Empty app-version metadata remains deterministic for this build
            // and does not expose user data.
        }

        String identity =
            PROTOCOL
                + "|pkg=" + app.getPackageName()
                + "|versionName=" + versionName
                + "|versionCode=" + versionCode
                + "|sdk=" + Build.VERSION.SDK_INT
                + "|abis=" + Arrays.toString(Build.SUPPORTED_ABIS)
                + "|maxSource="
                + LaboratorySandboxService.MAX_SOURCE_CHARS
                + "|maxInput="
                + LaboratorySandboxService.MAX_INPUT_CHARS
                + "|maxResponse="
                + LaboratorySandboxService.MAX_RESPONSE_CHARS
                + "|maxTimeout="
                + LaboratorySandboxService.MAX_TIMEOUT_MS;
        return sha256(identity.getBytes(StandardCharsets.UTF_8));
    }

    private static String sha256(byte[] bytes) {
        try {
            MessageDigest digest =
                MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(bytes);
            StringBuilder out =
                new StringBuilder(hash.length * 2);
            for (byte value : hash) {
                out.append(
                    String.format(
                        Locale.ROOT,
                        "%02x",
                        value & 0xff));
            }
            return out.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(
                "SHA-256 unavailable",
                impossible);
        }
    }
}
