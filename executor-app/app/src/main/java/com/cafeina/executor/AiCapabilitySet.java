package com.cafeina.executor;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/** Fail-closed capability grant set for AI/tool orchestration. */
public final class AiCapabilitySet {
    private final Set<String> granted;

    public AiCapabilitySet(Set<String> granted) {
        LinkedHashSet<String> copy = new LinkedHashSet<>();
        if (granted != null) {
            for (String capability : granted) {
                if (capability == null || capability.trim().isEmpty()) throw new IllegalArgumentException("capability is required");
                copy.add(capability);
            }
        }
        this.granted = Collections.unmodifiableSet(copy);
    }

    public static AiCapabilitySet none() { return new AiCapabilitySet(Collections.emptySet()); }

    public boolean allows(String capability) {
        if (capability == null || capability.trim().isEmpty()) return false;
        return granted.contains(capability);
    }

    public Set<String> granted() { return granted; }

    public void require(String capability) {
        if (!allows(capability)) throw new SecurityException("capability not granted: " + capability);
    }
}
