#include "llama.h"

#include <jni.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

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

void throwIOException(JNIEnv* env, const char* message)
{
    jclass type = env->FindClass("java/io/IOException");
    if (type)
        env->ThrowNew(type, message);
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
    jstring promptValue,
    jint maxTokens,
    jint maxOutputChars,
    jint contextTokens,
    jint threads,
    jint topK,
    jfloat topP,
    jfloat temperature,
    jlong seed
)
{
    ModelSession* session = requireSession(handle);
    if (!session || !session->model)
    {
        throwIOException(env, "local model session is unavailable");
        return nullptr;
    }

    const std::string prompt = fromJString(env, promptValue);
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
            || temperature < 0.0f || temperature > 2.0f)
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

    llama_context* context =
        llama_init_from_model(session->model, params);
    if (!context)
    {
        throwIOException(env, "local model context could not be created");
        return nullptr;
    }

    llama_batch_ext* batch = llama_batch_ext_init(context);
    if (!batch)
    {
        llama_free(context);
        throwIOException(env, "local model batch could not be created");
        return nullptr;
    }

    llama_sampler* sampler = llama_sampler_chain_init(
        llama_sampler_chain_default_params());
    if (!sampler)
    {
        llama_batch_ext_free(batch);
        llama_free(context);
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
        ++position;
    }

    llama_sampler_free(sampler);
    llama_batch_ext_free(batch);
    llama_free(context);

    if (!ok)
    {
        throwIOException(env, "local model generation failed");
        return nullptr;
    }
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
