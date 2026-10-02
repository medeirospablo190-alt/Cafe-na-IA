package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

public final class LaboratoryTestWorldTest {
    @Test
    public void fixtureIsVersionedImmutableAndIndependentFromGameplayScene() {
        assertEquals("world-geometry-v1", LaboratoryTestWorld.FIXTURE_ID);
        assertEquals(11, LaboratoryTestWorld.blocks().size());
        assertEquals(64, LaboratoryTestWorld.fixtureSha256().length());
        assertEquals(LaboratoryTestWorld.fixtureSha256(),
            LaboratoryTestWorld.fixtureSha256());
        assertThrows(UnsupportedOperationException.class,
            () -> LaboratoryTestWorld.blocks().clear());
    }

    @Test
    public void solidAndTriggerContactsAreDeterministicInMillimeters() {
        assertEquals("solids=Chao;zones=ZonaVerde",
            LaboratoryTestWorld.contact("0,20,-4200,100,100,100").outputLine());
        assertEquals("solids=PortaEvento;zones=-",
            LaboratoryTestWorld.contact("0,1650,0,340,825,340").outputLine());
        assertEquals("solids=-;zones=-",
            LaboratoryTestWorld.contact("0,1650,410,100,100,100").outputLine());
        assertEquals("solids=-;zones=-",
            LaboratoryTestWorld.contact("0,20000,30000,100,100,100").outputLine());
    }

    @Test
    public void parserRejectsInvalidOrUnboundedGeneratedInputs() {
        for (String invalid : Arrays.asList("", "0,0,0", "0,0,0,0,1,1",
                "100001,0,0,1,1,1", "0,0,0,99999,1,1",
                "2147483648,0,0,1,1,1", "0,0,0,1,1,1;fs.write()",
                "0,0,0,1,1,1\n0,0,0,1,1,1")) {
            assertThrows(IllegalArgumentException.class,
                () -> LaboratoryTestWorld.parseProbe(invalid));
        }
    }

    @Test
    public void worldProbeUsesBoundedHarnessAndRecordsCompositeEnvironmentHash() {
        LaboratoryEngine.Request request = new LaboratoryEngine.Request(
            LaboratoryEngine.WORLD_CONTACT_TOOL, LaboratoryEngine.WORLD_CONTACT_VERSION,
            1234, 1000,
            Arrays.asList(
                new LaboratoryEngine.TestCase("floor-and-zone",
                    "0,20,-4200,100,100,100", "solids=Chao;zones=ZonaVerde"),
                new LaboratoryEngine.TestCase("mismatch",
                    "0,1650,0,340,825,340", "solids=-;zones=-")
            ));
        LaboratoryEngine.Report report =
            LaboratoryEngine.run(request, new LaboratoryEngine.Cancellation());
        assertEquals(LaboratoryEngine.Status.FAIL, report.status);
        assertEquals(1, report.passed);
        assertEquals(1, report.failed);
        String expectedEnvironmentIdentity =
            "CAFEINA_HOST_LAB_V1|"
                + LaboratoryEngine.WORLD_CONTACT_TOOL
                + "|"
                + LaboratoryEngine.WORLD_CONTACT_VERSION
                + "|fixture="
                + LaboratoryTestWorld.fixtureSha256();
        String expectedEnvironmentSha256 =
            LaboratoryEngine.fingerprint(expectedEnvironmentIdentity)
                .substring(7, 71);
        assertEquals(expectedEnvironmentSha256, report.environmentSha256);
        assertFalse(
            LaboratoryTestWorld.fixtureSha256()
                .equals(report.environmentSha256));
        assertTrue(report.checks.get(0).passed);
        assertFalse(report.checks.get(1).passed);
        assertEquals("solids=PortaEvento;zones=-", report.checks.get(1).actualOutput);
    }

    @Test
    public void cannotPassSourceCodeOrUnknownWorldFixtureIntoBuiltInTool() {
        assertThrows(IllegalArgumentException.class, () -> new LaboratoryEngine.Request(
            LaboratoryEngine.WORLD_CONTACT_TOOL, "999", 0, 1000,
            Collections.singletonList(new LaboratoryEngine.TestCase(
                "unknown", "0,0,0,1,1,1", "anything"))));
        assertThrows(IllegalArgumentException.class, () -> new LaboratoryEngine.Request(
            LaboratoryEngine.WORLD_CONTACT_TOOL, LaboratoryEngine.WORLD_CONTACT_VERSION,
            0, 1000, Collections.singletonList(new LaboratoryEngine.TestCase(
                "code", "print('not geometry')", "anything"))));
    }
}
