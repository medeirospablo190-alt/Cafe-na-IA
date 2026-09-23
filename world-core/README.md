# CAFEÍNA World Core — Phase 9 foundation

Headless, platform-neutral world state for CAFEÍNA.

This module deliberately has no Android UI, renderer, physics engine, Luau dependency or network dependency.

## Current scope

- stable monotonic `ObjectId` values;
- object name;
- transform:
  - position;
  - rotation in degrees;
  - scale;
- create/find/update/remove;
- parent/child scene hierarchy with root objects;
- cycle and self-parent protection;
- non-destructive parent removal: direct children are preserved and moved to root;
- deterministic object and child snapshots ordered by ID;
- clearing a world without recycling IDs;
- standalone C++ smoke tests.

## Why IDs are not names

Names are editable human labels. Other systems will eventually need stable references for:

- scripts;
- scene graph relationships;
- contextual AI conversations;
- undo/redo;
- replay;
- snapshots;
- diffs;
- diagnostics.

Renaming an object therefore never changes its `ObjectId`.

## Explicitly not included yet

- components;
- rendering;
- physics;
- serialization;
- Android input;
- Luau World API;
- AI integration.

Those enter as separate tested phases so the headless data model remains reusable by Android, CLI tests and future desktop/notebook tooling.


## Phase 10.1 — Scene Graph foundation

`parentId = 0` represents the scene root.

Hierarchy rules:

- an object can be reparented without changing its stable `ObjectId`;
- missing parents fail without mutating the object;
- self-parenting is rejected;
- indirect cycles are rejected;
- `childrenOf(parentId)` is deterministic because the underlying registry is ID ordered;
- the base `removeObject()` operation is intentionally non-destructive to descendants: direct children move to root instead of being silently deleted.

An explicit subtree-delete operation can be added later with its own confirmation/transaction semantics.


## Phase 10.5 — versioned world persistence

World Core now supports deterministic JSON persistence.

Format identity:

- `format = CAFEINA_WORLD`
- `version = 1`

Persisted state includes:

- stable object IDs;
- next object ID;
- parent hierarchy;
- names;
- position;
- rotation;
- scale.

Safety rules:

- unsupported versions fail closed;
- input size is limited before parsing;
- object count is bounded during parsing;
- duplicate/zero/invalid IDs are rejected;
- missing parents and hierarchy cycles are rejected;
- non-finite transforms are rejected;
- restore validates into temporary state before replacing the active world;
- JSON round-trip is deterministic for the same world state.

### JSON dependency

World persistence uses `nlohmann/json` v3.12.0, fetched from the official release archive with a pinned SHA-256 in CMake. The project is open source and its primary class is MIT licensed; the upstream repository also documents bundled third-party licensing metadata. The dependency is build-time/library code only and does not add a server requirement.


## Phase 10.6 — synchronized WorldService

A shared scene should not be edited through raw `World*` pointers from unrelated threads.

`WorldService` is now the synchronized host-facing facade for one World instance.

It provides thread-safe single operations for:

- create/remove;
- read object snapshot;
- rename;
- transform;
- reparent;
- children lookup;
- object listing;
- state snapshot/restore;
- clear.

The underlying `World` remains the deterministic data model. `WorldService` owns synchronization.

This is deliberately not a multi-operation transaction system yet. Transactions/preview/undo will build above this boundary later.

### Build separation

The CMake project now separates:

- `cafeina_world_core`: World + WorldService, no JSON dependency;
- `cafeina_world_serialization`: optional JSON persistence target.

This lets the runtime/Android bridge link only the core model when persistence is not required in that binary path.
