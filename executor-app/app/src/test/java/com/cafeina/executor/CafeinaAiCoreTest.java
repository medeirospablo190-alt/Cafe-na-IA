package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;
import java.util.Arrays;
import java.util.Collections;

public final class CafeinaAiCoreTest {
    @Test public void requestRequiresProjectAndMessage() {
        assertThrows(IllegalArgumentException.class, () -> new CafeinaAiCore.Request(" ", "hi", null));
        assertThrows(IllegalArgumentException.class, () -> new CafeinaAiCore.Request("p", " ", null));
    }

    @Test public void capabilityListsAreImmutable() {
        CafeinaAiCore.Request request = new CafeinaAiCore.Request("p", "hi", Arrays.asList("knowledge.read"));
        assertEquals(Collections.singletonList("knowledge.read"), request.requestedCapabilities);
        assertThrows(UnsupportedOperationException.class, () -> request.requestedCapabilities.add("world.write"));
    }
}
