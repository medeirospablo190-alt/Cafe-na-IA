#include "cafeina/world/World.hpp"

#include <cctype>
#include <stdexcept>
#include <utility>

namespace cafeina::world {

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
    return objects_.erase(id) != 0;
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
    auto it = objects_.find(id);
    if (it == objects_.end())
        return false;

    it->second.transform = transform;
    return true;
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

void World::clear() noexcept
{
    objects_.clear();
}

} // namespace cafeina::world
