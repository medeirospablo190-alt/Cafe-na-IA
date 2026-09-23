#include "cafeina/render/RenderScene.hpp"

#include <map>
#include <stdexcept>

namespace cafeina::render {

RenderScene RenderSceneBuilder::build(const world::WorldState& state)
{
    std::map<world::ObjectId, world::WorldObject> objects;
    for (const world::WorldObject& object : state.objects)
    {
        if (!objects.emplace(object.id, object).second)
            throw std::invalid_argument("render scene contains duplicate object id");
    }

    std::map<world::ObjectId, RenderItem> renderables;

    for (const auto& entry : state.meshComponents)
    {
        const auto object = objects.find(entry.objectId);
        if (object == objects.end())
            throw std::invalid_argument("mesh component references missing render object");

        if (!world::World::isValidMeshComponent(entry.value))
            throw std::invalid_argument("render scene contains invalid mesh component");

        if (!world::World::isValidTransform(object->second.transform))
            throw std::invalid_argument("render scene contains invalid transform");

        if (!entry.value.visible)
            continue;

        RenderItem item;
        item.objectId = entry.objectId;
        item.primitive = entry.value.primitive;
        item.transform = object->second.transform;

        if (!renderables.emplace(item.objectId, item).second)
            throw std::invalid_argument("render scene contains duplicate mesh component");
    }

    RenderScene scene;
    scene.items.reserve(renderables.size());

    for (const auto& entry : renderables)
        scene.items.push_back(entry.second);

    return scene;
}

} // namespace cafeina::render
