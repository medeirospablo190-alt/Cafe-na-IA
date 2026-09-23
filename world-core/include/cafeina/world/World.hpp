#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "cafeina/world/Components.hpp"

namespace cafeina::world {

struct Vec3 {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;

    bool operator==(const Vec3& other) const
    {
        return x == other.x && y == other.y && z == other.z;
    }
};

struct Transform {
    Vec3 position;
    Vec3 rotationDegrees;
    Vec3 scale{1.0, 1.0, 1.0};

    bool operator==(const Transform& other) const
    {
        return position == other.position
            && rotationDegrees == other.rotationDegrees
            && scale == other.scale;
    }
};

struct WorldObject {
    ObjectId id = 0;
    ObjectId parentId = 0;
    std::string name;
    Transform transform;
};

struct WorldState {
    ObjectId nextObjectId = 1;
    std::vector<WorldObject> objects;
    std::vector<ComponentEntry<MeshComponent>> meshComponents;
    std::vector<ComponentEntry<ColliderComponent>> colliderComponents;
    std::vector<ComponentEntry<SemanticComponent>> semanticComponents;
};

class World {
public:
    static constexpr std::size_t MaxObjectNameBytes = 128;

    ObjectId createObject(const std::string& name);
    bool removeObject(ObjectId id);

    const WorldObject* findObject(ObjectId id) const;

    bool setName(ObjectId id, const std::string& name);
    bool setTransform(ObjectId id, const Transform& transform);

    // parentId == 0 means scene root. Cycles and self-parenting are rejected.
    bool setParent(ObjectId childId, ObjectId parentId);
    std::vector<ObjectId> childrenOf(ObjectId parentId) const;

    bool setMeshComponent(ObjectId id, const MeshComponent& component);
    const MeshComponent* meshComponent(ObjectId id) const;
    bool removeMeshComponent(ObjectId id);

    bool setColliderComponent(ObjectId id, const ColliderComponent& component);
    const ColliderComponent* colliderComponent(ObjectId id) const;
    bool removeColliderComponent(ObjectId id);

    bool setSemanticComponent(ObjectId id, const SemanticComponent& component);
    const SemanticComponent* semanticComponent(ObjectId id) const;
    bool removeSemanticComponent(ObjectId id);

    std::vector<WorldObject> objects() const;
    std::size_t objectCount() const noexcept;

    WorldState state() const;
    void restore(const WorldState& state);

    // Removes all current objects but intentionally does not recycle IDs.
    // Stable IDs must never start referring to a different object in the same World lifetime.
    void clear() noexcept;

    static bool isValidObjectName(const std::string& name);
    static bool isValidTransform(const Transform& transform);
    static bool isValidSemanticComponent(const SemanticComponent& component);

private:
    bool wouldCreateCycle(ObjectId childId, ObjectId parentId) const;

    ObjectId nextId_ = 1;
    std::map<ObjectId, WorldObject> objects_;
    std::map<ObjectId, MeshComponent> meshComponents_;
    std::map<ObjectId, ColliderComponent> colliderComponents_;
    std::map<ObjectId, SemanticComponent> semanticComponents_;
};

} // namespace cafeina::world
