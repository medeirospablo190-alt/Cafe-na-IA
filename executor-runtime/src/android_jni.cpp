#include "cafeina/LuauRuntime.hpp"

#include <jni.h>
#include <string>

namespace {

std::string jsonEscape(const std::string& input)
{
    std::string out;
    out.reserve(input.size() + 16);
    for (unsigned char c : input)
    {
        switch (c)
        {
        case '\\': out += "\\\\"; break;
        case '"': out += "\\\""; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20)
                out += '?';
            else
                out += static_cast<char>(c);
        }
    }
    return out;
}

std::string toJson(const cafeina::RuntimeResult& r)
{
    std::string out = "{\"ok\":";
    out += r.ok ? "true" : "false";
    out += ",\"output\":\"" + jsonEscape(r.output) + "\"";
    out += ",\"error\":\"" + jsonEscape(r.error) + "\"";
    out += ",\"elapsedMs\":" + std::to_string(r.elapsedMs);
    out += ",\"returns\":[";
    for (size_t i = 0; i < r.returns.size(); ++i)
    {
        if (i) out += ',';
        out += "\"" + jsonEscape(r.returns[i]) + "\"";
    }
    out += "]}";
    return out;
}

std::string fromJString(JNIEnv* env, jstring value)
{
    if (!value)
        return {};

    const char* chars = env->GetStringUTFChars(value, nullptr);
    std::string out = chars ? chars : "";
    if (chars)
        env->ReleaseStringUTFChars(value, chars);
    return out;
}

jstring executeToJson(
    JNIEnv* env,
    jstring source,
    jint timeoutMs,
    const cafeina::RuntimeHostAccess& hostAccess
)
{
    const std::string code = fromJString(env, source);

    cafeina::LuauRuntime runtime;
    cafeina::RuntimeLimits limits;
    limits.timeoutMs = timeoutMs > 0 ? static_cast<std::uint32_t>(timeoutMs) : 250;

    const std::string json = toJson(runtime.execute(code, limits, hostAccess));
    return env->NewStringUTF(json.c_str());
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LuauBridge_nativeExecute(JNIEnv* env, jclass, jstring source, jint timeoutMs)
{
    return executeToJson(env, source, timeoutMs, {});
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LuauBridge_nativeExecuteWithFiles(
    JNIEnv* env,
    jclass,
    jstring source,
    jint timeoutMs,
    jstring sandboxRoot
)
{
    cafeina::RuntimeHostAccess hostAccess;
    hostAccess.filesRoot = fromJString(env, sandboxRoot);
    return executeToJson(env, source, timeoutMs, hostAccess);
}
