#include "cafeina/render/RenderSceneDiff.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

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
    using cafeina::render::RenderScene;
    using cafeina::render::RenderSceneBuilder;
    using cafeina::render::RenderSceneDiffer;
    using cafeina::world::MeshComponent;
    using cafeina::world::PrimitiveMesh;
    using cafeina::world::Transform;
    using cafeina::world::Vec3;
    using cafeina::world::World;

    World world;

    const auto stable = world.createObject("Stable");
    const auto changed = world.createObject("Changed");
    const auto removed = world.createObject("Removed");

    MeshComponent box;
    box.primitive = PrimitiveMesh::Box;

    require(world.setMeshComponent(stable, box), "stable mesh should attach");
    require(world.setMeshComponent(changed, box), "changed mesh should attach");
    require(world.setMeshComponent(removed, box), "removed mesh should attach");

    const RenderScene before = RenderSceneBuilder::build(world.state());

    Transform moved;
    moved.position = Vec3{4.0, 2.0, -1.0};
    require(world.setTransform(changed, moved), "changed transform should update");

    require(world.removeObject(removed), "removed object should leave world");

    const auto added = world.createObject("Added");
    require(added > removed, "new object id must not recycle removed id");

    MeshComponent sphere;
    sphere.primitive = PrimitiveMesh::Sphere;
    require(world.setMeshComponent(added, sphere), "added mesh should attach");

    const RenderScene after = RenderSceneBuilder::build(world.state());
    const auto diff = RenderSceneDiffer::diff(before, after);

    require(diff.added.size() == 1, "one render item should be added");
    require(diff.added[0] == added, "added id should be deterministic");

    require(diff.removed.size() == 1, "one render item should be removed");
    require(diff.removed[0] == removed, "removed id should be deterministic");

    require(diff.updated.size() == 1, "one render item should be updated");
    require(diff.updated[0] == changed, "changed transform should be updated");

    const auto same = RenderSceneDiffer::diff(after, after);
    require(same.empty(), "identical scenes should produce empty diff");

    RenderScene invalid = after;
    invalid.items.push_back(after.items[0]);

    bool duplicateRejected = false;
    try
    {
        (void)RenderSceneDiffer::diff(after, invalid);
    }
    catch (const std::invalid_argument&)
    {
        duplicateRejected = true;
    }
    require(duplicateRejected, "duplicate ids must fail closed");

    std::cout << "render scene diff smoke tests passed\n";
    return 0;
}
