package com.cafeina.executor;

import android.content.Context;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;

public final class PreviewCameraController implements View.OnTouchListener {
    public interface Listener {
        void onCameraChanged(OrbitCameraState.CameraPose pose);
    }

    private final OrbitCameraState state;
    private final Listener listener;
    private final ScaleGestureDetector scaleDetector;

    private float lastX;
    private float lastY;
    private float lastFocusX;
    private float lastFocusY;
    private boolean hasSinglePointer;
    private boolean hasMultiPointer;

    public PreviewCameraController(
        Context context,
        OrbitCameraState state,
        Listener listener
    ) {
        this.state = state;
        this.listener = listener;

        scaleDetector = new ScaleGestureDetector(
            context,
            new ScaleGestureDetector.SimpleOnScaleGestureListener() {
                @Override
                public boolean onScale(ScaleGestureDetector detector) {
                    state.zoom(detector.getScaleFactor());
                    dispatch();
                    return true;
                }
            }
        );
    }

    @Override
    public boolean onTouch(View view, MotionEvent event) {
        scaleDetector.onTouchEvent(event);

        switch (event.getActionMasked()) {
        case MotionEvent.ACTION_DOWN:
            hasSinglePointer = true;
            hasMultiPointer = false;
            lastX = event.getX();
            lastY = event.getY();
            return true;

        case MotionEvent.ACTION_POINTER_DOWN:
            if (event.getPointerCount() >= 2) {
                hasMultiPointer = true;
                hasSinglePointer = false;
                lastFocusX = focusX(event);
                lastFocusY = focusY(event);
            }
            return true;

        case MotionEvent.ACTION_MOVE:
            if (event.getPointerCount() >= 2) {
                float focusX = focusX(event);
                float focusY = focusY(event);

                if (hasMultiPointer && !scaleDetector.isInProgress()) {
                    state.pan(
                        focusX - lastFocusX,
                        focusY - lastFocusY,
                        Math.max(1, view.getHeight())
                    );
                    dispatch();
                }

                lastFocusX = focusX;
                lastFocusY = focusY;
                hasMultiPointer = true;
                hasSinglePointer = false;
                return true;
            }

            if (event.getPointerCount() == 1) {
                float x = event.getX();
                float y = event.getY();

                if (hasSinglePointer) {
                    state.orbit(x - lastX, y - lastY);
                    dispatch();
                }

                lastX = x;
                lastY = y;
                hasSinglePointer = true;
                hasMultiPointer = false;
                return true;
            }

            return true;

        case MotionEvent.ACTION_POINTER_UP:
            hasMultiPointer = false;
            hasSinglePointer = false;
            return true;

        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
            hasSinglePointer = false;
            hasMultiPointer = false;
            return true;

        default:
            return true;
        }
    }

    public void reset() {
        state.reset();
        dispatch();
    }

    public OrbitCameraState.CameraPose pose() {
        return state.pose();
    }

    private void dispatch() {
        listener.onCameraChanged(state.pose());
    }

    private static float focusX(MotionEvent event) {
        float total = 0f;
        for (int i = 0; i < event.getPointerCount(); i++) {
            total += event.getX(i);
        }
        return total / event.getPointerCount();
    }

    private static float focusY(MotionEvent event) {
        float total = 0f;
        for (int i = 0; i < event.getPointerCount(); i++) {
            total += event.getY(i);
        }
        return total / event.getPointerCount();
    }
}
