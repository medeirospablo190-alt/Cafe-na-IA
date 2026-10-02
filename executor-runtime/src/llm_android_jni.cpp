#include "llama.h"

#include <jni.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace {

enum GenerationPhase
{
    PHASE_NONE = 0,
    PHASE_CONTEXT = 1,
    PHASE_PROMPT = 2,
    PHASE_TOKENS = 3
};

struct ModelSession
{
    llama_model* model = nullptr;
    std::atomic<bool> cancelRequested{false};
    std::atomic<bool> timedOut{false};
    std::atomic<int64_t> deadlineNanos{0};
    std::atomic<int> phase{PHASE_NONE};
    std::atomic<int32_t> promptTokens{0};
    std::atomic<int32_t> promptTokensProcessed{0};
    std::atomic<int32_t> generatedTokens{0};
    std::atomic<int32_t> maxGeneratedTokens{0};
    std::atomic<int64_t> contextSetupNanos{0};
    std::atomic<int64_t> promptEvalNanos{0};
    std::atomic<int64_t> tokenGenerationNanos{0};
    std::atomic<int64_t> generationTimeLimitMs{0};
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


int64_t monotonicNanos()
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

bool shouldAbort(ModelSession* session)
{
    if (!session)
        return true;
    if (session->cancelRequested.load())
        return true;

    const int64_t deadline = session->deadlineNanos.load();
    if (deadline > 0 && monotonicNanos() >= deadline)
    {
        session->timedOut.store(true);
        return true;
    }
    return false;
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

std::string fromJByteArray(JNIEnv* env, jbyteArray value)
{
    if (!value)
        return {};

    const jsize size = env->GetArrayLength(value);
    if (size <= 0)
        return {};

    std::string out(static_cast<size_t>(size), '\0');
    env->GetByteArrayRegion(
        value,
        0,
        size,
        reinterpret_cast<jbyte*>(&out[0]));
    if (env->ExceptionCheck())
        return {};
    return out;
}

void throwIOException(JNIEnv* env, const char* message)
{
    jclass type = env->FindClass("java/io/IOException");
    if (type)
        env->ThrowNew(type, message);
}

const char* timeoutMessage(const ModelSession* session)
{
    if (!session)
        return "local model generation timed out";
    switch (session->phase.load())
    {
        case PHASE_CONTEXT:
            return "local model timed out during context setup";
        case PHASE_PROMPT:
            return "local model timed out while processing prompt";
        case PHASE_TOKENS:
            return "local model timed out while generating tokens";
        default:
            return "local model generation timed out";
    }
}

bool setBatchTokens(
    llama_batch_ext* batch,
    const llama_token* tokens,
    int32_t count,
    llama_pos firstPosition,
    bool outputLast
)
{
    llama_batch_ext_clear(batch);
    for (int32_t i = 0; i < count; ++i)
    {
        const int32_t index =
            llama_batch_ext_add_token(batch, 0, tokens[i]);
        if (index < 0)
            return false;

        const llama_pos position = firstPosition + i;
        if (!llama_batch_ext_set_pos(batch, index, &position))
            return false;
    }

    if (outputLast && count > 0)
        llama_batch_ext_set_output_logits(batch, count - 1, true);
    return true;
}

std::string formatUserPrompt(
    llama_model* model,
    const std::string& prompt
)
{
    const char* chatTemplate =
        llama_model_chat_template(model, nullptr);
    if (!chatTemplate || chatTemplate[0] == '\0')
        return prompt;

    llama_chat_message message;
    message.role = "user";
    message.content = prompt.c_str();

    const int32_t required = llama_chat_apply_template(
        chatTemplate,
        &message,
        1,
        true,
        nullptr,
        0);
    if (required <= 0)
        return prompt;

    std::vector<char> buffer(static_cast<size_t>(required) + 1U);
    const int32_t written = llama_chat_apply_template(
        chatTemplate,
        &message,
        1,
        true,
        buffer.data(),
        static_cast<int32_t>(buffer.size()));
    if (written <= 0
            || written > static_cast<int32_t>(buffer.size())) {
        return prompt;
    }

    return std::string(
        buffer.data(),
        static_cast<size_t>(written));
}

bool tokenPiece(
    const llama_vocab* vocab,
    llama_token token,
    std::string& piece
)
{
    std::vector<char> buffer(256);
    int32_t size = llama_token_to_piece(
        vocab,
        token,
        buffer.data(),
        static_cast<int32_t>(buffer.size()),
        0,
        true);

    if (size < 0)
    {
        buffer.resize(static_cast<size_t>(-size));
        size = llama_token_to_piece(
            vocab,
            token,
            buffer.data(),
            static_cast<int32_t>(buffer.size()),
            0,
            true);
    }
    if (size < 0)
        return false;

    piece.assign(buffer.data(), static_cast<size_t>(size));
    return true;
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



extern "C" JNIEXPORT jint JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeGenerationPhase(
    JNIEnv*,
    jclass,
    jlong handle
)
{
    if (handle == 0)
        return PHASE_NONE;
    auto* session = reinterpret_cast<ModelSession*>(handle);
    std::lock_guard<std::mutex> guard(sessionsMutex);
    if (sessions.count(session) != 1)
        return PHASE_NONE;
    return static_cast<jint>(session->phase.load());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeGenerationTimedOut(
    JNIEnv*,
    jclass,
    jlong handle
)
{
    if (handle == 0)
        return JNI_FALSE;
    auto* session = reinterpret_cast<ModelSession*>(handle);
    std::lock_guard<std::mutex> guard(sessionsMutex);
    if (sessions.count(session) != 1)
        return JNI_FALSE;
    return session->timedOut.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeGenerationMetrics(
    JNIEnv* env,
    jclass,
    jlong handle
)
{
    jlong values[10] = {};
    if (handle != 0)
    {
        auto* session = reinterpret_cast<ModelSession*>(handle);
        std::lock_guard<std::mutex> guard(sessionsMutex);
        if (sessions.count(session) == 1)
        {
            values[0] = static_cast<jlong>(session->phase.load());
            values[1] = session->timedOut.load() ? 1 : 0;
            values[2] = static_cast<jlong>(session->promptTokens.load());
            values[3] = static_cast<jlong>(
                session->promptTokensProcessed.load());
            values[4] = static_cast<jlong>(session->generatedTokens.load());
            values[5] = static_cast<jlong>(
                session->maxGeneratedTokens.load());
            values[6] = static_cast<jlong>(
                session->contextSetupNanos.load() / 1'000'000LL);
            values[7] = static_cast<jlong>(
                session->promptEvalNanos.load() / 1'000'000LL);
            values[8] = static_cast<jlong>(
                session->tokenGenerationNanos.load() / 1'000'000LL);
            values[9] = static_cast<jlong>(
                session->generationTimeLimitMs.load());
        }
    }

    jlongArray result = env->NewLongArray(10);
    if (!result)
        return nullptr;
    env->SetLongArrayRegion(result, 0, 10, values);
    return result;
}


extern "C" JNIEXPORT void JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeCancelGeneration(
    JNIEnv*,
    jclass,
    jlong handle
)
{
    if (handle == 0)
        return;

    auto* session = reinterpret_cast<ModelSession*>(handle);
    std::lock_guard<std::mutex> guard(sessionsMutex);
    if (sessions.count(session) == 1)
        session->cancelRequested.store(true);
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


extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_cafeina_runtime_LlamaBridge_nativeGenerateBytes(
    JNIEnv* env,
    jclass,
    jlong handle,
    jbyteArray promptUtf8,
    jint maxTokens,
    jint maxOutputChars,
    jint contextTokens,
    jint threads,
    jint topK,
    jfloat topP,
    jfloat temperature,
    jlong seed,
    jlong maxGenerationMs
)
{
    ModelSession* session = nullptr;
    {
        std::lock_guard<std::mutex> guard(sessionsMutex);
        if (handle != 0)
        {
            auto* candidate = reinterpret_cast<ModelSession*>(handle);
            if (sessions.count(candidate) == 1 && candidate->model)
            {
                session = candidate;
                session->cancelRequested.store(false);
                session->timedOut.store(false);
                session->deadlineNanos.store(0);
                session->phase.store(PHASE_NONE);
                session->promptTokens.store(0);
                session->promptTokensProcessed.store(0);
                session->generatedTokens.store(0);
                session->maxGeneratedTokens.store(maxTokens);
                session->contextSetupNanos.store(0);
                session->promptEvalNanos.store(0);
                session->tokenGenerationNanos.store(0);
                session->generationTimeLimitMs.store(maxGenerationMs);
            }
        }
    }
    if (!session)
    {
        throwIOException(env, "local model session is unavailable");
        return nullptr;
    }

    const std::string prompt = fromJByteArray(env, promptUtf8);
    if (prompt.empty())
    {
        throwIOException(env, "local model prompt is empty");
        return nullptr;
    }
    if (maxTokens < 1 || maxTokens > 2048
            || maxOutputChars < 1 || maxOutputChars > 96 * 1024
            || contextTokens < 256 || contextTokens > 8192
            || threads < 1 || threads > 8
            || topK < 0 || topK > 200
            || topP <= 0.0f || topP > 1.0f
            || temperature < 0.0f || temperature > 2.0f
            || maxGenerationMs < 1'000L
            || maxGenerationMs > 5L * 60L * 1'000L)
    {
        throwIOException(env, "invalid local generation limits");
        return nullptr;
    }
    if (llama_model_has_encoder(session->model))
    {
        throwIOException(
            env,
            "encoder models are not supported by local planner generation");
        return nullptr;
    }

    const llama_vocab* vocab = llama_model_get_vocab(session->model);
    if (!vocab)
    {
        throwIOException(env, "local model vocabulary is unavailable");
        return nullptr;
    }

    const std::string formattedPrompt =
        formatUserPrompt(session->model, prompt);

    const int32_t required = -llama_tokenize(
        vocab,
        formattedPrompt.data(),
        static_cast<int32_t>(formattedPrompt.size()),
        nullptr,
        0,
        true,
        true);
    if (required <= 0)
    {
        throwIOException(env, "local model prompt tokenization failed");
        return nullptr;
    }

    std::vector<llama_token> promptTokens(
        static_cast<size_t>(required));
    const int32_t tokenized = llama_tokenize(
        vocab,
        formattedPrompt.data(),
        static_cast<int32_t>(formattedPrompt.size()),
        promptTokens.data(),
        static_cast<int32_t>(promptTokens.size()),
        true,
        true);
    if (tokenized <= 0)
    {
        throwIOException(env, "local model prompt tokenization failed");
        return nullptr;
    }
    promptTokens.resize(static_cast<size_t>(tokenized));
    session->promptTokens.store(tokenized);

    if (tokenized + maxTokens + 1 > contextTokens)
    {
        throwIOException(env, "local model prompt exceeds context budget");
        return nullptr;
    }

    llama_context_params params = llama_context_default_params();
    params.n_ctx = static_cast<uint32_t>(contextTokens);
    params.n_batch = static_cast<uint32_t>(
        std::min(contextTokens, 512));
    params.n_ubatch = params.n_batch;
    params.n_threads = threads;
    params.n_threads_batch = threads;
    params.no_perf = true;
    session->phase.store(PHASE_CONTEXT);
    const int64_t contextStartedNanos = monotonicNanos();
    session->deadlineNanos.store(
        monotonicNanos()
            + static_cast<int64_t>(maxGenerationMs) * 1'000'000LL);
    params.abort_callback = [](void* data) -> bool {
        return shouldAbort(static_cast<ModelSession*>(data));
    };
    params.abort_callback_data = session;

    llama_context* context =
        llama_init_from_model(session->model, params);
    session->contextSetupNanos.store(
        std::max<int64_t>(0, monotonicNanos() - contextStartedNanos));
    if (!context)
    {
        session->deadlineNanos.store(0);
        session->phase.store(PHASE_NONE);
        throwIOException(env, "local model context could not be created");
        return nullptr;
    }
    if (shouldAbort(session))
    {
        const bool timedOut = session->timedOut.load();
        const bool cancelled = session->cancelRequested.load();
        const char* message = timedOut
            ? timeoutMessage(session)
            : (cancelled
                ? "local model generation cancelled"
                : "local model generation failed");
        llama_free(context);
        session->deadlineNanos.store(0);
        session->phase.store(PHASE_NONE);
        throwIOException(env, message);
        return nullptr;
    }

    llama_batch_ext* batch = llama_batch_ext_init(context);
    if (!batch)
    {
        llama_free(context);
        session->deadlineNanos.store(0);
        session->phase.store(PHASE_NONE);
        throwIOException(env, "local model batch could not be created");
        return nullptr;
    }

    llama_sampler* sampler = llama_sampler_chain_init(
        llama_sampler_chain_default_params());
    if (!sampler)
    {
        llama_batch_ext_free(batch);
        llama_free(context);
        session->deadlineNanos.store(0);
        session->phase.store(PHASE_NONE);
        throwIOException(env, "local model sampler could not be created");
        return nullptr;
    }

    if (temperature <= 0.0f)
    {
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_greedy());
    }
    else
    {
        if (topK > 0)
        {
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_top_k(topK));
        }
        if (topP < 1.0f)
        {
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_top_p(topP, 1));
        }
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_dist(
                static_cast<uint32_t>(seed)));
    }

    bool ok = true;
    session->phase.store(PHASE_PROMPT);
    const int64_t promptStartedNanos = monotonicNanos();
    const int32_t batchSize =
        static_cast<int32_t>(params.n_batch);
    for (int32_t offset = 0;
            offset < tokenized && ok;
            offset += batchSize)
    {
        const int32_t count =
            std::min(batchSize, tokenized - offset);
        const bool lastChunk = offset + count == tokenized;
        ok = setBatchTokens(
            batch,
            promptTokens.data() + offset,
            count,
            offset,
            lastChunk);
        if (ok)
            ok = llama_process(
                context,
                LLAMA_PROCESS_TYPE_DECODE,
                batch) == 0;
        session->promptEvalNanos.store(
            std::max<int64_t>(
                0, monotonicNanos() - promptStartedNanos));
        if (ok)
            session->promptTokensProcessed.store(offset + count);
        if (shouldAbort(session))
            ok = false;
    }

    int64_t tokenStartedNanos = 0;
    if (ok)
    {
        session->phase.store(PHASE_TOKENS);
        tokenStartedNanos = monotonicNanos();
    }

    std::string output;
    output.reserve(
        static_cast<size_t>(
            std::min(maxOutputChars, maxTokens * 8)));

    llama_pos position = tokenized;
    for (int32_t generated = 0;
            ok && generated < maxTokens;
            ++generated)
    {
        if (shouldAbort(session))
        {
            ok = false;
            break;
        }

        const llama_token token =
            llama_sampler_sample(sampler, context, -1);
        if (llama_vocab_is_eog(vocab, token))
            break;

        std::string piece;
        if (!tokenPiece(vocab, token, piece))
        {
            ok = false;
            break;
        }
        if (output.size() + piece.size()
                > static_cast<size_t>(maxOutputChars))
            break;
        output += piece;
        session->generatedTokens.store(generated + 1);
        if (tokenStartedNanos > 0)
        {
            session->tokenGenerationNanos.store(
                std::max<int64_t>(
                    0, monotonicNanos() - tokenStartedNanos));
        }

        if (!setBatchTokens(
                batch,
                &token,
                1,
                position,
                true))
        {
            ok = false;
            break;
        }
        if (llama_process(
                context,
                LLAMA_PROCESS_TYPE_DECODE,
                batch) != 0)
        {
            ok = false;
            break;
        }
        if (tokenStartedNanos > 0)
        {
            session->tokenGenerationNanos.store(
                std::max<int64_t>(
                    0, monotonicNanos() - tokenStartedNanos));
        }
        ++position;
    }

    llama_sampler_free(sampler);
    llama_batch_ext_free(batch);
    llama_free(context);

    const int terminalPhase = session->phase.load();
    session->deadlineNanos.store(0);

    if (!ok)
    {
        if (session->timedOut.load())
        {
            session->phase.store(terminalPhase);
            throwIOException(env, timeoutMessage(session));
        }
        else if (session->cancelRequested.load())
            throwIOException(env, "local model generation cancelled");
        else
            throwIOException(env, "local model generation failed");
        session->phase.store(PHASE_NONE);
        return nullptr;
    }
    session->phase.store(PHASE_NONE);
    jbyteArray bytes = env->NewByteArray(
        static_cast<jsize>(output.size()));
    if (!bytes)
        return nullptr;
    if (!output.empty())
    {
        env->SetByteArrayRegion(
            bytes,
            0,
            static_cast<jsize>(output.size()),
            reinterpret_cast<const jbyte*>(output.data()));
    }
    return bytes;
}
