#pragma once

#include <vector>

#include "cafeina/render/RenderScene.hpp"

namespace cafeina::render {

struct RenderSceneDiff {
    std::vector<world::ObjectId> added;
    std::vector<world::ObjectId> removed;
    std::vector<world::ObjectId> updated;

    bool empty() const noexcept
    {
        return added.empty() && removed.empty() && updated.empty();
    }
};

class RenderSceneDiffer {
public:
    static RenderSceneDiff diff(
        const RenderScene& previous,
        const RenderScene& current
    );
};

} // namespace cafeina::render
