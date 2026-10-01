#include "llama.h"

#include <jni.h>

#include <mutex>
#include <string>
#include <unordered_set>

namespace {

struct ModelSession
{
    llama_model* model = nullptr;
};

std::once_flag backendInit;
std::mutex sessionsMutex;
std::unordered_set<ModelSession*> sessions;

void ensureBackend()
{
    std::call_once(backendInit, [] {
        llama_backend_init();
    });
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

ModelSession* requireSession(jlong handle)
{
    if (handle == 0)
        return nullptr;

    auto* session = reinterpret_cast<ModelSession*>(handle);
    std::lock_guard<std::mutex> guard(sessionsMutex);
    return sessions.count(session) == 1 ? session : nullptr;
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeVersion(
    JNIEnv* env,
    jclass
)
{
    ensureBackend();
    return env->NewStringUTF(llama_version());
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeOpen(
    JNIEnv* env,
    jclass,
    jstring modelPath
)
{
    const std::string path = fromJString(env, modelPath);
    if (path.empty())
        return 0;

    ensureBackend();

    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;

    llama_model* model = llama_model_load_from_file(path.c_str(), params);
    if (!model)
        return 0;

    auto* session = new ModelSession();
    session->model = model;
    {
        std::lock_guard<std::mutex> guard(sessionsMutex);
        sessions.insert(session);
    }
    return reinterpret_cast<jlong>(session);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeDescription(
    JNIEnv* env,
    jclass,
    jlong handle
)
{
    ModelSession* session = requireSession(handle);
    if (!session || !session->model)
        return nullptr;

    char description[256] = {};
    const int32_t length = llama_model_desc(
        session->model,
        description,
        sizeof(description));
    if (length < 0)
        return nullptr;
    return env->NewStringUTF(description);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeModelSizeBytes(
    JNIEnv*,
    jclass,
    jlong handle
)
{
    ModelSession* session = requireSession(handle);
    if (!session || !session->model)
        return -1;
    return static_cast<jlong>(llama_model_size(session->model));
}

extern "C" JNIEXPORT void JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeClose(
    JNIEnv*,
    jclass,
    jlong handle
)
{
    if (handle == 0)
        return;

    auto* session = reinterpret_cast<ModelSession*>(handle);
    {
        std::lock_guard<std::mutex> guard(sessionsMutex);
        auto it = sessions.find(session);
        if (it == sessions.end())
            return;
        sessions.erase(it);
    }

    llama_model_free(session->model);
    session->model = nullptr;
    delete session;
}
