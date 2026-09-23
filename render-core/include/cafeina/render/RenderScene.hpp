#pragma once

#include <vector>

#include "cafeina/world/World.hpp"

namespace cafeina::render {

struct RenderItem {
    world::ObjectId objectId = 0;
    world::PrimitiveMesh primitive = world::PrimitiveMesh::Box;
    world::Transform transform;

    bool operator==(const RenderItem& other) const
    {
        return objectId == other.objectId
            && primitive == other.primitive
            && transform == other.transform;
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
