#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace cafeina {

struct RuntimeLimits {
    std::uint32_t timeoutMs = 250;
};

struct RuntimeHostAccess {
    // Empty means no host filesystem API is exposed to Luau.
    // When set, scripts are restricted to flat files inside this directory.
    std::string filesRoot;
};

enum class RuntimeCapability : std::uint64_t {
    Files = 1ull << 0,
};

struct RuntimeCapabilities {
    std::uint64_t bits = 0;

    bool has(RuntimeCapability capability) const
    {
        return (bits & static_cast<std::uint64_t>(capability)) != 0;
    }

    void grant(RuntimeCapability capability)
    {
        bits |= static_cast<std::uint64_t>(capability);
    }

    void revoke(RuntimeCapability capability)
    {
        bits &= ~static_cast<std::uint64_t>(capability);
    }
};

// Host-owned metadata and access granted to one execution.
// Capabilities are explicit: host access alone does not expose an API.
struct ExecutionContext {
    // Opaque identifiers for diagnostics, task tracking and future recovery.
    // Empty values are valid for legacy callers.
    std::string executionId;
    std::string projectId;

    RuntimeCapabilities capabilities;
    RuntimeHostAccess hostAccess;
};

// Canonical request shape for the runtime platform.
// Legacy execute(source, limits, hostAccess) remains available as a wrapper.
struct ExecutionRequest {
    std::string source;
    RuntimeLimits limits;
    ExecutionContext context;
};

struct RuntimeResult {
    bool ok = false;
    std::string output;
    std::string error;
    std::vector<std::string> returns;
    std::uint64_t elapsedMs = 0;
};

// Forward-looking semantic name while preserving the existing RuntimeResult API.
using ExecutionResult = RuntimeResult;

class LuauRuntime {
public:
    LuauRuntime();
    ~LuauRuntime();

    LuauRuntime(const LuauRuntime&) = delete;
    LuauRuntime& operator=(const LuauRuntime&) = delete;

    RuntimeResult execute(const ExecutionRequest& request);

    RuntimeResult execute(
        const std::string& source,
        const RuntimeLimits& limits = {},
        const RuntimeHostAccess& hostAccess = {}
    );

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

} // namespace cafeina
