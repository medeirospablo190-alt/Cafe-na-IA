package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class PreviewRayMathTest {
    private static final double EPSILON = 0.0001;

    @Test
    public void centerScreenRayPointsAtCameraTarget() {
        OrbitCameraState state = new OrbitCameraState();
        OrbitCameraState.CameraPose pose = state.pose();

        PreviewRayMath.Ray ray = PreviewRayMath.fromScreen(
            pose,
            500.0,
            500.0,
            1000.0,
            1000.0,
            45.0
        );

        double targetX = pose.targetX - pose.eyeX;
        double targetY = pose.targetY - pose.eyeY;
        double targetZ = pose.targetZ - pose.eyeZ;
        double targetLength = Math.sqrt(
            targetX * targetX
                + targetY * targetY
                + targetZ * targetZ
        );

        assertEquals(targetX / targetLength, ray.direction.x, EPSILON);
        assertEquals(targetY / targetLength, ray.direction.y, EPSILON);
        assertEquals(targetZ / targetLength, ray.direction.z, EPSILON);
        assertEquals(1.0, ray.direction.length(), EPSILON);
    }

    @Test
    public void oppositeScreenSidesProduceDifferentWorldDirections() {
        OrbitCameraState state = new OrbitCameraState();
        OrbitCameraState.CameraPose pose = state.pose();

        PreviewRayMath.Ray left = PreviewRayMath.fromScreen(
            pose,
            0.0,
            500.0,
            1000.0,
            1000.0,
            45.0
        );

        PreviewRayMath.Ray right = PreviewRayMath.fromScreen(
            pose,
            1000.0,
            500.0,
            1000.0,
            1000.0,
            45.0
        );

        double difference =
            Math.abs(left.direction.x - right.direction.x)
                + Math.abs(left.direction.y - right.direction.y)
                + Math.abs(left.direction.z - right.direction.z);

        assertTrue(difference > 0.1);
        assertEquals(1.0, left.direction.length(), EPSILON);
        assertEquals(1.0, right.direction.length(), EPSILON);
    }

    @Test(expected = IllegalArgumentException.class)
    public void zeroViewportIsRejected() {
        OrbitCameraState state = new OrbitCameraState();

        PreviewRayMath.fromScreen(
            state.pose(),
            0.0,
            0.0,
            0.0,
            1000.0,
            45.0
        );
    }

    @Test(expected = IllegalArgumentException.class)
    public void invalidFovIsRejected() {
        OrbitCameraState state = new OrbitCameraState();

        PreviewRayMath.fromScreen(
            state.pose(),
            100.0,
            100.0,
            1000.0,
            1000.0,
            180.0
        );
    }
}
