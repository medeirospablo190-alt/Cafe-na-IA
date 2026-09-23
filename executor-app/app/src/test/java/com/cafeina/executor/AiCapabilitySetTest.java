package com.cafeina.executor;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import java.util.Collections;

public final class AiCapabilitySetTest {
    @Test public void failsClosedByDefault() {
        AiCapabilitySet capabilities = AiCapabilitySet.none();
        assertFalse(capabilities.allows("world.write"));
        assertThrows(SecurityException.class, () -> capabilities.require("world.write"));
    }

    @Test public void grantsOnlyExactDeclaredCapability() {
        AiCapabilitySet capabilities = new AiCapabilitySet(Collections.singleton("knowledge.read"));
        assertTrue(capabilities.allows("knowledge.read"));
        assertFalse(capabilities.allows("knowledge.write"));
        assertThrows(SecurityException.class, () -> capabilities.require("knowledge.write"));
    }
}
