package com.cafeina.executor;

public final class OrbitCameraState {
    public static final double MIN_DISTANCE = 2.0;
    public static final double MAX_DISTANCE = 40.0;
    public static final double MIN_PITCH_DEGREES = -80.0;
    public static final double MAX_PITCH_DEGREES = 80.0;

    private double targetX;
    private double targetY;
    private double targetZ;

    private double yawDegrees = 35.0;
    private double pitchDegrees = 25.0;
    private double distance = 10.0;

    private double homeTargetX;
    private double homeTargetY;
    private double homeTargetZ;
    private double homeDistance = 10.0;

    public synchronized void orbit(double deltaPixelsX, double deltaPixelsY) {
        yawDegrees = wrapDegrees(yawDegrees + deltaPixelsX * 0.35);
        pitchDegrees = clamp(
            pitchDegrees - deltaPixelsY * 0.30,
            MIN_PITCH_DEGREES,
            MAX_PITCH_DEGREES
        );
    }

    public synchronized void zoom(double scaleFactor) {
        if (!Double.isFinite(scaleFactor) || scaleFactor <= 0.0) {
            return;
        }

        distance = clamp(distance / scaleFactor, MIN_DISTANCE, MAX_DISTANCE);
    }

    public synchronized void pan(
        double deltaPixelsX,
        double deltaPixelsY,
        double viewportHeightPixels
    ) {
        if (!Double.isFinite(viewportHeightPixels) || viewportHeightPixels <= 0.0) {
            return;
        }

        double worldPerPixel = (distance * 1.5) / viewportHeightPixels;
        double dx = -deltaPixelsX * worldPerPixel;
        double dy = deltaPixelsY * worldPerPixel;

        double yawRadians = Math.toRadians(yawDegrees);
        double rightX = Math.cos(yawRadians);
        double rightZ = -Math.sin(yawRadians);

        targetX += rightX * dx;
        targetZ += rightZ * dx;
        targetY += dy;
    }

    public synchronized void frameBounds(
        double centerX,
        double centerY,
        double centerZ,
        double radius
    ) {
        if (
            !Double.isFinite(centerX)
                || !Double.isFinite(centerY)
                || !Double.isFinite(centerZ)
                || !Double.isFinite(radius)
                || radius < 0.0
        ) {
            return;
        }

        targetX = centerX;
        targetY = centerY;
        targetZ = centerZ;
        distance = clamp(
            Math.max(MIN_DISTANCE, radius * 2.8 + 1.0),
            MIN_DISTANCE,
            MAX_DISTANCE
        );
        yawDegrees = 35.0;
        pitchDegrees = 25.0;

        homeTargetX = targetX;
        homeTargetY = targetY;
        homeTargetZ = targetZ;
        homeDistance = distance;
    }

    public synchronized CameraPose pose() {
        double yawRadians = Math.toRadians(yawDegrees);
        double pitchRadians = Math.toRadians(pitchDegrees);

        double horizontalDistance = distance * Math.cos(pitchRadians);

        double eyeX = targetX + horizontalDistance * Math.sin(yawRadians);
        double eyeY = targetY + distance * Math.sin(pitchRadians);
        double eyeZ = targetZ + horizontalDistance * Math.cos(yawRadians);

        return new CameraPose(
            eyeX,
            eyeY,
            eyeZ,
            targetX,
            targetY,
            targetZ,
            yawDegrees,
            pitchDegrees,
            distance
        );
    }

    public synchronized void reset() {
        targetX = homeTargetX;
        targetY = homeTargetY;
        targetZ = homeTargetZ;
        yawDegrees = 35.0;
        pitchDegrees = 25.0;
        distance = homeDistance;
    }

    private static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }

    private static double wrapDegrees(double value) {
        double wrapped = value % 360.0;
        return wrapped < 0.0 ? wrapped + 360.0 : wrapped;
    }

    public static final class CameraPose {
        public final double eyeX;
        public final double eyeY;
        public final double eyeZ;
        public final double targetX;
        public final double targetY;
        public final double targetZ;
        public final double yawDegrees;
        public final double pitchDegrees;
        public final double distance;

        private CameraPose(
            double eyeX,
            double eyeY,
            double eyeZ,
            double targetX,
            double targetY,
            double targetZ,
            double yawDegrees,
            double pitchDegrees,
            double distance
        ) {
            this.eyeX = eyeX;
            this.eyeY = eyeY;
            this.eyeZ = eyeZ;
            this.targetX = targetX;
            this.targetY = targetY;
            this.targetZ = targetZ;
            this.yawDegrees = yawDegrees;
            this.pitchDegrees = pitchDegrees;
            this.distance = distance;
        }
    }
}
