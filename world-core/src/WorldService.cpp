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
