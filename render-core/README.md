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


## World transform propagation

Render items now preserve both:

- the object's local `Transform`;
- a resolved column-major `worldMatrix`.

The world matrix is built as:

`parentWorld * translation * rotationZ * rotationY * rotationX * scale`

This matches the Android preview transform order while keeping the local transform available for editor/inspection tooling.

Hierarchy rules during render extraction:

- root objects use their local transform as world transform;
- child transforms are composed through all ancestors;
- parents do not need a MeshComponent to influence child rendering;
- missing parents fail closed;
- hierarchy cycles fail closed;
- invalid transforms anywhere in the resolved ancestry fail closed.

Graphics backends should consume `worldMatrix` for actual drawing. The local `transform` field remains useful for editor UI, diagnostics and serialization-aware tooling.
