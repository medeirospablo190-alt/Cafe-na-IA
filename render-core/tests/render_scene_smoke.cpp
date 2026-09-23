#include "cafeina/render/RenderScene.hpp"

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
    using cafeina::render::RenderSceneBuilder;
    using cafeina::world::MeshComponent;
    using cafeina::world::PrimitiveMesh;
    using cafeina::world::Transform;
    using cafeina::world::Vec3;
    using cafeina::world::World;
    using cafeina::world::WorldState;

    World world;

    const auto ground = world.createObject("Ground");
    const auto cube = world.createObject("Cube");
    const auto hidden = world.createObject("Hidden");
    const auto logicalOnly = world.createObject("TriggerLogic");

    MeshComponent groundMesh;
    groundMesh.primitive = PrimitiveMesh::Plane;
    require(world.setMeshComponent(ground, groundMesh), "ground should accept plane mesh");

    MeshComponent cubeMesh;
    cubeMesh.primitive = PrimitiveMesh::Box;
    require(world.setMeshComponent(cube, cubeMesh), "cube should accept box mesh");

    MeshComponent hiddenMesh;
    hiddenMesh.primitive = PrimitiveMesh::Sphere;
    hiddenMesh.visible = false;
    require(world.setMeshComponent(hidden, hiddenMesh), "hidden object should accept mesh metadata");

    Transform cubeTransform;
    cubeTransform.position = Vec3{2.0, 3.0, -4.0};
    cubeTransform.rotationDegrees = Vec3{0.0, 45.0, 0.0};
    cubeTransform.scale = Vec3{1.5, 1.5, 1.5};
    require(world.setTransform(cube, cubeTransform), "cube transform should update");

    const auto scene = RenderSceneBuilder::build(world.state());

    require(scene.items.size() == 2, "only visible objects with meshes should render");
    require(scene.items[0].objectId == ground, "render items should be ordered by stable object id");
    require(scene.items[0].primitive == PrimitiveMesh::Plane, "ground primitive should be preserved");
    require(scene.items[1].objectId == cube, "cube should be second deterministic render item");
    require(scene.items[1].primitive == PrimitiveMesh::Box, "cube primitive should be preserved");
    require(scene.items[1].transform == cubeTransform, "render snapshot should preserve transform");
    require(logicalOnly > hidden, "logical-only object should still be a valid world object");

    WorldState invalid = world.state();
    invalid.meshComponents.push_back({999999, MeshComponent{}});

    bool missingObjectRejected = false;
    try
    {
        (void)RenderSceneBuilder::build(invalid);
    }
    catch (const std::invalid_argument&)
    {
        missingObjectRejected = true;
    }
    require(missingObjectRejected, "render builder must reject mesh references to missing objects");

    std::cout << "render scene smoke tests passed\n";
    return 0;
}
