#include "cafeina/world/World.hpp"
#include "cafeina/world/WorldSerialization.hpp"
#include "cafeina/world/WorldService.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

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
    using cafeina::world::WorldFormatError;
    using cafeina::world::WorldService;
    using cafeina::world::WorldState;
    using cafeina::world::deserializeWorldJson;
    using cafeina::world::serializeWorldJson;

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

    const auto houseId = world.createObject("House");
    const auto doorId = world.createObject("Door");
    const auto buttonId = world.createObject("Button");

    require(world.setParent(doorId, houseId), "door should be parented under house");
    require(world.setParent(buttonId, doorId), "button should be parented under door");
    require(world.findObject(doorId)->parentId == houseId, "door should retain house parent");
    require(world.findObject(buttonId)->parentId == doorId, "button should retain door parent");

    const auto houseChildren = world.childrenOf(houseId);
    require(
        houseChildren.size() == 1 && houseChildren[0] == doorId,
        "children should be returned deterministically by object ID"
    );

    const auto rootsBeforeRemoval = world.childrenOf(0);
    require(
        rootsBeforeRemoval.size() == 3,
        "floor, wall and house should be roots before hierarchy removal"
    );

    bool cycleRejected = false;
    try
    {
        world.setParent(houseId, buttonId);
    }
    catch (const std::invalid_argument&)
    {
        cycleRejected = true;
    }
    require(cycleRejected, "scene graph cycles must be rejected");
    require(world.findObject(houseId)->parentId == 0, "rejected cycle must not mutate hierarchy");

    bool selfParentRejected = false;
    try
    {
        world.setParent(doorId, doorId);
    }
    catch (const std::invalid_argument&)
    {
        selfParentRejected = true;
    }
    require(selfParentRejected, "self-parenting must be rejected");
    require(!world.setParent(doorId, 999999), "missing parent should fail without mutation");
    require(world.findObject(doorId)->parentId == houseId, "failed parent change must preserve old parent");

    require(world.removeObject(doorId), "parent object should be removable");
    require(
        world.findObject(buttonId) && world.findObject(buttonId)->parentId == 0,
        "children of a removed object should be preserved and reparented to root"
    );

    const auto ordered = world.objects();
    require(ordered.size() == 4, "deterministic object snapshot should include all remaining objects");
    require(
        ordered[0].id == floorId
            && ordered[1].id == wallId
            && ordered[2].id == houseId
            && ordered[3].id == buttonId,
        "object snapshots should remain ordered by stable ID after hierarchy edits"
    );

    require(world.removeObject(floorId), "existing object should be removable");
    require(!world.removeObject(floorId), "removing the same object twice should report false");
    require(world.findObject(floorId) == nullptr, "removed object should no longer be findable");

    const auto rampId = world.createObject("Ramp");
    require(rampId > buttonId, "removed IDs must not be recycled");

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

    {
        Transform invalidTransform;
        invalidTransform.position.x = std::numeric_limits<double>::infinity();

        bool invalidTransformRejected = false;
        try
        {
            world.setTransform(spawnId, invalidTransform);
        }
        catch (const std::invalid_argument&)
        {
            invalidTransformRejected = true;
        }
        require(invalidTransformRejected, "non-finite transforms must be rejected");
    }

    {
        World persistent;
        const auto house = persistent.createObject("House");
        const auto door = persistent.createObject("Door");
        const auto deleted = persistent.createObject("Temporary");

        Transform houseTransform;
        houseTransform.position = Vec3{12.5, 3.0, -8.25};
        houseTransform.rotationDegrees = Vec3{0.0, 45.0, 0.0};
        houseTransform.scale = Vec3{2.0, 2.0, 2.0};

        require(persistent.setTransform(house, houseTransform), "persistent transform should update");
        require(persistent.setParent(door, house), "persistent hierarchy should update");
        require(persistent.removeObject(deleted), "temporary object should be removed before save");

        const std::string encoded = serializeWorldJson(persistent);
        World reopened = deserializeWorldJson(encoded);

        require(reopened.objectCount() == 2, "round-trip should preserve object count");
        require(reopened.findObject(house) != nullptr, "round-trip should preserve stable house ID");
        require(reopened.findObject(door) != nullptr, "round-trip should preserve stable door ID");
        require(reopened.findObject(house)->transform == houseTransform, "round-trip should preserve transforms");
        require(reopened.findObject(door)->parentId == house, "round-trip should preserve hierarchy");
        require(serializeWorldJson(reopened) == encoded, "serialized world should be deterministic after round-trip");

        const auto afterReopen = reopened.createObject("AfterReopen");
        require(afterReopen > deleted, "round-trip must preserve next object ID and never recycle deleted IDs");

        std::string unsupported = encoded;
        const std::string versionNeedle = "\"version\": 1";
        const auto versionPos = unsupported.find(versionNeedle);
        require(versionPos != std::string::npos, "serialized world should contain explicit version");
        unsupported.replace(versionPos, versionNeedle.size(), "\"version\": 999");

        bool versionRejected = false;
        try
        {
            (void)deserializeWorldJson(unsupported);
        }
        catch (const WorldFormatError&)
        {
            versionRejected = true;
        }
        require(versionRejected, "unsupported world versions must fail closed");

        WorldState invalidState = persistent.state();
        require(invalidState.objects.size() == 2, "state snapshot should contain saved objects");
        invalidState.objects[0].parentId = invalidState.objects[1].id;
        invalidState.objects[1].parentId = invalidState.objects[0].id;

        World protectedWorld;
        const auto protectedId = protectedWorld.createObject("Protected");

        bool invalidStateRejected = false;
        try
        {
            protectedWorld.restore(invalidState);
        }
        catch (const std::invalid_argument&)
        {
            invalidStateRejected = true;
        }

        require(invalidStateRejected, "cyclic restored state must be rejected");
        require(
            protectedWorld.objectCount() == 1 && protectedWorld.findObject(protectedId) != nullptr,
            "failed restore must leave the existing world untouched"
        );
    }

    {
        WorldService service;

        constexpr int threadCount = 4;
        constexpr int objectsPerThread = 50;

        std::vector<std::vector<cafeina::world::ObjectId>> created(threadCount);
        std::vector<std::thread> workers;
        workers.reserve(threadCount);

        for (int threadIndex = 0; threadIndex < threadCount; ++threadIndex)
        {
            workers.emplace_back([&, threadIndex]() {
                auto& ids = created[threadIndex];
                ids.reserve(objectsPerThread);

                for (int i = 0; i < objectsPerThread; ++i)
                {
                    ids.push_back(
                        service.createObject(
                            "T" + std::to_string(threadIndex) + "_" + std::to_string(i)
                        )
                    );
                }
            });
        }

        for (auto& worker : workers)
            worker.join();

        require(
            service.objectCount() == std::size_t(threadCount * objectsPerThread),
            "synchronized service should retain all concurrently created objects"
        );

        std::set<cafeina::world::ObjectId> uniqueIds;
        for (const auto& ids : created)
            uniqueIds.insert(ids.begin(), ids.end());

        require(
            uniqueIds.size() == std::size_t(threadCount * objectsPerThread),
            "concurrent creation must still issue unique stable IDs"
        );

        const auto snapshot = service.state();
        require(
            snapshot.objects.size() == std::size_t(threadCount * objectsPerThread),
            "service state should provide a consistent snapshot"
        );

        const auto sampleId = created[0][0];
        const auto sample = service.object(sampleId);
        require(sample.has_value(), "service should return object copies safely");
        require(sample->id == sampleId, "service object copy should preserve stable ID");
    }

    std::cout << "world core smoke tests passed\n";
    return 0;
}
