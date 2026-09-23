#include "cafeina/render/RenderSceneDiff.hpp"

#include <map>
#include <stdexcept>

namespace cafeina::render {
namespace {

std::map<world::ObjectId, RenderItem> indexScene(const RenderScene& scene)
{
    std::map<world::ObjectId, RenderItem> indexed;

    for (const RenderItem& item : scene.items)
    {
        if (!indexed.emplace(item.objectId, item).second)
            throw std::invalid_argument("render scene diff contains duplicate object id");
    }

    return indexed;
}

} // namespace

RenderSceneDiff RenderSceneDiffer::diff(
    const RenderScene& previous,
    const RenderScene& current
)
{
    const auto before = indexScene(previous);
    const auto after = indexScene(current);

    RenderSceneDiff result;

    for (const auto& entry : before)
    {
        const auto found = after.find(entry.first);

        if (found == after.end())
        {
            result.removed.push_back(entry.first);
            continue;
        }

        if (!(entry.second == found->second))
            result.updated.push_back(entry.first);
    }

    for (const auto& entry : after)
    {
        if (before.find(entry.first) == before.end())
            result.added.push_back(entry.first);
    }

    return result;
}

} // namespace cafeina::render
