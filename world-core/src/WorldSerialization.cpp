#include "cafeina/world/WorldSerialization.hpp"

#include <limits>
#include <string>

#include <nlohmann/json.hpp>

namespace cafeina::world {
namespace {

using Json = nlohmann::json;

constexpr int kWorldFormatVersion = 1;
constexpr std::size_t kMaxSerializedWorldBytes = 16 * 1024 * 1024;
constexpr std::size_t kMaxSerializedObjects = 100000;

Json vec3ToJson(const Vec3& value)
{
    return Json::array({value.x, value.y, value.z});
}

Vec3 vec3FromJson(const Json& value)
{
    if (!value.is_array() || value.size() != 3)
        throw WorldFormatError("vec3 must contain exactly three numbers");

    Vec3 result;
    result.x = value.at(0).get<double>();
    result.y = value.at(1).get<double>();
    result.z = value.at(2).get<double>();
    return result;
}

Json transformToJson(const Transform& transform)
{
    return Json{
        {"position", vec3ToJson(transform.position)},
        {"rotationDegrees", vec3ToJson(transform.rotationDegrees)},
        {"scale", vec3ToJson(transform.scale)}
    };
}

Transform transformFromJson(const Json& value)
{
    if (!value.is_object())
        throw WorldFormatError("transform must be an object");

    Transform transform;
    transform.position = vec3FromJson(value.at("position"));
    transform.rotationDegrees = vec3FromJson(value.at("rotationDegrees"));
    transform.scale = vec3FromJson(value.at("scale"));

    if (!World::isValidTransform(transform))
        throw WorldFormatError("transform contains non-finite values");

    return transform;
}

} // namespace

std::string serializeWorldJson(const World& world)
{
    try
    {
        const WorldState state = world.state();

        Json objects = Json::array();
        for (const WorldObject& object : state.objects)
        {
            objects.push_back(Json{
                {"id", object.id},
                {"parentId", object.parentId},
                {"name", object.name},
                {"transform", transformToJson(object.transform)}
            });
        }

        Json root{
            {"format", "CAFEINA_WORLD"},
            {"version", kWorldFormatVersion},
            {"nextObjectId", state.nextObjectId},
            {"objects", std::move(objects)}
        };

        std::string result = root.dump(2);
        result.push_back('\n');

        if (result.size() > kMaxSerializedWorldBytes)
            throw WorldFormatError("serialized world exceeds size limit");

        return result;
    }
    catch (const WorldFormatError&)
    {
        throw;
    }
    catch (const std::exception& error)
    {
        throw WorldFormatError(std::string("failed to serialize world: ") + error.what());
    }
}

World deserializeWorldJson(const std::string& jsonText)
{
    if (jsonText.size() > kMaxSerializedWorldBytes)
        throw WorldFormatError("world file exceeds size limit");

    try
    {
        const Json root = Json::parse(jsonText);

        if (!root.is_object())
            throw WorldFormatError("world root must be an object");
        if (root.at("format").get<std::string>() != "CAFEINA_WORLD")
            throw WorldFormatError("unsupported world format");
        if (root.at("version").get<int>() != kWorldFormatVersion)
            throw WorldFormatError("unsupported world version");

        const Json& objects = root.at("objects");
        if (!objects.is_array())
            throw WorldFormatError("objects must be an array");
        if (objects.size() > kMaxSerializedObjects)
            throw WorldFormatError("world object count exceeds limit");

        WorldState state;
        state.nextObjectId = root.at("nextObjectId").get<ObjectId>();
        state.objects.reserve(objects.size());

        for (const Json& raw : objects)
        {
            if (!raw.is_object())
                throw WorldFormatError("world object entry must be an object");

            WorldObject object;
            object.id = raw.at("id").get<ObjectId>();
            object.parentId = raw.at("parentId").get<ObjectId>();
            object.name = raw.at("name").get<std::string>();
            object.transform = transformFromJson(raw.at("transform"));
            state.objects.push_back(std::move(object));
        }

        World world;
        world.restore(state);
        return world;
    }
    catch (const WorldFormatError&)
    {
        throw;
    }
    catch (const std::exception& error)
    {
        throw WorldFormatError(std::string("invalid world JSON: ") + error.what());
    }
}

} // namespace cafeina::world
