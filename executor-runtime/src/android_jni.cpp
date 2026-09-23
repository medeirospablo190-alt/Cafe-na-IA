#include "cafeina/LuauRuntime.hpp"
#include "cafeina/render/RenderScene.hpp"

#include <jni.h>

#include <exception>
#include <string>

namespace {

cafeina::world::WorldService& sharedWorld()
{
    static cafeina::world::WorldService service;
    return service;
}

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

jstring toJString(JNIEnv* env, const std::string& value)
{
    return env->NewStringUTF(value.c_str());
}

jstring executeLegacyToJson(
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

    return toJString(env, toJson(runtime.execute(code, limits, hostAccess)));
}

jstring executeWithSharedWorldToJson(
    JNIEnv* env,
    jstring source,
    jint timeoutMs,
    jstring sandboxRoot
)
{
    cafeina::ExecutionRequest request;
    request.source = fromJString(env, source);
    request.limits.timeoutMs =
        timeoutMs > 0 ? static_cast<std::uint32_t>(timeoutMs) : 250;

    request.context.hostAccess.filesRoot = fromJString(env, sandboxRoot);
    request.context.hostAccess.worldService = &sharedWorld();

    if (!request.context.hostAccess.filesRoot.empty())
        request.context.capabilities.grant(cafeina::RuntimeCapability::Files);

    request.context.capabilities.grant(cafeina::RuntimeCapability::World);

    cafeina::LuauRuntime runtime;
    return toJString(env, toJson(runtime.execute(request)));
}

const char* primitiveName(cafeina::world::PrimitiveMesh primitive)
{
    switch (primitive)
    {
    case cafeina::world::PrimitiveMesh::Box:
        return "box";
    case cafeina::world::PrimitiveMesh::Sphere:
        return "sphere";
    case cafeina::world::PrimitiveMesh::Cylinder:
        return "cylinder";
    case cafeina::world::PrimitiveMesh::Plane:
        return "plane";
    }

    return "unknown";
}

void appendVec3(std::string& out, const cafeina::world::Vec3& value)
{
    out += '[';
    out += std::to_string(value.x);
    out += ',';
    out += std::to_string(value.y);
    out += ',';
    out += std::to_string(value.z);
    out += ']';
}

std::string renderSceneSnapshotJson()
{
    try
    {
        const cafeina::render::RenderScene scene =
            cafeina::render::RenderSceneBuilder::build(sharedWorld().state());

        std::string out = "{\"ok\":true,\"items\":[";
        for (size_t i = 0; i < scene.items.size(); ++i)
        {
            if (i)
                out += ',';

            const cafeina::render::RenderItem& item = scene.items[i];

            out += "{\"id\":\"";
            out += std::to_string(item.objectId);
            out += "\",\"primitive\":\"";
            out += primitiveName(item.primitive);
            out += "\",\"position\":";
            appendVec3(out, item.transform.position);
            out += ",\"rotationDegrees\":";
            appendVec3(out, item.transform.rotationDegrees);
            out += ",\"scale\":";
            appendVec3(out, item.transform.scale);
            out += '}';
        }
        out += "]}";
        return out;
    }
    catch (const std::exception& error)
    {
        return "{\"ok\":false,\"error\":\"" + jsonEscape(error.what()) + "\",\"items\":[]}";
    }
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LuauBridge_nativeExecute(
    JNIEnv* env,
    jclass,
    jstring source,
    jint timeoutMs
)
{
    return executeLegacyToJson(env, source, timeoutMs, {});
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
    return executeLegacyToJson(env, source, timeoutMs, hostAccess);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LuauBridge_nativeExecuteWithFilesAndWorld(
    JNIEnv* env,
    jclass,
    jstring source,
    jint timeoutMs,
    jstring sandboxRoot
)
{
    return executeWithSharedWorldToJson(env, source, timeoutMs, sandboxRoot);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LuauBridge_nativeRenderSceneSnapshot(
    JNIEnv* env,
    jclass
)
{
    return toJString(env, renderSceneSnapshotJson());
}

extern "C" JNIEXPORT void JNICALL
Java_com_cafeina_runtime_LuauBridge_nativeResetWorld(
    JNIEnv*,
    jclass
)
{
    sharedWorld().clear();
}
