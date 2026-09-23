#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace cafeina {

struct RuntimeLimits {
    std::uint32_t timeoutMs = 250;
};

struct RuntimeResult {
    bool ok = false;
    std::string output;
    std::string error;
    std::vector<std::string> returns;
    std::uint64_t elapsedMs = 0;
};

class LuauRuntime {
public:
    LuauRuntime();
    ~LuauRuntime();

    LuauRuntime(const LuauRuntime&) = delete;
    LuauRuntime& operator=(const LuauRuntime&) = delete;

    RuntimeResult execute(const std::string& source, const RuntimeLimits& limits = {});

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

} // namespace cafeina
