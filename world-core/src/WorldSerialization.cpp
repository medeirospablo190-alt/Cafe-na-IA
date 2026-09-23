#include "cafeina/world/WorldSerialization.hpp"

#include <string>
#include <utility>

#include <nlohmann/json.hpp>

namespace cafeina::world {
namespace {

using Json = nlohmann::json;

constexpr int kWorldFormatVersion = 2;
constexpr int kOldestSupportedWorldFormatVersion = 1;
constexpr std::size_t kMaxSerializedWorldBytes = 16 * 1024 * 1024;
constexpr std::size_t kMaxSerializedObjects = 100000;
constexpr std::size_t kMaxSerializedComponents = 300000;

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

const char* primitiveMeshName(PrimitiveMesh primitive)
{
    switch (primitive)
    {
    case PrimitiveMesh::Box:
        return "box";
    case PrimitiveMesh::Sphere:
        return "sphere";
    case PrimitiveMesh::Cylinder:
        return "cylinder";
    case PrimitiveMesh::Plane:
        return "plane";
    }

    throw WorldFormatError("unknown primitive mesh");
}

PrimitiveMesh primitiveMeshFromJson(const Json& value)
{
    const std::string name = value.get<std::string>();

    if (name == "box")
        return PrimitiveMesh::Box;
    if (name == "sphere")
        return PrimitiveMesh::Sphere;
    if (name == "cylinder")
        return PrimitiveMesh::Cylinder;
    if (name == "plane")
        return PrimitiveMesh::Plane;

    throw WorldFormatError("unsupported primitive mesh");
}

const char* colliderShapeName(ColliderShape shape)
{
    switch (shape)
    {
    case ColliderShape::Box:
        return "box";
    case ColliderShape::Sphere:
        return "sphere";
    case ColliderShape::Capsule:
        return "capsule";
    }

    throw WorldFormatError("unknown collider shape");
}

ColliderShape colliderShapeFromJson(const Json& value)
{
    const std::string name = value.get<std::string>();

    if (name == "box")
        return ColliderShape::Box;
    if (name == "sphere")
        return ColliderShape::Sphere;
    if (name == "capsule")
        return ColliderShape::Capsule;

    throw WorldFormatError("unsupported collider shape");
}

Json meshComponentsToJson(const WorldState& state)
{
    Json result = Json::array();
    for (const auto& entry : state.meshComponents)
    {
        result.push_back(Json{
            {"objectId", entry.objectId},
            {"primitive", primitiveMeshName(entry.value.primitive)},
            {"visible", entry.value.visible}
        });
    }
    return result;
}

Json colliderComponentsToJson(const WorldState& state)
{
    Json result = Json::array();
    for (const auto& entry : state.colliderComponents)
    {
        result.push_back(Json{
            {"objectId", entry.objectId},
            {"shape", colliderShapeName(entry.value.shape)},
            {"enabled", entry.value.enabled},
            {"solid", entry.value.solid}
        });
    }
    return result;
}

Json semanticComponentsToJson(const WorldState& state)
{
    Json result = Json::array();
    for (const auto& entry : state.semanticComponents)
    {
        result.push_back(Json{
            {"objectId", entry.objectId},
            {"role", entry.value.role},
            {"tags", entry.value.tags}
        });
    }
    return result;
}

void readVersion2Components(const Json& root, WorldState& state)
{
    const Json& components = root.at("components");
    if (!components.is_object())
        throw WorldFormatError("components must be an object");

    const Json& meshes = components.at("mesh");
    const Json& colliders = components.at("collider");
    const Json& semantics = components.at("semantic");

    if (!meshes.is_array() || !colliders.is_array() || !semantics.is_array())
        throw WorldFormatError("component stores must be arrays");

    if (meshes.size() + colliders.size() + semantics.size() > kMaxSerializedComponents)
        throw WorldFormatError("world component count exceeds limit");

    state.meshComponents.reserve(meshes.size());
    for (const Json& raw : meshes)
    {
        if (!raw.is_object())
            throw WorldFormatError("mesh component entry must be an object");

        ComponentEntry<MeshComponent> entry;
        entry.objectId = raw.at("objectId").get<ObjectId>();
        entry.value.primitive = primitiveMeshFromJson(raw.at("primitive"));
        entry.value.visible = raw.at("visible").get<bool>();
        state.meshComponents.push_back(std::move(entry));
    }

    state.colliderComponents.reserve(colliders.size());
    for (const Json& raw : colliders)
    {
        if (!raw.is_object())
            throw WorldFormatError("collider component entry must be an object");

        ComponentEntry<ColliderComponent> entry;
        entry.objectId = raw.at("objectId").get<ObjectId>();
        entry.value.shape = colliderShapeFromJson(raw.at("shape"));
        entry.value.enabled = raw.at("enabled").get<bool>();
        entry.value.solid = raw.at("solid").get<bool>();
        state.colliderComponents.push_back(std::move(entry));
    }

    state.semanticComponents.reserve(semantics.size());
    for (const Json& raw : semantics)
    {
        if (!raw.is_object())
            throw WorldFormatError("semantic component entry must be an object");

        ComponentEntry<SemanticComponent> entry;
        entry.objectId = raw.at("objectId").get<ObjectId>();
        entry.value.role = raw.at("role").get<std::string>();
        entry.value.tags = raw.at("tags").get<std::vector<std::string>>();
        state.semanticComponents.push_back(std::move(entry));
    }
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
            {"objects", std::move(objects)},
            {"components", Json{
                {"mesh", meshComponentsToJson(state)},
                {"collider", colliderComponentsToJson(state)},
                {"semantic", semanticComponentsToJson(state)}
            }}
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

        const int version = root.at("version").get<int>();
        if (version < kOldestSupportedWorldFormatVersion || version > kWorldFormatVersion)
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

        if (version >= 2)
            readVersion2Components(root, state);

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
