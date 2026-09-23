#pragma once

#include <optional>

#include "cafeina/render/RenderScene.hpp"

namespace cafeina::render {

struct Ray {
    world::Vec3 origin;
    world::Vec3 direction;
};

struct PickHit {
    world::ObjectId objectId = 0;
    double distance = 0.0;
    world::Vec3 worldPosition;
};

class RenderPicker {
public:
    // Returns the nearest visible supported primitive hit by the ray.
    // Initial implementation supports Box primitives only.
    static std::optional<PickHit> pickNearest(
        const RenderScene& scene,
        const Ray& ray
    );
};

} // namespace cafeina::render
