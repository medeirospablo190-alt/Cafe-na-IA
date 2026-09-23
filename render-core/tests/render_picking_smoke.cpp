#include "cafeina/render/RenderPicking.hpp"

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
    using cafeina::render::Ray;
    using cafeina::render::RenderPicker;
    using cafeina::render::RenderSceneBuilder;
    using cafeina::world::MeshComponent;
    using cafeina::world::PrimitiveMesh;
    using cafeina::world::Transform;
    using cafeina::world::Vec3;
    using cafeina::world::World;

    World world;

    const auto farBox = world.createObject("FarBox");
    const auto nearBox = world.createObject("NearBox");
    const auto parent = world.createObject("Parent");
    const auto child = world.createObject("Child");

    MeshComponent boxMesh;
    boxMesh.primitive = PrimitiveMesh::Box;

    require(world.setMeshComponent(farBox, boxMesh), "far box mesh should attach");
    require(world.setMeshComponent(nearBox, boxMesh), "near box mesh should attach");
    require(world.setMeshComponent(child, boxMesh), "child box mesh should attach");

    Transform farTransform;
    farTransform.position = Vec3{0.0, 0.0, 0.0};
    require(world.setTransform(farBox, farTransform), "far box transform should update");

    Transform nearTransform;
    nearTransform.position = Vec3{0.0, 0.0, 4.0};
    require(world.setTransform(nearBox, nearTransform), "near box transform should update");

    Transform parentTransform;
    parentTransform.position = Vec3{4.0, 0.0, 0.0};
    parentTransform.rotationDegrees = Vec3{0.0, 0.0, 90.0};
    parentTransform.scale = Vec3{2.0, 2.0, 2.0};
    require(world.setTransform(parent, parentTransform), "parent transform should update");

    Transform childTransform;
    childTransform.position = Vec3{1.0, 0.0, 0.0};
    require(world.setTransform(child, childTransform), "child transform should update");
    require(world.setParent(child, parent), "child should parent correctly");

    const auto scene = RenderSceneBuilder::build(world.state());

    const auto nearest = RenderPicker::pickNearest(
        scene,
        Ray{
            Vec3{0.0, 0.0, 10.0},
            Vec3{0.0, 0.0, -1.0}
        }
    );

    require(nearest.has_value(), "forward ray should hit a box");
    require(nearest->objectId == nearBox, "nearest visible box should win");
    requireNear(nearest->worldPosition.z, 4.5, "near box front face should be hit");

    const auto childHit = RenderPicker::pickNearest(
        scene,
        Ray{
            Vec3{4.0, 2.0, 10.0},
            Vec3{0.0, 0.0, -1.0}
        }
    );

    require(childHit.has_value(), "ray should hit hierarchically transformed child");
    require(childHit->objectId == child, "resolved child world matrix should drive picking");

    const auto miss = RenderPicker::pickNearest(
        scene,
        Ray{
            Vec3{50.0, 50.0, 50.0},
            Vec3{1.0, 0.0, 0.0}
        }
    );
    require(!miss.has_value(), "ray away from scene should miss");

    bool zeroDirectionRejected = false;
    try
    {
        (void)RenderPicker::pickNearest(
            scene,
            Ray{
                Vec3{0.0, 0.0, 0.0},
                Vec3{0.0, 0.0, 0.0}
            }
        );
    }
    catch (const std::invalid_argument&)
    {
        zeroDirectionRejected = true;
    }
    require(zeroDirectionRejected, "zero-length picking rays must be rejected");

    std::cout << "render picking smoke tests passed\n";
    return 0;
}
