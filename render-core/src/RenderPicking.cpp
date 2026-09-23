#include "cafeina/render/RenderPicking.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace cafeina::render {
namespace {

using Matrix4 = std::array<double, 16>;

double length(const world::Vec3& value)
{
    return std::sqrt(
        value.x * value.x
        + value.y * value.y
        + value.z * value.z
    );
}

world::Vec3 normalize(const world::Vec3& value)
{
    const double magnitude = length(value);
    if (!std::isfinite(magnitude) || magnitude <= 1e-12)
        throw std::invalid_argument("picking ray direction must be non-zero and finite");

    return world::Vec3{
        value.x / magnitude,
        value.y / magnitude,
        value.z / magnitude
    };
}

bool invertMatrix(const Matrix4& input, Matrix4& output)
{
    double augmented[4][8]{};

    for (int row = 0; row < 4; ++row)
    {
        for (int column = 0; column < 4; ++column)
            augmented[row][column] = input[column * 4 + row];

        augmented[row][row + 4] = 1.0;
    }

    for (int pivotColumn = 0; pivotColumn < 4; ++pivotColumn)
    {
        int pivotRow = pivotColumn;
        double pivotMagnitude = std::fabs(augmented[pivotRow][pivotColumn]);

        for (int row = pivotColumn + 1; row < 4; ++row)
        {
            const double magnitude = std::fabs(augmented[row][pivotColumn]);
            if (magnitude > pivotMagnitude)
            {
                pivotMagnitude = magnitude;
                pivotRow = row;
            }
        }

        if (!std::isfinite(pivotMagnitude) || pivotMagnitude <= 1e-12)
            return false;

        if (pivotRow != pivotColumn)
        {
            for (int column = 0; column < 8; ++column)
                std::swap(augmented[pivotRow][column], augmented[pivotColumn][column]);
        }

        const double pivot = augmented[pivotColumn][pivotColumn];
        for (int column = 0; column < 8; ++column)
            augmented[pivotColumn][column] /= pivot;

        for (int row = 0; row < 4; ++row)
        {
            if (row == pivotColumn)
                continue;

            const double factor = augmented[row][pivotColumn];
            if (factor == 0.0)
                continue;

            for (int column = 0; column < 8; ++column)
            {
                augmented[row][column] -=
                    factor * augmented[pivotColumn][column];
            }
        }
    }

    for (int row = 0; row < 4; ++row)
    {
        for (int column = 0; column < 4; ++column)
            output[column * 4 + row] = augmented[row][column + 4];
    }

    return true;
}

world::Vec3 transformPoint(const Matrix4& matrix, const world::Vec3& value)
{
    const double x =
        matrix[0] * value.x
        + matrix[4] * value.y
        + matrix[8] * value.z
        + matrix[12];

    const double y =
        matrix[1] * value.x
        + matrix[5] * value.y
        + matrix[9] * value.z
        + matrix[13];

    const double z =
        matrix[2] * value.x
        + matrix[6] * value.y
        + matrix[10] * value.z
        + matrix[14];

    const double w =
        matrix[3] * value.x
        + matrix[7] * value.y
        + matrix[11] * value.z
        + matrix[15];

    if (!std::isfinite(w) || std::fabs(w) <= 1e-12)
        throw std::invalid_argument("picking transform produced invalid homogeneous coordinate");

    if (std::fabs(w - 1.0) <= 1e-12)
        return world::Vec3{x, y, z};

    return world::Vec3{x / w, y / w, z / w};
}

world::Vec3 transformDirection(
    const Matrix4& matrix,
    const world::Vec3& value
)
{
    return world::Vec3{
        matrix[0] * value.x
            + matrix[4] * value.y
            + matrix[8] * value.z,
        matrix[1] * value.x
            + matrix[5] * value.y
            + matrix[9] * value.z,
        matrix[2] * value.x
            + matrix[6] * value.y
            + matrix[10] * value.z
    };
}

bool intersectUnitBox(
    const world::Vec3& origin,
    const world::Vec3& direction,
    double& outT
)
{
    double minimum = -std::numeric_limits<double>::infinity();
    double maximum = std::numeric_limits<double>::infinity();

    const double origins[3] = {origin.x, origin.y, origin.z};
    const double directions[3] = {direction.x, direction.y, direction.z};

    for (int axis = 0; axis < 3; ++axis)
    {
        const double axisOrigin = origins[axis];
        const double axisDirection = directions[axis];

        if (std::fabs(axisDirection) <= 1e-12)
        {
            if (axisOrigin < -0.5 || axisOrigin > 0.5)
                return false;
            continue;
        }

        double nearT = (-0.5 - axisOrigin) / axisDirection;
        double farT = (0.5 - axisOrigin) / axisDirection;

        if (nearT > farT)
            std::swap(nearT, farT);

        minimum = std::max(minimum, nearT);
        maximum = std::min(maximum, farT);

        if (minimum > maximum)
            return false;
    }

    if (maximum < 0.0)
        return false;

    outT = minimum >= 0.0 ? minimum : maximum;
    return std::isfinite(outT);
}

} // namespace

std::optional<PickHit> RenderPicker::pickNearest(
    const RenderScene& scene,
    const Ray& ray
)
{
    const world::Vec3 normalizedDirection = normalize(ray.direction);

    std::optional<PickHit> nearest;

    for (const RenderItem& item : scene.items)
    {
        if (item.primitive != world::PrimitiveMesh::Box)
            continue;

        Matrix4 inverse{};
        if (!invertMatrix(item.worldMatrix, inverse))
            continue;

        const world::Vec3 localOrigin =
            transformPoint(inverse, ray.origin);
        const world::Vec3 localDirection =
            transformDirection(inverse, normalizedDirection);

        double localT = 0.0;
        if (!intersectUnitBox(localOrigin, localDirection, localT))
            continue;

        const world::Vec3 localHit{
            localOrigin.x + localDirection.x * localT,
            localOrigin.y + localDirection.y * localT,
            localOrigin.z + localDirection.z * localT
        };

        const world::Vec3 worldHit =
            transformPoint(item.worldMatrix, localHit);

        const world::Vec3 fromOrigin{
            worldHit.x - ray.origin.x,
            worldHit.y - ray.origin.y,
            worldHit.z - ray.origin.z
        };

        const double distance = length(fromOrigin);
        if (!std::isfinite(distance))
            continue;

        if (
            !nearest
            || distance < nearest->distance - 1e-9
            || (
                std::fabs(distance - nearest->distance) <= 1e-9
                && item.objectId < nearest->objectId
            )
        )
        {
            nearest = PickHit{
                item.objectId,
                distance,
                worldHit
            };
        }
    }

    return nearest;
}

} // namespace cafeina::render
