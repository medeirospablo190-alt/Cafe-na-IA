#include "cafeina/LuauRuntime.hpp"

#include <chrono>
#include <cstdlib>
#include <memory>
#include <string>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "luacode.h"
}

namespace cafeina {
namespace {

using Clock = std::chrono::steady_clock;

struct ExecutionContext {
    Clock::time_point deadline;
    std::string* output = nullptr;
};

std::string stackValueToString(lua_State* L, int index)
{
    size_t length = 0;
    const char* value = luaL_tolstring(L, index, &length);
    if (!value)
        return "<unprintable>";

    std::string out(value, length);
    lua_pop(L, 1);
    return out;
}

int capturePrint(lua_State* L)
{
    auto* ctx = static_cast<ExecutionContext*>(lua_getthreaddata(L));
    if (!ctx || !ctx->output)
        return 0;

    const int count = lua_gettop(L);
    for (int i = 1; i <= count; ++i)
    {
        if (i > 1)
            ctx->output->append("\t");
        ctx->output->append(stackValueToString(L, i));
    }
    ctx->output->append("\n");
    return 0;
}

void timeoutInterrupt(lua_State* L, int gc)
{
    if (gc >= 0)
        return;

    auto* ctx = static_cast<ExecutionContext*>(lua_getthreaddata(L));
    if (!ctx)
        return;

    if (Clock::now() > ctx->deadline)
    {
        lua_checkstack(L, 1);
        luaL_error(L, "execution timed out");
    }
}

std::string currentError(lua_State* L)
{
    const char* err = lua_tostring(L, -1);
    return err ? std::string(err) : std::string("unknown Luau error");
}

} // namespace

struct LuauRuntime::Impl {
    lua_State* global = nullptr;

    Impl()
    {
        global = luaL_newstate();
        if (!global)
            return;

        luaL_openlibs(global);
        luaL_sandbox(global);
        lua_callbacks(global)->interrupt = timeoutInterrupt;
    }

    ~Impl()
    {
        if (global)
            lua_close(global);
    }
};

LuauRuntime::LuauRuntime()
    : impl_(new Impl())
{
}

LuauRuntime::~LuauRuntime()
{
    delete impl_;
}

RuntimeResult LuauRuntime::execute(const std::string& source, const RuntimeLimits& limits)
{
    RuntimeResult result;
    const auto started = Clock::now();

    if (!impl_ || !impl_->global)
    {
        result.error = "failed to initialize Luau VM";
        return result;
    }

    lua_State* thread = lua_newthread(impl_->global);
    const int threadRef = lua_ref(impl_->global, -1);
    lua_pop(impl_->global, 1);

    luaL_sandboxthread(thread);

    ExecutionContext ctx;
    ctx.deadline = started + std::chrono::milliseconds(limits.timeoutMs);
    ctx.output = &result.output;
    lua_setthreaddata(thread, &ctx);

    lua_pushcfunction(thread, capturePrint, "print");
    lua_setglobal(thread, "print");
    lua_pushcfunction(thread, capturePrint, "warn");
    lua_setglobal(thread, "warn");

    size_t bytecodeSize = 0;
    char* bytecodeRaw = luau_compile(source.data(), source.size(), nullptr, &bytecodeSize);
    std::unique_ptr<char, decltype(&std::free)> bytecode(bytecodeRaw, &std::free);

    if (!bytecode)
    {
        result.error = "Luau compiler returned no bytecode";
        lua_unref(impl_->global, threadRef);
        return result;
    }

    const int loadStatus = luau_load(thread, "=cafeina", bytecode.get(), bytecodeSize, 0);
    if (loadStatus != 0)
    {
        result.error = currentError(thread);
        result.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started).count();
        lua_unref(impl_->global, threadRef);
        return result;
    }

    const int status = lua_resume(thread, nullptr, 0);
    result.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started).count();

    if (status != 0)
    {
        result.error = currentError(thread);
        lua_unref(impl_->global, threadRef);
        return result;
    }

    const int returnCount = lua_gettop(thread);
    result.returns.reserve(returnCount);
    for (int i = 1; i <= returnCount; ++i)
        result.returns.push_back(stackValueToString(thread, i));

    result.ok = true;
    lua_unref(impl_->global, threadRef);
    return result;
}

} // namespace cafeina
