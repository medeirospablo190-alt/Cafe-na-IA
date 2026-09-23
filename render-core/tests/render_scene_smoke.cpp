#include "cafeina/render/RenderScene.hpp"

#include <cmath>
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

void requireNear(double actual, double expected, const char* message)
{
    if (std::fabs(actual - expected) > 0.000001)
    {
        std::cerr
            << "FAIL: " << message
            << " (expected " << expected
            << ", got " << actual << ")\n";
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

    const auto parent = world.createObject("Parent");
    const auto child = world.createObject("Child");

    Transform parentTransform;
    parentTransform.position = Vec3{10.0, 0.0, 0.0};
    parentTransform.rotationDegrees = Vec3{0.0, 0.0, 90.0};
    parentTransform.scale = Vec3{2.0, 2.0, 2.0};
    require(world.setTransform(parent, parentTransform), "parent transform should update");

    Transform childTransform;
    childTransform.position = Vec3{1.0, 0.0, 0.0};
    require(world.setTransform(child, childTransform), "child transform should update");
    require(world.setParent(child, parent), "child should attach to parent");

    MeshComponent childMesh;
    childMesh.primitive = PrimitiveMesh::Box;
    require(world.setMeshComponent(child, childMesh), "child should accept mesh");

    const auto scene = RenderSceneBuilder::build(world.state());

    require(scene.items.size() == 3, "only visible objects with meshes should render");
    require(scene.items[0].objectId == ground, "render items should be ordered by stable object id");
    require(scene.items[0].primitive == PrimitiveMesh::Plane, "ground primitive should be preserved");
    require(scene.items[1].objectId == cube, "cube should be second deterministic render item");
    require(scene.items[1].primitive == PrimitiveMesh::Box, "cube primitive should be preserved");
    require(scene.items[1].transform == cubeTransform, "render snapshot should preserve transform");
    require(scene.items[2].objectId == child, "child should be third deterministic render item");
    require(scene.items[2].transform == childTransform, "child local transform should remain inspectable");
    requireNear(
        scene.items[2].worldMatrix[12],
        10.0,
        "parent rotation should keep resolved child x at parent origin"
    );
    requireNear(
        scene.items[2].worldMatrix[13],
        2.0,
        "parent scale and rotation should move child in world space"
    );
    requireNear(
        scene.items[2].worldMatrix[14],
        0.0,
        "resolved child z should remain unchanged"
    );
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
