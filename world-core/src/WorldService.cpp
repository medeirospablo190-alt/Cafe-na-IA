#include "cafeina/world/WorldService.hpp"

#include <utility>

namespace cafeina::world {

ObjectId WorldService::createObject(const std::string& name)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.createObject(name);
}

bool WorldService::removeObject(ObjectId id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.removeObject(id);
}

std::optional<WorldObject> WorldService::object(ObjectId id) const
{
    std::lock_guard<std::mutex> lock(mutex_);

    const WorldObject* found = world_.findObject(id);
    if (!found)
        return std::nullopt;

    return *found;
}

bool WorldService::setName(ObjectId id, const std::string& name)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.setName(id, name);
}

bool WorldService::setTransform(ObjectId id, const Transform& transform)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.setTransform(id, transform);
}

bool WorldService::setParent(ObjectId childId, ObjectId parentId)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.setParent(childId, parentId);
}

bool WorldService::setMeshComponent(ObjectId id, const MeshComponent& component)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.setMeshComponent(id, component);
}

std::optional<MeshComponent> WorldService::meshComponent(ObjectId id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    const MeshComponent* component = world_.meshComponent(id);
    return component ? std::optional<MeshComponent>(*component) : std::nullopt;
}

bool WorldService::removeMeshComponent(ObjectId id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.removeMeshComponent(id);
}

bool WorldService::setColliderComponent(ObjectId id, const ColliderComponent& component)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.setColliderComponent(id, component);
}

std::optional<ColliderComponent> WorldService::colliderComponent(ObjectId id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    const ColliderComponent* component = world_.colliderComponent(id);
    return component ? std::optional<ColliderComponent>(*component) : std::nullopt;
}

bool WorldService::removeColliderComponent(ObjectId id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.removeColliderComponent(id);
}

bool WorldService::setSemanticComponent(ObjectId id, const SemanticComponent& component)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.setSemanticComponent(id, component);
}

std::optional<SemanticComponent> WorldService::semanticComponent(ObjectId id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    const SemanticComponent* component = world_.semanticComponent(id);
    return component ? std::optional<SemanticComponent>(*component) : std::nullopt;
}

bool WorldService::removeSemanticComponent(ObjectId id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.removeSemanticComponent(id);
}

std::vector<ObjectId> WorldService::childrenOf(ObjectId parentId) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.childrenOf(parentId);
}

std::vector<WorldObject> WorldService::objects() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.objects();
}

std::size_t WorldService::objectCount() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.objectCount();
}

WorldState WorldService::state() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return world_.state();
}

void WorldService::restore(const WorldState& state)
{
    std::lock_guard<std::mutex> lock(mutex_);
    world_.restore(state);
}

void WorldService::clear()
{
    std::lock_guard<std::mutex> lock(mutex_);
    world_.clear();
}

} // namespace cafeina::world
