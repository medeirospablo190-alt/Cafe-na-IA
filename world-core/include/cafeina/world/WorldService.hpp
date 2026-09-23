#pragma once

#include <cstddef>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "cafeina/world/World.hpp"

namespace cafeina::world {

// Thread-safe facade over one shared World instance.
// Each method is an atomic operation at the service boundary.
// Multi-operation transactions will be added separately.
class WorldService {
public:
    WorldService() = default;

    WorldService(const WorldService&) = delete;
    WorldService& operator=(const WorldService&) = delete;

    ObjectId createObject(const std::string& name);
    bool removeObject(ObjectId id);

    std::optional<WorldObject> object(ObjectId id) const;

    bool setName(ObjectId id, const std::string& name);
    bool setTransform(ObjectId id, const Transform& transform);
    bool setParent(ObjectId childId, ObjectId parentId);

    bool setMeshComponent(ObjectId id, const MeshComponent& component);
    std::optional<MeshComponent> meshComponent(ObjectId id) const;
    bool removeMeshComponent(ObjectId id);

    bool setColliderComponent(ObjectId id, const ColliderComponent& component);
    std::optional<ColliderComponent> colliderComponent(ObjectId id) const;
    bool removeColliderComponent(ObjectId id);

    bool setSemanticComponent(ObjectId id, const SemanticComponent& component);
    std::optional<SemanticComponent> semanticComponent(ObjectId id) const;
    bool removeSemanticComponent(ObjectId id);

    std::vector<ObjectId> childrenOf(ObjectId parentId) const;
    std::vector<WorldObject> objects() const;
    std::size_t objectCount() const;

    WorldState state() const;
    void restore(const WorldState& state);

    void clear();

private:
    mutable std::mutex mutex_;
    World world_;
};

} // namespace cafeina::world
