#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace cafeina::world {

using ObjectId = std::uint64_t;

enum class PrimitiveMesh {
    Box,
    Sphere,
    Cylinder,
    Plane,
};

struct MeshComponent {
    PrimitiveMesh primitive = PrimitiveMesh::Box;
    bool visible = true;

    bool operator==(const MeshComponent& other) const
    {
        return primitive == other.primitive && visible == other.visible;
    }
};

enum class ColliderShape {
    Box,
    Sphere,
    Capsule,
};

struct ColliderComponent {
    ColliderShape shape = ColliderShape::Box;
    bool enabled = true;
    bool solid = true;

    bool operator==(const ColliderComponent& other) const
    {
        return shape == other.shape
            && enabled == other.enabled
            && solid == other.solid;
    }
};

struct SemanticComponent {
    static constexpr std::size_t MaxRoleBytes = 128;
    static constexpr std::size_t MaxTags = 32;
    static constexpr std::size_t MaxTagBytes = 64;

    std::string role;
    std::vector<std::string> tags;

    bool operator==(const SemanticComponent& other) const
    {
        return role == other.role && tags == other.tags;
    }
};

template <typename T>
struct ComponentEntry {
    ObjectId objectId = 0;
    T value;
};

} // namespace cafeina::world
