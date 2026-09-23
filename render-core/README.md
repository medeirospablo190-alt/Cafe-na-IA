# CAFEÍNA Render Core

Backend-neutral render scene extraction for CAFEÍNA.

This module is intentionally smaller than a renderer. It converts validated World Core state into a deterministic immutable snapshot that a GPU backend can consume.

## Current contract

World Core remains the source of truth.

`RenderSceneBuilder` reads a `WorldState` and emits ordered `RenderItem` records containing:

- stable `ObjectId`;
- primitive mesh type;
- transform.

Only objects with a visible `MeshComponent` become render items.

Objects without meshes remain valid world objects for logic, triggers, semantics and future systems.

## Why this layer exists

The World model must not depend on Android surfaces, OpenGL, Vulkan, Filament or another graphics backend.

The flow is:

```text
WorldService
  -> WorldState snapshot
  -> RenderSceneBuilder
  -> RenderScene
  -> graphics backend
```

That keeps the same scene usable by:

- Android rendering;
- headless tests;
- future desktop/notebook renderer;
- thumbnails;
- offscreen test rendering;
- visual regression tooling.

## Not included yet

- GPU backend;
- camera;
- materials;
- lighting;
- textures;
- local/world transform propagation;
- picking;
- Android SurfaceView integration.

Those remain separate layers above this contract.
