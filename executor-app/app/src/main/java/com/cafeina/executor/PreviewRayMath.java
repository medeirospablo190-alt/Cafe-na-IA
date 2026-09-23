package com.cafeina.executor;

public final class PreviewRayMath {
    private PreviewRayMath() {}

    public static Ray fromScreen(
        OrbitCameraState.CameraPose pose,
        double screenX,
        double screenY,
        double viewportWidth,
        double viewportHeight,
        double verticalFovDegrees
    ) {
        if (
            pose == null
                || !Double.isFinite(screenX)
                || !Double.isFinite(screenY)
                || !Double.isFinite(viewportWidth)
                || !Double.isFinite(viewportHeight)
                || viewportWidth <= 0.0
                || viewportHeight <= 0.0
                || !Double.isFinite(verticalFovDegrees)
                || verticalFovDegrees <= 1.0
                || verticalFovDegrees >= 179.0
        ) {
            throw new IllegalArgumentException("invalid preview ray input");
        }

        Vec3 eye = new Vec3(pose.eyeX, pose.eyeY, pose.eyeZ);
        Vec3 target = new Vec3(pose.targetX, pose.targetY, pose.targetZ);

        Vec3 forward = target.subtract(eye).normalized();
        Vec3 worldUp = new Vec3(0.0, 1.0, 0.0);

        Vec3 right = forward.cross(worldUp);
        if (right.length() <= 1e-9) {
            worldUp = new Vec3(0.0, 0.0, 1.0);
            right = forward.cross(worldUp);
        }
        right = right.normalized();

        Vec3 up = right.cross(forward).normalized();

        double normalizedX = (2.0 * screenX / viewportWidth) - 1.0;
        double normalizedY = 1.0 - (2.0 * screenY / viewportHeight);

        double aspect = viewportWidth / viewportHeight;
        double tanHalfFov = Math.tan(Math.toRadians(verticalFovDegrees) * 0.5);

        Vec3 direction = forward
            .add(right.scale(normalizedX * tanHalfFov * aspect))
            .add(up.scale(normalizedY * tanHalfFov))
            .normalized();

        return new Ray(eye, direction);
    }

    public static final class Ray {
        public final Vec3 origin;
        public final Vec3 direction;

        private Ray(Vec3 origin, Vec3 direction) {
            this.origin = origin;
            this.direction = direction;
        }
    }

    public static final class Vec3 {
        public final double x;
        public final double y;
        public final double z;

        private Vec3(double x, double y, double z) {
            this.x = x;
            this.y = y;
            this.z = z;
        }

        private Vec3 add(Vec3 other) {
            return new Vec3(x + other.x, y + other.y, z + other.z);
        }

        private Vec3 subtract(Vec3 other) {
            return new Vec3(x - other.x, y - other.y, z - other.z);
        }

        private Vec3 scale(double value) {
            return new Vec3(x * value, y * value, z * value);
        }

        private Vec3 cross(Vec3 other) {
            return new Vec3(
                y * other.z - z * other.y,
                z * other.x - x * other.z,
                x * other.y - y * other.x
            );
        }

        public double length() {
            return Math.sqrt(x * x + y * y + z * z);
        }

        private Vec3 normalized() {
            double magnitude = length();
            if (!Double.isFinite(magnitude) || magnitude <= 1e-12) {
                throw new IllegalArgumentException("cannot normalize zero preview vector");
            }

            return new Vec3(x / magnitude, y / magnitude, z / magnitude);
        }
    }
}
