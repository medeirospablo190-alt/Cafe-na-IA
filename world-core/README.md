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
