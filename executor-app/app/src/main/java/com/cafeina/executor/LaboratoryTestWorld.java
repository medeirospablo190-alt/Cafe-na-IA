package com.cafeina.executor;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Pure JVM geometry fixture for internal tool tests; never opens or edits the
 * user's Godot World. Coordinates are integer millimeters for reproducible
 * AABB contact checks. It is NOT a substitute for Godot physics or rendering.
 */
public final class LaboratoryTestWorld {
    public static final String FIXTURE_ID = "world-geometry-v1";
    public static final String TOOL_ID = "world-contact";
    public static final String TOOL_VERSION = "0.1.0";
    public static final int MAX_COORDINATE_MM = 100_000;
    public static final int MAX_HALF_EXTENT_MM = 20_000;

    /** Frozen test-only copy of the eleven initial Godot scene block bounds. */
    private static final List<Box> BOXES = Collections.unmodifiableList(Arrays.asList(
        new Box("Chao", 0, -150, 0, 10000, 300, 16000, true),
        new Box("ParedeEsquerda", -3250, 1650, 0, 2500, 3300, 620, true),
        new Box("ParedeDireita", 3250, 1650, 0, 2500, 3300, 620, true),
        new Box("PortaEvento", 0, 1650, 0, 4000, 3300, 620, true),
        new Box("LinhaDeInicio", 0, 20, 3100, 5800, 35, 140, false),
        new Box("ZonaVerde", 0, 20, -4200, 3100, 35, 2000, false),
        new Box("ObstaculoBaixo", -2550, 370, 2050, 1550, 740, 580, true),
        new Box("PlataformaAzul", 2450, 2550, 1550, 1700, 220, 1650, true),
        new Box("MarcadorAltura", 3800, 2750, 1550, 120, 5500, 120, false),
        new Box("ZonaPorta", 0, 25, 1450, 4400, 40, 1250, false),
        new Box("ZonaGravidade", 2450, 25, -2450, 1700, 40, 2200, false)
    ));

    public static final class Box {
        public final String name;
        public final int xMm, yMm, zMm, widthMm, heightMm, depthMm;
        public final boolean solid;

        private Box(String name, int x, int y, int z, int width, int height,
                int depth, boolean solid) {
            this.name = name;
            this.xMm = x;
            this.yMm = y;
            this.zMm = z;
            this.widthMm = width;
            this.heightMm = height;
            this.depthMm = depth;
            this.solid = solid;
        }
    }

    public static final class Probe {
        public final int xMm, yMm, zMm, halfWidthMm, halfHeightMm, halfDepthMm;

        private Probe(int x, int y, int z, int hx, int hy, int hz) {
            this.xMm = x;
            this.yMm = y;
            this.zMm = z;
            this.halfWidthMm = hx;
            this.halfHeightMm = hy;
            this.halfDepthMm = hz;
        }
    }

    public static final class Contact {
        public final String fixtureSha256;
        public final List<String> solidNames;
        public final List<String> zoneNames;

        private Contact(List<String> solids, List<String> zones) {
            this.fixtureSha256 = LaboratoryTestWorld.fixtureSha256();
            this.solidNames = Collections.unmodifiableList(new ArrayList<>(solids));
            this.zoneNames = Collections.unmodifiableList(new ArrayList<>(zones));
        }

        public String outputLine() {
            return "solids=" + (solidNames.isEmpty() ? "-" : String.join(",", solidNames))
                + ";zones=" + (zoneNames.isEmpty() ? "-" : String.join(",", zoneNames));
        }
    }

    private LaboratoryTestWorld() {}

    public static List<Box> blocks() {
        return BOXES;
    }

    /**
     * Probe encoding: x,y,z,halfWidth,halfHeight,halfDepth in integer mm.
     * Bounded input prevents a generated tool from overloading the test parser.
     */
    public static Probe parseProbe(String encoded) {
        if (encoded == null || encoded.length() < 11 || encoded.length() > 96
                || !encoded.matches("-?[0-9]+(,-?[0-9]+){5}")) {
            throw new IllegalArgumentException("invalid world probe");
        }
        String[] parts = encoded.split(",", -1);
        int[] mm = new int[6];
        try {
            for (int i = 0; i < mm.length; i++) mm[i] = Integer.parseInt(parts[i]);
        } catch (NumberFormatException invalid) {
            throw new IllegalArgumentException("world probe exceeds integer limits", invalid);
        }
        for (int i = 0; i < 3; i++) {
            if (Math.abs((long) mm[i]) > MAX_COORDINATE_MM) {
                throw new IllegalArgumentException("world probe outside fixture budget");
            }
        }
        for (int i = 3; i < 6; i++) {
            if (mm[i] < 1 || mm[i] > MAX_HALF_EXTENT_MM) {
                throw new IllegalArgumentException("world probe has invalid extent");
            }
        }
        return new Probe(mm[0], mm[1], mm[2], mm[3], mm[4], mm[5]);
    }

    public static Contact contact(String encodedProbe) {
        return contact(parseProbe(encodedProbe));
    }

    public static Contact contact(Probe probe) {
        if (probe == null) throw new IllegalArgumentException("world probe missing");
        List<String> solids = new ArrayList<>();
        List<String> zones = new ArrayList<>();
        for (Box box : BOXES) {
            boolean touching = axisOverlap(probe.xMm, probe.halfWidthMm,
                    box.xMm, box.widthMm)
                && axisOverlap(probe.yMm, probe.halfHeightMm, box.yMm, box.heightMm)
                && axisOverlap(probe.zMm, probe.halfDepthMm, box.zMm, box.depthMm);
            if (touching) {
                (box.solid ? solids : zones).add(box.name);
            }
        }
        return new Contact(solids, zones);
    }

    /** Touching an AABB boundary exactly is not an overlap. */
    private static boolean axisOverlap(int center, int halfExtent,
            int boxCenter, int boxFullExtent) {
        return Math.abs((long) center - boxCenter) * 2L
            < (long) halfExtent * 2L + boxFullExtent;
    }

    public static String fixtureSha256() {
        StringBuilder serialized = new StringBuilder(FIXTURE_ID).append('\n');
        for (Box box : BOXES) {
            serialized.append(box.name).append('|')
                .append(box.xMm).append('|').append(box.yMm).append('|')
                .append(box.zMm).append('|').append(box.widthMm).append('|')
                .append(box.heightMm).append('|').append(box.depthMm).append('|')
                .append(box.solid).append('\n');
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                serialized.toString().getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte value : digest) {
                hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }
}
