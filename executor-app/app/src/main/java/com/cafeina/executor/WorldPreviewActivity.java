package com.cafeina.executor;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Surface;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;

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
import com.google.android.filament.VertexBuffer;
import com.google.android.filament.View;
import com.google.android.filament.Viewport;
import com.google.android.filament.android.ChoreographerHelper;
import com.google.android.filament.android.DisplayHelper;
import com.google.android.filament.android.FilamentHelper;
import com.google.android.filament.android.UiHelper;
import com.google.android.filament.filamat.MaterialBuilder;
import com.google.android.filament.filamat.MaterialPackage;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class WorldPreviewActivity extends Activity {
    public static final int SURFACE_VIEW_ID = 0x43414645;
    public static final int STATUS_VIEW_ID = 0x43414646;

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
    private int renderable;
    private int cameraEntity;
    private boolean destroyed;

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
        statusView.setText("WORLD PREVIEW • FILAMENT 1.77.1");
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(12f);
        statusView.setBackgroundColor(Color.argb(180, 12, 13, 16));
        statusView.setPadding(dp(12), dp(8), dp(12), dp(8));

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

        setContentView(root);

        try {
            setupSurface();
            setupFilament();
            setupScene();
            statusView.setText("WORLD PREVIEW • GPU READY");
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

        view.setScene(scene);
        view.setCamera(camera);
        view.setPostProcessingEnabled(false);
    }

    private void setupScene() {
        material = buildRuntimeMaterial();
        createTriangleMesh();

        renderable = EntityManager.get().create();

        new RenderableManager.Builder(1)
            .boundingBox(new Box(0f, 0f, 0f, 1f, 1f, 0.01f))
            .geometry(
                0,
                RenderableManager.PrimitiveType.TRIANGLES,
                vertexBuffer,
                indexBuffer,
                0,
                3
            )
            .material(0, material.getDefaultInstance())
            .build(engine, renderable);

        scene.addEntity(renderable);
    }

    private Material buildRuntimeMaterial() {
        MaterialBuilder.init();
        try {
            MaterialPackage materialPackage = new MaterialBuilder()
                .platform(MaterialBuilder.Platform.MOBILE)
                .name("CAFEINA Preview Vertex Color")
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

    private void createTriangleMesh() {
        final int floatBytes = 4;
        final int colorBytes = 4;
        final int vertexStride = 3 * floatBytes + colorBytes;

        ByteBuffer vertices = ByteBuffer
            .allocateDirect(3 * vertexStride)
            .order(ByteOrder.nativeOrder());

        putVertex(vertices, 0.0f, 1.0f, 0.0f, 0xffff7a18);
        putVertex(vertices, -0.9f, -0.7f, 0.0f, 0xff3b8bfe);
        putVertex(vertices, 0.9f, -0.7f, 0.0f, 0xff4acb71);
        vertices.flip();

        vertexBuffer = new VertexBuffer.Builder()
            .bufferCount(1)
            .vertexCount(3)
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

        ByteBuffer indices = ByteBuffer
            .allocateDirect(3 * 2)
            .order(ByteOrder.nativeOrder());
        indices.putShort((short) 0);
        indices.putShort((short) 1);
        indices.putShort((short) 2);
        indices.flip();

        indexBuffer = new IndexBuffer.Builder()
            .indexCount(3)
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

        if (renderable != 0) {
            scene.removeEntity(renderable);
            engine.destroyEntity(renderable);
            EntityManager.get().destroy(renderable);
            renderable = 0;
        }

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

            double zoom = 1.4;
            double aspect = (double) width / (double) height;
            camera.setProjection(
                Camera.Projection.ORTHO,
                -aspect * zoom,
                aspect * zoom,
                -zoom,
                zoom,
                0.0,
                10.0
            );

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
