#include "cafeina/LuauRuntime.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

void require(bool condition, const char* message)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << message << "\n";
        std::exit(1);
    }
}

} // namespace

int main()
{
    cafeina::LuauRuntime runtime;

    {
        const auto r = runtime.execute("print('hello', 42) return 2 + 3", {250});
        require(r.ok, "basic script should succeed");
        require(r.output == "hello\t42\n", "print should be captured");
        require(r.returns.size() == 1 && r.returns[0] == "5", "return value should be captured");
    }

    {
        const auto r = runtime.execute("local =", {250});
        require(!r.ok, "syntax error should fail");
        require(!r.error.empty(), "syntax error should have a message");
    }

    {
        const auto r = runtime.execute("error('boom')", {250});
        require(!r.ok, "runtime error should fail");
        require(r.error.find("boom") != std::string::npos, "runtime error should contain message");
    }

    {
        const auto r = runtime.execute("while true do end", {40});
        require(!r.ok, "infinite loop should be interrupted");
        require(r.error.find("timed out") != std::string::npos, "timeout should be reported");
    }

    std::cout << "runtime smoke tests passed\n";
    return 0;
}
