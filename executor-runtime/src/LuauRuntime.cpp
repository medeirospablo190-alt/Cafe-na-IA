#include "cafeina/LuauRuntime.hpp"
#include "WorldLuauApi.hpp"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <string>
#include <system_error>
#include <vector>

#include "lua.h"
#include "lualib.h"
#include "luacode.h"

namespace cafeina {
namespace {

using Clock = std::chrono::steady_clock;
namespace fs = std::filesystem;

constexpr std::size_t kMaxRuntimeFileBytes = 1024 * 1024;
constexpr std::size_t kMaxRuntimeFileNameBytes = 120;
constexpr int kMaxRuntimeFilesListed = 128;

struct VmExecutionContext {
    Clock::time_point deadline;
    std::string* output = nullptr;
    std::string filesRoot;
    const CancellationToken* cancellation = nullptr;
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

VmExecutionContext* executionContext(lua_State* L)
{
    return static_cast<VmExecutionContext*>(lua_getthreaddata(L));
}

int capturePrint(lua_State* L)
{
    auto* ctx = executionContext(L);
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

    auto* ctx = executionContext(L);
    if (!ctx)
        return;

    if (ctx->cancellation && ctx->cancellation->isCancellationRequested())
    {
        lua_checkstack(L, 1);
        luaL_error(L, "execution cancelled");
    }

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

bool validRuntimeFileName(const std::string& name)
{
    if (name.empty() || name.size() > kMaxRuntimeFileNameBytes)
        return false;
    if (name == "." || name == ".." || name.front() == '.')
        return false;
    if (name.find("..") != std::string::npos)
        return false;
    if (name.find('/') != std::string::npos || name.find('\\') != std::string::npos)
        return false;

    for (unsigned char c : name)
    {
        if (std::iscntrl(c))
            return false;
    }

    return true;
}

std::string checkedRuntimeFileName(lua_State* L, int index)
{
    size_t length = 0;
    const char* raw = luaL_checklstring(L, index, &length);
    std::string name(raw, length);

    if (!validRuntimeFileName(name))
        luaL_error(L, "invalid runtime file name");

    return name;
}

fs::path checkedFilesystemRoot(lua_State* L)
{
    auto* ctx = executionContext(L);
    if (!ctx || ctx->filesRoot.empty())
        luaL_error(L, "filesystem API is not enabled");

    fs::path root(ctx->filesRoot);
    std::error_code ec;
    fs::create_directories(root, ec);
    if (ec)
        luaL_error(L, "failed to create filesystem sandbox: %s", ec.message().c_str());

    const fs::file_status status = fs::symlink_status(root, ec);
    if (ec || !fs::is_directory(status) || fs::is_symlink(status))
        luaL_error(L, "filesystem sandbox root is invalid");

    return root;
}

fs::path checkedTargetPath(lua_State* L, const fs::path& root, const std::string& name)
{
    fs::path target = root / name;

    std::error_code ec;
    const fs::file_status status = fs::symlink_status(target, ec);
    if (!ec && fs::is_symlink(status))
        luaL_error(L, "symbolic links are not allowed in filesystem sandbox");

    return target;
}

int fsWrite(lua_State* L)
{
    const std::string name = checkedRuntimeFileName(L, 1);

    size_t contentLength = 0;
    const char* content = luaL_checklstring(L, 2, &contentLength);
    if (contentLength > kMaxRuntimeFileBytes)
        luaL_error(L, "runtime file exceeds %d bytes", int(kMaxRuntimeFileBytes));

    const fs::path root = checkedFilesystemRoot(L);
    const fs::path target = checkedTargetPath(L, root, name);

    const auto stamp = Clock::now().time_since_epoch().count();
    const fs::path temp = root / ("." + name + ".tmp-" + std::to_string(stamp));

    {
        std::ofstream output(temp, std::ios::binary | std::ios::trunc);
        if (!output)
            luaL_error(L, "failed to open temporary runtime file");

        output.write(content, static_cast<std::streamsize>(contentLength));
        output.flush();

        if (!output)
        {
            output.close();
            std::error_code cleanup;
            fs::remove(temp, cleanup);
            luaL_error(L, "failed to write runtime file");
        }
    }

    std::error_code ec;
    fs::rename(temp, target, ec);

    if (ec)
    {
        // Some platforms do not replace an existing file during rename.
        // Keep the temp file in the same sandbox and fall back conservatively.
        std::error_code removeError;
        fs::remove(target, removeError);
        ec.clear();
        fs::rename(temp, target, ec);
    }

    if (ec)
    {
        std::error_code cleanup;
        fs::remove(temp, cleanup);
        luaL_error(L, "failed to commit runtime file: %s", ec.message().c_str());
    }

    lua_pushboolean(L, 1);
    return 1;
}

int fsRead(lua_State* L)
{
    const std::string name = checkedRuntimeFileName(L, 1);
    const fs::path root = checkedFilesystemRoot(L);
    const fs::path target = checkedTargetPath(L, root, name);

    std::error_code ec;
    const fs::file_status status = fs::symlink_status(target, ec);
    if (ec || !fs::is_regular_file(status) || fs::is_symlink(status))
        luaL_error(L, "runtime file not found");

    const std::uintmax_t fileSize = fs::file_size(target, ec);
    if (ec)
        luaL_error(L, "failed to inspect runtime file");
    if (fileSize > kMaxRuntimeFileBytes)
        luaL_error(L, "runtime file exceeds %d bytes", int(kMaxRuntimeFileBytes));

    std::ifstream input(target, std::ios::binary);
    if (!input)
        luaL_error(L, "failed to open runtime file");

    std::string content(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>()
    );

    if (!input.eof() && input.fail())
        luaL_error(L, "failed to read runtime file");

    lua_pushlstring(L, content.data(), content.size());
    return 1;
}

int fsExists(lua_State* L)
{
    const std::string name = checkedRuntimeFileName(L, 1);
    const fs::path root = checkedFilesystemRoot(L);
    const fs::path target = checkedTargetPath(L, root, name);

    std::error_code ec;
    const fs::file_status status = fs::symlink_status(target, ec);
    const bool exists = !ec && fs::is_regular_file(status) && !fs::is_symlink(status);

    lua_pushboolean(L, exists ? 1 : 0);
    return 1;
}

int fsList(lua_State* L)
{
    const fs::path root = checkedFilesystemRoot(L);

    std::vector<std::string> names;
    std::error_code ec;
    fs::directory_iterator it(root, ec);
    fs::directory_iterator end;

    while (!ec && it != end && int(names.size()) < kMaxRuntimeFilesListed)
    {
        const fs::directory_entry& entry = *it;
        std::error_code statusError;
        const fs::file_status status = entry.symlink_status(statusError);

        if (!statusError && fs::is_regular_file(status) && !fs::is_symlink(status))
        {
            const std::string name = entry.path().filename().string();
            if (validRuntimeFileName(name))
                names.push_back(name);
        }

        it.increment(ec);
    }

    if (ec)
        luaL_error(L, "failed to list filesystem sandbox: %s", ec.message().c_str());

    std::sort(names.begin(), names.end());

    lua_createtable(L, static_cast<int>(names.size()), 0);
    for (size_t i = 0; i < names.size(); ++i)
    {
        lua_pushlstring(L, names[i].data(), names[i].size());
        lua_rawseti(L, -2, static_cast<int>(i + 1));
    }

    return 1;
}

void exposeFilesystemApi(lua_State* L)
{
    lua_createtable(L, 0, 4);

    lua_pushcfunction(L, fsWrite, "fs.write");
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, fsRead, "fs.read");
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, fsExists, "fs.exists");
    lua_setfield(L, -2, "exists");

    lua_pushcfunction(L, fsList, "fs.list");
    lua_setfield(L, -2, "list");

    lua_setreadonly(L, -1, true);
    lua_setglobal(L, "fs");
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

RuntimeResult LuauRuntime::execute(const ExecutionRequest& request)
{
    RuntimeResult result;
    const auto started = Clock::now();
    const std::shared_ptr<CancellationToken> cancellation = request.context.cancellation;

    if (cancellation && cancellation->isCancellationRequested())
    {
        result.error = "execution cancelled";
        return result;
    }

    const bool filesEnabled = request.context.capabilities.has(RuntimeCapability::Files);
    if (filesEnabled && request.context.hostAccess.filesRoot.empty())
    {
        result.error = "FILES capability requires a filesystem sandbox root";
        return result;
    }

    const bool worldEnabled = request.context.capabilities.has(RuntimeCapability::World);
    if (worldEnabled && !request.context.hostAccess.worldService)
    {
        result.error = "WORLD capability requires a WorldService";
        return result;
    }

    if (!impl_ || !impl_->global)
    {
        result.error = "failed to initialize Luau VM";
        return result;
    }

    lua_State* thread = lua_newthread(impl_->global);
    const int threadRef = lua_ref(impl_->global, -1);
    lua_pop(impl_->global, 1);

    luaL_sandboxthread(thread);

    VmExecutionContext ctx;
    ctx.deadline = started + std::chrono::milliseconds(request.limits.timeoutMs);
    ctx.output = &result.output;
    if (filesEnabled)
        ctx.filesRoot = request.context.hostAccess.filesRoot;
    ctx.cancellation = cancellation.get();
    lua_setthreaddata(thread, &ctx);

    lua_pushcfunction(thread, capturePrint, "print");
    lua_setglobal(thread, "print");
    lua_pushcfunction(thread, capturePrint, "warn");
    lua_setglobal(thread, "warn");

    if (!ctx.filesRoot.empty())
        exposeFilesystemApi(thread);
    if (worldEnabled)
        exposeWorldApi(thread, request.context.hostAccess.worldService);

    size_t bytecodeSize = 0;
    char* bytecodeRaw = luau_compile(request.source.data(), request.source.size(), nullptr, &bytecodeSize);
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


RuntimeResult LuauRuntime::execute(
    const std::string& source,
    const RuntimeLimits& limits,
    const RuntimeHostAccess& hostAccess
)
{
    ExecutionRequest request;
    request.source = source;
    request.limits = limits;
    request.context.hostAccess = hostAccess;

    // Preserve Phase 8 behavior for existing JNI/app callers: providing a
    // legacy filesRoot explicitly grants only the FILES capability.
    if (!hostAccess.filesRoot.empty())
        request.context.capabilities.grant(RuntimeCapability::Files);

    return execute(request);
}

} // namespace cafeina
