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
- deterministic object snapshots ordered by ID;
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

- parent/child hierarchy;
- components;
- rendering;
- physics;
- serialization;
- Android input;
- Luau World API;
- AI integration.

Those enter as separate tested phases so the headless data model remains reusable by Android, CLI tests and future desktop/notebook tooling.
