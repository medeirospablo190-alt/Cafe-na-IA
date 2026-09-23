# Third-party dependencies

## Google Filament

- Purpose: Android graphics backend bootstrap for the CAFEÍNA World Preview.
- Version: 1.75.1.
- Upstream: https://github.com/google/filament
- Release date: 2026-09-21.
- Maven artifacts:
  - `com.google.android.filament:filament-android:1.75.1`
  - `com.google.android.filament:filamat-android:1.75.1` (bootstrap runtime material compilation only)
- License: Apache License 2.0.

The current bootstrap uses `filamat-android` to generate a tiny preview material at runtime. This is intentionally temporary; after the render path is stable, CAFEÍNA should prefer a material precompiled with the same Filament release and remove the runtime compiler from ordinary builds.
