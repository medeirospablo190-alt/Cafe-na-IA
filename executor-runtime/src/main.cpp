#include "cafeina/LuauRuntime.hpp"

#include <iostream>
#include <iterator>
#include <string>

int main(int argc, char** argv)
{
    std::string source;
    if (argc > 1)
        source = argv[1];
    else
        source.assign(std::istreambuf_iterator<char>(std::cin), std::istreambuf_iterator<char>());

    cafeina::LuauRuntime runtime;
    cafeina::RuntimeLimits limits;
    limits.timeoutMs = 500;

    const cafeina::RuntimeResult result = runtime.execute(source, limits);

    if (!result.output.empty())
        std::cout << result.output;

    if (!result.ok)
    {
        std::cerr << result.error << "\n";
        return 1;
    }

    if (!result.returns.empty())
    {
        std::cout << "returns:";
        for (const std::string& value : result.returns)
            std::cout << " [" << value << "]";
        std::cout << "\n";
    }

    return 0;
}
