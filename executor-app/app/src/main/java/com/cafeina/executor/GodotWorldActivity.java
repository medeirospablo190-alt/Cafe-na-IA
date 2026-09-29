package com.cafeina.executor;

import org.godotengine.godot.GodotActivity;

/**
 * Hosts the first playable CAFEINA world in the installed Android app.
 * Runs in :world so the Godot engine and Luau JNI have independent process lifecycles.
 * The validated T14 Luau bridge/anti-cheat is NOT enabled until it can be safely ported.
 */
public final class GodotWorldActivity extends GodotActivity {
}
