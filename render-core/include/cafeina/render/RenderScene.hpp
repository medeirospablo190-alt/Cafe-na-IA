#pragma once

#include <array>
#include <vector>

#include "cafeina/world/World.hpp"

namespace cafeina::render {

struct RenderItem {
    world::ObjectId objectId = 0;
    world::PrimitiveMesh primitive = world::PrimitiveMesh::Box;

    // Local transform is preserved for inspection/editor tooling.
    world::Transform transform;

    // Column-major world transform for graphics backends.
    std::array<double, 16> worldMatrix{};

    bool operator==(const RenderItem& other) const
    {
        return objectId == other.objectId
            && primitive == other.primitive
            && transform == other.transform
            && worldMatrix == other.worldMatrix;
    }
};

struct RenderScene {
    std::vector<RenderItem> items;
};

class RenderSceneBuilder {
public:
    // Builds an immutable render snapshot from a validated WorldState.
    // Only objects with a visible MeshComponent become render items.
    static RenderScene build(const world::WorldState& state);
};

} // namespace cafeina::render
