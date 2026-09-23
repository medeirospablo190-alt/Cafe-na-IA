#include "cafeina/world/World.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const char* message)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << message << "\n";
        std::exit(1);
    }
}

} // namespace

int main()
{
    using cafeina::world::Transform;
    using cafeina::world::Vec3;
    using cafeina::world::World;

    World world;

    const auto floorId = world.createObject("Floor");
    const auto wallId = world.createObject("Wall");

    require(floorId != 0, "object IDs must never use zero");
    require(wallId > floorId, "object IDs must increase monotonically");
    require(world.objectCount() == 2, "world should contain two objects");

    const auto* floor = world.findObject(floorId);
    require(floor != nullptr && floor->name == "Floor", "created object should be findable by stable ID");

    Transform wallTransform;
    wallTransform.position = Vec3{10.0, 2.0, -4.0};
    wallTransform.rotationDegrees = Vec3{0.0, 90.0, 0.0};
    wallTransform.scale = Vec3{5.0, 4.0, 0.5};

    require(world.setTransform(wallId, wallTransform), "existing object transform should update");
    require(
        world.findObject(wallId) && world.findObject(wallId)->transform == wallTransform,
        "updated transform should be retained"
    );

    require(world.setName(wallId, "EntranceWall"), "existing object should be renameable");
    require(world.findObject(wallId)->name == "EntranceWall", "renamed object should retain the same ID");

    const auto ordered = world.objects();
    require(ordered.size() == 2, "deterministic object snapshot should include both objects");
    require(
        ordered[0].id == floorId && ordered[1].id == wallId,
        "object snapshots should be ordered by stable ID"
    );

    require(world.removeObject(floorId), "existing object should be removable");
    require(!world.removeObject(floorId), "removing the same object twice should report false");
    require(world.findObject(floorId) == nullptr, "removed object should no longer be findable");

    const auto rampId = world.createObject("Ramp");
    require(rampId > wallId, "removed IDs must not be recycled");

    world.clear();
    require(world.objectCount() == 0, "clear should remove current objects");

    const auto spawnId = world.createObject("Spawn");
    require(spawnId > rampId, "clear must not recycle IDs within the same World lifetime");

    require(!World::isValidObjectName(""), "empty names should be invalid");
    require(!World::isValidObjectName("bad\nname"), "control characters should be invalid");

    bool rejected = false;
    try
    {
        world.createObject("");
    }
    catch (const std::invalid_argument&)
    {
        rejected = true;
    }
    require(rejected, "invalid names must fail explicitly");

    std::cout << "world core smoke tests passed\n";
    return 0;
}
