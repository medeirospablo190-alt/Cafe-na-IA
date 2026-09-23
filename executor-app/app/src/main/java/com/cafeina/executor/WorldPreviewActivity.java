package com.cafeina.executor;

import android.app.Activity;
import android.graphics.Color;
import android.opengl.Matrix;
import android.os.Bundle;
import android.view.Gravity;
import android.view.Surface;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;

import com.cafeina.runtime.LuauBridge;

import com.google.android.filament.Box;
import com.google.android.filament.Camera;
import com.google.android.filament.Engine;
import com.google.android.filament.EntityManager;
import com.google.android.filament.IndexBuffer;
import com.google.android.filament.Material;
import com.google.android.filament.RenderableManager;
import com.google.android.filament.Renderer;
import com.google.android.filament.Scene;
import com.google.android.filament.SwapChain;
import com.google.android.filament.TransformManager;
import com.google.android.filament.VertexBuffer;
import com.google.android.filament.View;
import com.google.android.filament.Viewport;
import com.google.android.filament.android.ChoreographerHelper;
import com.google.android.filament.android.DisplayHelper;
import com.google.android.filament.android.FilamentHelper;
import com.google.android.filament.android.UiHelper;
import com.google.android.filament.filamat.MaterialBuilder;
import com.google.android.filament.filamat.MaterialPackage;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

public final class WorldPreviewActivity extends Activity {
    public static final int SURFACE_VIEW_ID = 0x43414645;
    public static final int STATUS_VIEW_ID = 0x43414646;
    public static final int CAMERA_HINT_VIEW_ID = 0x43414647;

    private static final String TAG = "CafeinaWorldPreview";

    static {
        com.google.android.filament.Filament.init();
    }

    private SurfaceView surfaceView;
    private TextView statusView;
    private UiHelper uiHelper;
    private DisplayHelper displayHelper;

    private Engine engine;
    private Renderer renderer;
    private Scene scene;
    private View view;
    private Camera camera;
    private Material material;
    private VertexBuffer vertexBuffer;
    private IndexBuffer indexBuffer;
    private SwapChain swapChain;
    private int cameraEntity;
    private boolean destroyed;

    private final OrbitCameraState cameraState = new OrbitCameraState();
    private PreviewCameraController cameraController;
    private final List<Integer> renderables = new ArrayList<>();
    private final PreviewFrameCallback frameCallback = new PreviewFrameCallback();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().setStatusBarColor(Color.rgb(12, 13, 16));
        getWindow().setNavigationBarColor(Color.rgb(12, 13, 16));

        surfaceView = new SurfaceView(this);
        surfaceView.setId(SURFACE_VIEW_ID);

        statusView = new TextView(this);
        statusView.setId(STATUS_VIEW_ID);
        statusView.setText("WORLD PREVIEW • FILAMENT 1.75.1");
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(12f);
        statusView.setBackgroundColor(Color.argb(180, 12, 13, 16));
        statusView.setPadding(dp(12), dp(8), dp(12), dp(8));

        TextView cameraHintView = new TextView(this);
        cameraHintView.setId(CAMERA_HINT_VIEW_ID);
        cameraHintView.setText("1 dedo: orbitar  •  pinça: zoom  •  2 dedos: mover");
        cameraHintView.setTextColor(Color.rgb(220, 223, 230));
        cameraHintView.setTextSize(11f);
        cameraHintView.setBackgroundColor(Color.argb(150, 12, 13, 16));
        cameraHintView.setPadding(dp(10), dp(6), dp(10), dp(6));

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(9, 10, 13));
        root.addView(surfaceView, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ));

        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        root.addView(statusView, statusParams);

        Button resetCameraButton = new Button(this);
        resetCameraButton.setText("RESET CAM");
        resetCameraButton.setTextSize(11f);
        resetCameraButton.setAllCaps(false);
        resetCameraButton.setTextColor(Color.WHITE);
        resetCameraButton.setBackgroundColor(Color.argb(190, 30, 34, 43));
        resetCameraButton.setPadding(dp(10), dp(4), dp(10), dp(4));

        FrameLayout.LayoutParams resetParams = new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            dp(40)
        );
        resetParams.gravity = Gravity.TOP | Gravity.END;
        resetParams.setMargins(0, dp(44), dp(10), 0);
        root.addView(resetCameraButton, resetParams);

        FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
        hintParams.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        hintParams.setMargins(dp(10), 0, dp(10), dp(12));
        root.addView(cameraHintView, hintParams);

        cameraController = new PreviewCameraController(
            this,
            cameraState,
            this::applyCameraPose
        );
        surfaceView.setOnTouchListener(cameraController);
        resetCameraButton.setOnClickListener(v -> cameraController.reset());

        setContentView(root);

        try {
            setupSurface();
            setupFilament();
            int renderedItems = setupSceneFromSharedWorld();
            statusView.setText(
                "WORLD PREVIEW • GPU READY • " + renderedItems + " item(s)"
            );
        } catch (Throwable error) {
            statusView.setText("WORLD PREVIEW • INIT ERROR: " + safeMessage(error));
            android.util.Log.e(TAG, "Filament preview initialization failed", error);
            cleanupFilament();
        }
    }

    private void setupSurface() {
        displayHelper = new DisplayHelper(this);
        uiHelper = new UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK);
        uiHelper.setRenderCallback(new PreviewSurfaceCallback());
        uiHelper.attachTo(surfaceView);
    }

    private void setupFilament() {
        engine = Engine.create();
        renderer = engine.createRenderer();
        frameCallback.setRenderer(renderer);
        scene = engine.createScene();
        view = engine.createView();

        cameraEntity = EntityManager.get().create();
        camera = engine.createCamera(cameraEntity);
        applyCameraPose(cameraState.pose());

        view.setScene(scene);
        view.setCamera(camera);
        view.setPostProcessingEnabled(false);
    }

    private int setupSceneFromSharedWorld() throws Exception {
        material = buildRuntimeMaterial();
        createBoxMesh();

        JSONObject snapshot = new JSONObject(LuauBridge.nativeRenderSceneSnapshot());
        if (!snapshot.optBoolean("ok", false)) {
            throw new IllegalStateException(
                "RenderScene snapshot failed: " + snapshot.optString("error", "unknown error")
            );
        }

        JSONArray items = snapshot.optJSONArray("items");
        if (items == null) {
            throw new IllegalStateException("RenderScene snapshot has no items array");
        }

        frameCameraToItems(items);

        int renderedCount = 0;
        int unsupportedCount = 0;

        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.getJSONObject(i);
            String primitive = item.optString("primitive", "");

            if (!"box".equals(primitive)) {
                unsupportedCount++;
                continue;
            }

            int entity = createBoxRenderable(item);
            renderables.add(entity);
            scene.addEntity(entity);
            renderedCount++;
        }

        if (unsupportedCount > 0) {
            android.util.Log.i(
                TAG,
                "Skipped " + unsupportedCount + " unsupported primitive(s) in bootstrap renderer"
            );
        }

        return renderedCount;
    }

    private void frameCameraToItems(JSONArray items) throws Exception {
        boolean hasBounds = false;
        double minX = 0.0;
        double minY = 0.0;
        double minZ = 0.0;
        double maxX = 0.0;
        double maxY = 0.0;
        double maxZ = 0.0;

        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.getJSONObject(i);
            if (!"box".equals(item.optString("primitive", ""))) {
                continue;
            }

            JSONArray matrix = item.optJSONArray("worldMatrix");
            JSONArray scale = item.getJSONArray("scale");

            double x;
            double y;
            double z;

            if (matrix != null && matrix.length() == 16) {
                x = matrix.getDouble(12);
                y = matrix.getDouble(13);
                z = matrix.getDouble(14);
            } else {
                JSONArray position = item.getJSONArray("position");
                x = position.getDouble(0);
                y = position.getDouble(1);
                z = position.getDouble(2);
            }

            double sx = Math.abs(scale.getDouble(0));
            double sy = Math.abs(scale.getDouble(1));
            double sz = Math.abs(scale.getDouble(2));

            double radius = 0.5 * Math.sqrt(sx * sx + sy * sy + sz * sz);

            if (!hasBounds) {
                minX = x - radius;
                minY = y - radius;
                minZ = z - radius;
                maxX = x + radius;
                maxY = y + radius;
                maxZ = z + radius;
                hasBounds = true;
            } else {
                minX = Math.min(minX, x - radius);
                minY = Math.min(minY, y - radius);
                minZ = Math.min(minZ, z - radius);
                maxX = Math.max(maxX, x + radius);
                maxY = Math.max(maxY, y + radius);
                maxZ = Math.max(maxZ, z + radius);
            }
        }

        if (!hasBounds) {
            return;
        }

        double centerX = (minX + maxX) * 0.5;
        double centerY = (minY + maxY) * 0.5;
        double centerZ = (minZ + maxZ) * 0.5;

        double dx = maxX - minX;
        double dy = maxY - minY;
        double dz = maxZ - minZ;
        double radius = 0.5 * Math.sqrt(dx * dx + dy * dy + dz * dz);

        cameraState.frameBounds(centerX, centerY, centerZ, radius);
        applyCameraPose(cameraState.pose());
    }

    private int createBoxRenderable(JSONObject item) throws Exception {
        int entity = EntityManager.get().create();

        new RenderableManager.Builder(1)
            .boundingBox(new Box(0f, 0f, 0f, 0.5f, 0.5f, 0.5f))
            .geometry(
                0,
                RenderableManager.PrimitiveType.TRIANGLES,
                vertexBuffer,
                indexBuffer,
                0,
                36
            )
            .material(0, material.getDefaultInstance())
            .build(engine, entity);

        applyTransform(entity, item);
        return entity;
    }

    private void applyTransform(int entity, JSONObject item) throws Exception {
        float[] transform = new float[16];

        JSONArray worldMatrix = item.optJSONArray("worldMatrix");
        if (worldMatrix != null && worldMatrix.length() == 16) {
            for (int i = 0; i < 16; i++) {
                transform[i] = (float) worldMatrix.getDouble(i);
            }
        } else {
            JSONArray position = item.getJSONArray("position");
            JSONArray rotation = item.getJSONArray("rotationDegrees");
            JSONArray scale = item.getJSONArray("scale");

            Matrix.setIdentityM(transform, 0);
            Matrix.translateM(
                transform,
                0,
                (float) position.getDouble(0),
                (float) position.getDouble(1),
                (float) position.getDouble(2)
            );
            Matrix.rotateM(transform, 0, (float) rotation.getDouble(2), 0f, 0f, 1f);
            Matrix.rotateM(transform, 0, (float) rotation.getDouble(1), 0f, 1f, 0f);
            Matrix.rotateM(transform, 0, (float) rotation.getDouble(0), 1f, 0f, 0f);
            Matrix.scaleM(
                transform,
                0,
                (float) scale.getDouble(0),
                (float) scale.getDouble(1),
                (float) scale.getDouble(2)
            );
        }

        TransformManager transformManager = engine.getTransformManager();
        transformManager.setTransform(
            transformManager.getInstance(entity),
            transform
        );
    }

    private void applyCameraPose(OrbitCameraState.CameraPose pose) {
        if (camera == null || destroyed) {
            return;
        }

        camera.lookAt(
            pose.eyeX,
            pose.eyeY,
            pose.eyeZ,
            pose.targetX,
            pose.targetY,
            pose.targetZ,
            0.0,
            1.0,
            0.0
        );
    }

    private Material buildRuntimeMaterial() {
        MaterialBuilder.init();
        try {
            MaterialPackage materialPackage = new MaterialBuilder()
                .platform(MaterialBuilder.Platform.MOBILE)
                .name("CAFEINA World Box")
                .shading(MaterialBuilder.Shading.UNLIT)
                .require(MaterialBuilder.VertexAttribute.COLOR)
                .material(
                    "void material(inout MaterialInputs material) {\n" +
                    "    prepareMaterial(material);\n" +
                    "    material.baseColor = getColor();\n" +
                    "}\n"
                )
                .optimization(MaterialBuilder.Optimization.NONE)
                .build(engine);

            if (!materialPackage.isValid()) {
                throw new IllegalStateException("Filament rejected runtime preview material");
            }

            ByteBuffer buffer = materialPackage.getBuffer();
            return new Material.Builder()
                .payload(buffer, buffer.remaining())
                .build(engine);
        } finally {
            MaterialBuilder.shutdown();
        }
    }

    private void createBoxMesh() {
        final int floatBytes = 4;
        final int colorBytes = 4;
        final int vertexStride = 3 * floatBytes + colorBytes;

        ByteBuffer vertices = ByteBuffer
            .allocateDirect(8 * vertexStride)
            .order(ByteOrder.nativeOrder());

        putVertex(vertices, -0.5f, -0.5f, -0.5f, 0xffff7a18);
        putVertex(vertices,  0.5f, -0.5f, -0.5f, 0xff3b8bfe);
        putVertex(vertices,  0.5f,  0.5f, -0.5f, 0xff4acb71);
        putVertex(vertices, -0.5f,  0.5f, -0.5f, 0xffffc44a);
        putVertex(vertices, -0.5f, -0.5f,  0.5f, 0xffb875ff);
        putVertex(vertices,  0.5f, -0.5f,  0.5f, 0xff4acbd3);
        putVertex(vertices,  0.5f,  0.5f,  0.5f, 0xffff6680);
        putVertex(vertices, -0.5f,  0.5f,  0.5f, 0xff8da1ff);
        vertices.flip();

        vertexBuffer = new VertexBuffer.Builder()
            .bufferCount(1)
            .vertexCount(8)
            .attribute(
                VertexBuffer.VertexAttribute.POSITION,
                0,
                VertexBuffer.AttributeType.FLOAT3,
                0,
                vertexStride
            )
            .attribute(
                VertexBuffer.VertexAttribute.COLOR,
                0,
                VertexBuffer.AttributeType.UBYTE4,
                3 * floatBytes,
                vertexStride
            )
            .normalized(VertexBuffer.VertexAttribute.COLOR)
            .build(engine);

        vertexBuffer.setBufferAt(engine, 0, vertices);

        short[] cubeIndices = new short[] {
            0, 1, 2, 0, 2, 3,
            5, 4, 7, 5, 7, 6,
            4, 0, 3, 4, 3, 7,
            1, 5, 6, 1, 6, 2,
            3, 2, 6, 3, 6, 7,
            4, 5, 1, 4, 1, 0
        };

        ByteBuffer indices = ByteBuffer
            .allocateDirect(cubeIndices.length * 2)
            .order(ByteOrder.nativeOrder());

        for (short index : cubeIndices) {
            indices.putShort(index);
        }
        indices.flip();

        indexBuffer = new IndexBuffer.Builder()
            .indexCount(cubeIndices.length)
            .bufferType(IndexBuffer.Builder.IndexType.USHORT)
            .build(engine);
        indexBuffer.setBuffer(engine, indices);
    }

    private static void putVertex(
        ByteBuffer buffer,
        float x,
        float y,
        float z,
        int rgba
    ) {
        buffer.putFloat(x);
        buffer.putFloat(y);
        buffer.putFloat(z);
        buffer.putInt(rgba);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (engine != null && !destroyed) {
            frameCallback.post();
        }
    }

    @Override
    protected void onPause() {
        if (engine != null) {
            frameCallback.remove();
        }
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        cleanupFilament();
        super.onDestroy();
    }

    private void cleanupFilament() {
        if (destroyed) return;
        destroyed = true;

        frameCallback.remove();

        if (uiHelper != null) {
            uiHelper.detach();
        }

        if (engine == null) {
            return;
        }

        if (swapChain != null) {
            engine.destroySwapChain(swapChain);
            swapChain = null;
        }

        for (int entity : renderables) {
            if (scene != null) {
                scene.removeEntity(entity);
            }
            engine.destroyEntity(entity);
            EntityManager.get().destroy(entity);
        }
        renderables.clear();

        if (vertexBuffer != null) engine.destroyVertexBuffer(vertexBuffer);
        if (indexBuffer != null) engine.destroyIndexBuffer(indexBuffer);
        if (material != null) engine.destroyMaterial(material);
        if (renderer != null) engine.destroyRenderer(renderer);
        if (view != null) engine.destroyView(view);
        if (scene != null) engine.destroyScene(scene);

        if (camera != null) {
            engine.destroyCameraComponent(camera.getEntity());
        }
        if (cameraEntity != 0) {
            EntityManager.get().destroy(cameraEntity);
            cameraEntity = 0;
        }

        engine.destroy();
        engine = null;
    }

    private final class PreviewFrameCallback extends ChoreographerHelper {
        @Override
        public void onFrame(long frameTimeNanos) {
            if (
                !destroyed
                    && uiHelper != null
                    && uiHelper.isReadyToRender()
                    && renderer != null
                    && swapChain != null
            ) {
                if (renderer.beginFrame(swapChain, frameTimeNanos)) {
                    renderer.render(view);
                    renderer.endFrame();
                }
            }
        }
    }

    private final class PreviewSurfaceCallback implements UiHelper.RendererCallback {
        @Override
        public void onNativeWindowChanged(Surface surface) {
            if (engine == null || destroyed) return;

            if (swapChain != null) {
                engine.destroySwapChain(swapChain);
            }

            swapChain = engine.createSwapChain(surface, uiHelper.getSwapChainFlags());
            displayHelper.attach(renderer, surfaceView.getDisplay());
        }

        @Override
        public void onDetachedFromSurface() {
            if (displayHelper != null) {
                displayHelper.detach();
            }

            if (engine != null && swapChain != null) {
                engine.destroySwapChain(swapChain);
                engine.flushAndWait();
                swapChain = null;
            }
        }

        @Override
        public void onResized(int width, int height) {
            if (camera == null || view == null || engine == null || height == 0) return;

            double aspect = (double) width / (double) height;
            camera.setProjection(45.0, aspect, 0.1, 100.0, Camera.Fov.VERTICAL);
            view.setViewport(new Viewport(0, 0, width, height));
            FilamentHelper.synchronizePendingFrames(engine);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static String safeMessage(Throwable error) {
        String message = error.getMessage();
        if (message == null || message.isBlank()) {
            return error.getClass().getSimpleName();
        }
        return message;
    }
}
