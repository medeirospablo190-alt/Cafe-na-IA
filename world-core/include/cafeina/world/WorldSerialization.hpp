#pragma once

#include <stdexcept>
#include <string>

#include "cafeina/world/World.hpp"

namespace cafeina::world {

class WorldFormatError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

std::string serializeWorldJson(const World& world);
World deserializeWorldJson(const std::string& jsonText);

} // namespace cafeina::world
