#include "cafeina/render/RenderScene.hpp"

#include <cmath>
#include <map>
#include <set>
#include <stdexcept>

namespace cafeina::render {
namespace {

using Matrix4 = std::array<double, 16>;

Matrix4 identityMatrix()
{
    return Matrix4{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    };
}

Matrix4 multiply(const Matrix4& left, const Matrix4& right)
{
    Matrix4 result{};

    for (int column = 0; column < 4; ++column)
    {
        for (int row = 0; row < 4; ++row)
        {
            double value = 0.0;
            for (int k = 0; k < 4; ++k)
            {
                value += left[k * 4 + row] * right[column * 4 + k];
            }
            result[column * 4 + row] = value;
        }
    }

    return result;
}

Matrix4 translationMatrix(const world::Vec3& value)
{
    Matrix4 result = identityMatrix();
    result[12] = value.x;
    result[13] = value.y;
    result[14] = value.z;
    return result;
}

Matrix4 scaleMatrix(const world::Vec3& value)
{
    Matrix4 result = identityMatrix();
    result[0] = value.x;
    result[5] = value.y;
    result[10] = value.z;
    return result;
}

Matrix4 rotationX(double degrees)
{
    const double radians = degrees * 3.14159265358979323846 / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);

    Matrix4 result = identityMatrix();
    result[5] = cosine;
    result[6] = sine;
    result[9] = -sine;
    result[10] = cosine;
    return result;
}

Matrix4 rotationY(double degrees)
{
    const double radians = degrees * 3.14159265358979323846 / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);

    Matrix4 result = identityMatrix();
    result[0] = cosine;
    result[2] = -sine;
    result[8] = sine;
    result[10] = cosine;
    return result;
}

Matrix4 rotationZ(double degrees)
{
    const double radians = degrees * 3.14159265358979323846 / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);

    Matrix4 result = identityMatrix();
    result[0] = cosine;
    result[1] = sine;
    result[4] = -sine;
    result[5] = cosine;
    return result;
}

Matrix4 localMatrix(const world::Transform& transform)
{
    Matrix4 result = translationMatrix(transform.position);
    result = multiply(result, rotationZ(transform.rotationDegrees.z));
    result = multiply(result, rotationY(transform.rotationDegrees.y));
    result = multiply(result, rotationX(transform.rotationDegrees.x));
    result = multiply(result, scaleMatrix(transform.scale));
    return result;
}

Matrix4 resolveWorldMatrix(
    world::ObjectId objectId,
    const std::map<world::ObjectId, world::WorldObject>& objects,
    std::map<world::ObjectId, Matrix4>& resolved,
    std::set<world::ObjectId>& resolving
)
{
    const auto cached = resolved.find(objectId);
    if (cached != resolved.end())
        return cached->second;

    const auto object = objects.find(objectId);
    if (object == objects.end())
        throw std::invalid_argument("render scene references missing object");

    if (!world::World::isValidTransform(object->second.transform))
        throw std::invalid_argument("render scene contains invalid transform");

    if (!resolving.insert(objectId).second)
        throw std::invalid_argument("render scene contains hierarchy cycle");

    Matrix4 result = localMatrix(object->second.transform);

    if (object->second.parentId != 0)
    {
        const auto parent = objects.find(object->second.parentId);
        if (parent == objects.end())
            throw std::invalid_argument("render scene contains missing parent");

        result = multiply(
            resolveWorldMatrix(
                object->second.parentId,
                objects,
                resolved,
                resolving
            ),
            result
        );
    }

    resolving.erase(objectId);
    resolved.emplace(objectId, result);
    return result;
}

} // namespace

RenderScene RenderSceneBuilder::build(const world::WorldState& state)
{
    std::map<world::ObjectId, world::WorldObject> objects;
    for (const world::WorldObject& object : state.objects)
    {
        if (!objects.emplace(object.id, object).second)
            throw std::invalid_argument("render scene contains duplicate object id");
    }

    std::map<world::ObjectId, Matrix4> worldMatrices;
    std::set<world::ObjectId> resolving;

    for (const auto& entry : objects)
    {
        (void)resolveWorldMatrix(
            entry.first,
            objects,
            worldMatrices,
            resolving
        );
    }

    std::map<world::ObjectId, RenderItem> renderables;

    for (const auto& entry : state.meshComponents)
    {
        const auto object = objects.find(entry.objectId);
        if (object == objects.end())
            throw std::invalid_argument("mesh component references missing render object");

        if (!world::World::isValidMeshComponent(entry.value))
            throw std::invalid_argument("render scene contains invalid mesh component");

        if (!entry.value.visible)
            continue;

        RenderItem item;
        item.objectId = entry.objectId;
        item.primitive = entry.value.primitive;
        item.transform = object->second.transform;
        item.worldMatrix = worldMatrices.at(entry.objectId);

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
