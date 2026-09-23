package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class OrbitCameraStateTest {
    private static final double EPSILON = 0.0001;

    @Test
    public void defaultPoseIsFiniteAndUsesExpectedDistance() {
        OrbitCameraState state = new OrbitCameraState();
        OrbitCameraState.CameraPose pose = state.pose();

        assertEquals(10.0, pose.distance, EPSILON);
        assertEquals(35.0, pose.yawDegrees, EPSILON);
        assertEquals(25.0, pose.pitchDegrees, EPSILON);
        assertTrue(Double.isFinite(pose.eyeX));
        assertTrue(Double.isFinite(pose.eyeY));
        assertTrue(Double.isFinite(pose.eyeZ));
    }

    @Test
    public void orbitWrapsYawAndClampsPitch() {
        OrbitCameraState state = new OrbitCameraState();

        state.orbit(2000.0, -2000.0);
        OrbitCameraState.CameraPose high = state.pose();

        assertTrue(high.yawDegrees >= 0.0 && high.yawDegrees < 360.0);
        assertEquals(
            OrbitCameraState.MAX_PITCH_DEGREES,
            high.pitchDegrees,
            EPSILON
        );

        state.orbit(0.0, 4000.0);
        OrbitCameraState.CameraPose low = state.pose();

        assertEquals(
            OrbitCameraState.MIN_PITCH_DEGREES,
            low.pitchDegrees,
            EPSILON
        );
    }

    @Test
    public void zoomClampsToSafeRange() {
        OrbitCameraState state = new OrbitCameraState();

        state.zoom(1000.0);
        assertEquals(
            OrbitCameraState.MIN_DISTANCE,
            state.pose().distance,
            EPSILON
        );

        state.zoom(0.00001);
        assertEquals(
            OrbitCameraState.MAX_DISTANCE,
            state.pose().distance,
            EPSILON
        );

        state.zoom(Double.NaN);
        assertEquals(
            OrbitCameraState.MAX_DISTANCE,
            state.pose().distance,
            EPSILON
        );
    }

    @Test
    public void panMovesTargetInCameraRelativeSpace() {
        OrbitCameraState state = new OrbitCameraState();

        OrbitCameraState.CameraPose before = state.pose();
        state.pan(120.0, -80.0, 1000.0);
        OrbitCameraState.CameraPose after = state.pose();

        assertTrue(
            Math.abs(after.targetX - before.targetX) > EPSILON
                || Math.abs(after.targetZ - before.targetZ) > EPSILON
        );
        assertTrue(Math.abs(after.targetY - before.targetY) > EPSILON);
    }

    @Test
    public void framingSceneBecomesNewResetHome() {
        OrbitCameraState state = new OrbitCameraState();

        state.frameBounds(12.0, 4.0, -8.0, 3.0);
        OrbitCameraState.CameraPose framed = state.pose();

        assertEquals(12.0, framed.targetX, EPSILON);
        assertEquals(4.0, framed.targetY, EPSILON);
        assertEquals(-8.0, framed.targetZ, EPSILON);
        assertTrue(framed.distance > OrbitCameraState.MIN_DISTANCE);

        state.orbit(200.0, 120.0);
        state.zoom(1.5);
        state.pan(50.0, 40.0, 600.0);
        state.reset();

        OrbitCameraState.CameraPose reset = state.pose();
        assertEquals(framed.targetX, reset.targetX, EPSILON);
        assertEquals(framed.targetY, reset.targetY, EPSILON);
        assertEquals(framed.targetZ, reset.targetZ, EPSILON);
        assertEquals(framed.distance, reset.distance, EPSILON);
        assertEquals(35.0, reset.yawDegrees, EPSILON);
        assertEquals(25.0, reset.pitchDegrees, EPSILON);
    }

    @Test
    public void resetRestoresCanonicalView() {
        OrbitCameraState state = new OrbitCameraState();

        state.orbit(500.0, 300.0);
        state.zoom(2.5);
        state.pan(100.0, 100.0, 500.0);
        state.reset();

        OrbitCameraState.CameraPose pose = state.pose();

        assertEquals(0.0, pose.targetX, EPSILON);
        assertEquals(0.0, pose.targetY, EPSILON);
        assertEquals(0.0, pose.targetZ, EPSILON);
        assertEquals(35.0, pose.yawDegrees, EPSILON);
        assertEquals(25.0, pose.pitchDegrees, EPSILON);
        assertEquals(10.0, pose.distance, EPSILON);
    }
}
