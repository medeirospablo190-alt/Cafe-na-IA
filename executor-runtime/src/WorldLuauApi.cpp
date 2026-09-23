#include "WorldLuauApi.hpp"

#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

#include "cafeina/world/WorldService.hpp"

#include "lua.h"
#include "lualib.h"

namespace cafeina {
namespace {

world::WorldService* worldService(lua_State* L)
{
    auto* service = static_cast<world::WorldService*>(lua_touserdata(L, lua_upvalueindex(1)));
    if (!service)
        luaL_error(L, "World API host is unavailable");

    return service;
}

world::ObjectId checkedObjectId(lua_State* L, int index, bool allowZero = false)
{
    size_t length = 0;
    const char* raw = luaL_checklstring(L, index, &length);

    if (!raw || length == 0)
        throw std::invalid_argument("object id must be a decimal string");

    world::ObjectId value = 0;
    const world::ObjectId maxValue = std::numeric_limits<world::ObjectId>::max();

    for (size_t i = 0; i < length; ++i)
    {
        const unsigned char c = static_cast<unsigned char>(raw[i]);
        if (c < '0' || c > '9')
            throw std::invalid_argument("object id must contain only decimal digits");

        const world::ObjectId digit = static_cast<world::ObjectId>(c - '0');
        if (value > (maxValue - digit) / 10)
            throw std::invalid_argument("object id is out of range");

        value = value * 10 + digit;
    }

    if (!allowZero && value == 0)
        throw std::invalid_argument("object id zero is reserved for scene root");

    return value;
}

void pushObjectId(lua_State* L, world::ObjectId id)
{
    const std::string text = std::to_string(id);
    lua_pushlstring(L, text.data(), text.size());
}

void pushVec3(lua_State* L, const world::Vec3& value)
{
    lua_createtable(L, 0, 3);

    lua_pushnumber(L, value.x);
    lua_setfield(L, -2, "x");

    lua_pushnumber(L, value.y);
    lua_setfield(L, -2, "y");

    lua_pushnumber(L, value.z);
    lua_setfield(L, -2, "z");

    lua_setreadonly(L, -1, true);
}

void pushWorldObject(lua_State* L, const world::WorldObject& object)
{
    lua_createtable(L, 0, 6);

    pushObjectId(L, object.id);
    lua_setfield(L, -2, "id");

    pushObjectId(L, object.parentId);
    lua_setfield(L, -2, "parentId");

    lua_pushlstring(L, object.name.data(), object.name.size());
    lua_setfield(L, -2, "name");

    pushVec3(L, object.transform.position);
    lua_setfield(L, -2, "position");

    pushVec3(L, object.transform.rotationDegrees);
    lua_setfield(L, -2, "rotationDegrees");

    pushVec3(L, object.transform.scale);
    lua_setfield(L, -2, "scale");

    lua_setreadonly(L, -1, true);
}

template <typename Fn>
int withWorldErrors(lua_State* L, Fn&& fn)
{
    try
    {
        return fn();
    }
    catch (const std::exception& error)
    {
        luaL_error(L, "World API error: %s", error.what());
        return 0;
    }
}

int worldCreate(lua_State* L)
{
    return withWorldErrors(L, [&]() {
        size_t length = 0;
        const char* raw = luaL_checklstring(L, 1, &length);
        const std::string name(raw, length);

        const world::ObjectId id = worldService(L)->createObject(name);
        pushObjectId(L, id);
        return 1;
    });
}

int worldGet(lua_State* L)
{
    return withWorldErrors(L, [&]() {
        const world::ObjectId id = checkedObjectId(L, 1);
        const auto object = worldService(L)->object(id);

        if (!object)
        {
            lua_pushnil(L);
            return 1;
        }

        pushWorldObject(L, *object);
        return 1;
    });
}

int worldRemove(lua_State* L)
{
    return withWorldErrors(L, [&]() {
        const world::ObjectId id = checkedObjectId(L, 1);
        lua_pushboolean(L, worldService(L)->removeObject(id) ? 1 : 0);
        return 1;
    });
}

int worldSetName(lua_State* L)
{
    return withWorldErrors(L, [&]() {
        const world::ObjectId id = checkedObjectId(L, 1);

        size_t length = 0;
        const char* raw = luaL_checklstring(L, 2, &length);
        const std::string name(raw, length);

        lua_pushboolean(L, worldService(L)->setName(id, name) ? 1 : 0);
        return 1;
    });
}

int worldSetParent(lua_State* L)
{
    return withWorldErrors(L, [&]() {
        const world::ObjectId childId = checkedObjectId(L, 1);
        const world::ObjectId parentId = checkedObjectId(L, 2, true);

        lua_pushboolean(L, worldService(L)->setParent(childId, parentId) ? 1 : 0);
        return 1;
    });
}

enum class TransformField {
    Position,
    Rotation,
    Scale,
};

int worldSetTransformField(lua_State* L, TransformField field)
{
    return withWorldErrors(L, [&]() {
        const world::ObjectId id = checkedObjectId(L, 1);
        const double x = luaL_checknumber(L, 2);
        const double y = luaL_checknumber(L, 3);
        const double z = luaL_checknumber(L, 4);

        world::WorldService* service = worldService(L);
        const auto object = service->object(id);
        if (!object)
        {
            lua_pushboolean(L, 0);
            return 1;
        }

        world::Transform transform = object->transform;
        const world::Vec3 value{x, y, z};

        switch (field)
        {
        case TransformField::Position:
            transform.position = value;
            break;
        case TransformField::Rotation:
            transform.rotationDegrees = value;
            break;
        case TransformField::Scale:
            transform.scale = value;
            break;
        }

        lua_pushboolean(L, service->setTransform(id, transform) ? 1 : 0);
        return 1;
    });
}

int worldSetPosition(lua_State* L)
{
    return worldSetTransformField(L, TransformField::Position);
}

int worldSetRotation(lua_State* L)
{
    return worldSetTransformField(L, TransformField::Rotation);
}

int worldSetScale(lua_State* L)
{
    return worldSetTransformField(L, TransformField::Scale);
}

int worldChildren(lua_State* L)
{
    return withWorldErrors(L, [&]() {
        const world::ObjectId parentId = checkedObjectId(L, 1, true);
        const std::vector<world::ObjectId> children = worldService(L)->childrenOf(parentId);

        lua_createtable(L, static_cast<int>(children.size()), 0);
        for (size_t i = 0; i < children.size(); ++i)
        {
            pushObjectId(L, children[i]);
            lua_rawseti(L, -2, static_cast<int>(i + 1));
        }

        return 1;
    });
}

void setWorldFunction(
    lua_State* L,
    world::WorldService* service,
    lua_CFunction function,
    const char* debugName,
    const char* field
)
{
    lua_pushlightuserdata(L, service);
    lua_pushcclosure(L, function, debugName, 1);
    lua_setfield(L, -2, field);
}

} // namespace

void exposeWorldApi(lua_State* L, world::WorldService* service)
{
    if (!service)
        luaL_error(L, "World API requires a host service");

    lua_createtable(L, 0, 9);

    setWorldFunction(L, service, worldCreate, "World.create", "create");
    setWorldFunction(L, service, worldGet, "World.get", "get");
    setWorldFunction(L, service, worldRemove, "World.remove", "remove");
    setWorldFunction(L, service, worldSetName, "World.setName", "setName");
    setWorldFunction(L, service, worldSetParent, "World.setParent", "setParent");
    setWorldFunction(L, service, worldSetPosition, "World.setPosition", "setPosition");
    setWorldFunction(L, service, worldSetRotation, "World.setRotation", "setRotation");
    setWorldFunction(L, service, worldSetScale, "World.setScale", "setScale");
    setWorldFunction(L, service, worldChildren, "World.children", "children");

    lua_setreadonly(L, -1, true);
    lua_setglobal(L, "World");
}

} // namespace cafeina
