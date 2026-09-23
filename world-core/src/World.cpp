#include "cafeina/world/World.hpp"

#include <cctype>
#include <cmath>
#include <stdexcept>
#include <utility>

namespace cafeina::world {

bool World::isValidTransform(const Transform& transform)
{
    const auto finite = [](const Vec3& value) {
        return std::isfinite(value.x)
            && std::isfinite(value.y)
            && std::isfinite(value.z);
    };

    return finite(transform.position)
        && finite(transform.rotationDegrees)
        && finite(transform.scale);
}

bool World::isValidObjectName(const std::string& name)
{
    if (name.empty() || name.size() > MaxObjectNameBytes)
        return false;

    for (unsigned char c : name)
    {
        if (std::iscntrl(c))
            return false;
    }

    return true;
}

ObjectId World::createObject(const std::string& name)
{
    if (!isValidObjectName(name))
        throw std::invalid_argument("invalid world object name");

    if (nextId_ == 0)
        throw std::overflow_error("world object id space exhausted");

    const ObjectId id = nextId_++;

    WorldObject object;
    object.id = id;
    object.name = name;

    const auto inserted = objects_.emplace(id, std::move(object));
    if (!inserted.second)
        throw std::logic_error("world object id collision");

    return id;
}

bool World::removeObject(ObjectId id)
{
    const auto target = objects_.find(id);
    if (target == objects_.end())
        return false;

    // Non-destructive hierarchy rule for the base API: removing a parent
    // keeps its children and moves them to the scene root. A future explicit
    // subtree deletion operation can provide destructive semantics.
    for (auto& entry : objects_)
    {
        if (entry.second.parentId == id)
            entry.second.parentId = 0;
    }

    objects_.erase(target);
    return true;
}

const WorldObject* World::findObject(ObjectId id) const
{
    const auto it = objects_.find(id);
    return it == objects_.end() ? nullptr : &it->second;
}

bool World::setName(ObjectId id, const std::string& name)
{
    if (!isValidObjectName(name))
        throw std::invalid_argument("invalid world object name");

    auto it = objects_.find(id);
    if (it == objects_.end())
        return false;

    it->second.name = name;
    return true;
}

bool World::setTransform(ObjectId id, const Transform& transform)
{
    if (!isValidTransform(transform))
        throw std::invalid_argument("invalid world transform");

    auto it = objects_.find(id);
    if (it == objects_.end())
        return false;

    it->second.transform = transform;
    return true;
}

bool World::setParent(ObjectId childId, ObjectId parentId)
{
    auto child = objects_.find(childId);
    if (child == objects_.end())
        return false;

    if (parentId == childId)
        throw std::invalid_argument("world object cannot parent itself");

    if (parentId != 0 && objects_.find(parentId) == objects_.end())
        return false;

    if (wouldCreateCycle(childId, parentId))
        throw std::invalid_argument("scene graph cycle is not allowed");

    child->second.parentId = parentId;
    return true;
}

std::vector<ObjectId> World::childrenOf(ObjectId parentId) const
{
    std::vector<ObjectId> children;
    for (const auto& entry : objects_)
    {
        if (entry.second.parentId == parentId)
            children.push_back(entry.first);
    }
    return children;
}

bool World::wouldCreateCycle(ObjectId childId, ObjectId parentId) const
{
    ObjectId current = parentId;

    while (current != 0)
    {
        if (current == childId)
            return true;

        const auto it = objects_.find(current);
        if (it == objects_.end())
            return false;

        current = it->second.parentId;
    }

    return false;
}

std::vector<WorldObject> World::objects() const
{
    std::vector<WorldObject> result;
    result.reserve(objects_.size());

    for (const auto& entry : objects_)
        result.push_back(entry.second);

    return result;
}

std::size_t World::objectCount() const noexcept
{
    return objects_.size();
}

WorldState World::state() const
{
    WorldState snapshot;
    snapshot.nextObjectId = nextId_;
    snapshot.objects = objects();
    return snapshot;
}

void World::restore(const WorldState& state)
{
    if (state.nextObjectId == 0)
        throw std::invalid_argument("next object id must not be zero");

    std::map<ObjectId, WorldObject> restored;

    for (const WorldObject& object : state.objects)
    {
        if (object.id == 0 || object.id >= state.nextObjectId)
            throw std::invalid_argument("invalid object id in world state");
        if (!isValidObjectName(object.name))
            throw std::invalid_argument("invalid object name in world state");
        if (!isValidTransform(object.transform))
            throw std::invalid_argument("invalid transform in world state");
        if (object.parentId == object.id)
            throw std::invalid_argument("world object cannot parent itself");

        const auto inserted = restored.emplace(object.id, object);
        if (!inserted.second)
            throw std::invalid_argument("duplicate object id in world state");
    }

    for (const auto& entry : restored)
    {
        const WorldObject& object = entry.second;

        if (object.parentId != 0 && restored.find(object.parentId) == restored.end())
            throw std::invalid_argument("missing parent in world state");

        ObjectId current = object.parentId;
        std::size_t traversed = 0;

        while (current != 0)
        {
            if (current == object.id)
                throw std::invalid_argument("scene graph cycle in world state");

            const auto parent = restored.find(current);
            if (parent == restored.end())
                throw std::invalid_argument("missing parent in world state");

            current = parent->second.parentId;
            if (++traversed > restored.size())
                throw std::invalid_argument("scene graph cycle in world state");
        }
    }

    objects_ = std::move(restored);
    nextId_ = state.nextObjectId;
}

void World::clear() noexcept
{
    objects_.clear();
}

} // namespace cafeina::world
