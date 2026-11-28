package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import static org.junit.jupiter.api.DynamicTest.dynamicTest;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

/**
 * The Java codec against every test vector of the reference glue (#23), read from the repository:
 * {@code analysis/data-codec/vettori/oracle-gnucobol.tsv} and {@code oracle-oltre-picture.tsv}.
 *
 * <p>Mandatory when the system property {@value #RUN_PROPERTY} is present ({@code ./verify.sh}
 * passes it to Maven and mounts the whole repository): a missing file is then a failure. Without
 * the property (image build, which copies only POMs, rules and modules) both factories are
 * disabled and reported as skipped; {@code verify.sh} checks in the report of its own run that
 * every vector of the two files was verified, by identifier and in order, and none skipped.
 */
class OracleGnuCobolVectorsTest {

    static final String RUN_PROPERTY = "menb.verify.run";
    static final String SKIP_REASON =
            "proprieta' menb.verify.run assente (build delle immagini): test dei vettori saltato";
    static final int EXPECTED_ROWS = 375;
    static final int EXPECTED_DECODE = 336;
    static final int EXPECTED_ENCODE = 39;
    static final int EXPECTED_ENCODE_OK = 25;
    static final int EXPECTED_ENCODE_REJECTED = 14;
    static final int EXPECTED_BEYOND_PICTURE = 10;
    /** Marker of a vector whose checks all passed, followed by its identifier ({@link VectorFile.Row#id()}). */
    static final String VERIFIED = "VETTORE-VERIFICATO ";
    /** Offset of the field inside the longer record, between different guard bytes. */
    static final int OFFSET = 8;

    private static Path vectors(String name) {
        Path module = Path.of(System.getProperty("user.dir")).toAbsolutePath();
        Path root = module.getParent();
        if (root == null) {
            throw new IllegalStateException("radice del repository non trovata da " + module);
        }
        return root.resolve(Path.of("analysis", "data-codec", "vettori", name));
    }

    @TestFactory
    @EnabledIfSystemProperty(named = RUN_PROPERTY, matches = ".*\\S.*", disabledReason = SKIP_REASON)
    Stream<DynamicTest> oracleGnuCobolVectors() throws IOException {
        List<VectorFile.Row> rows = VectorFile.read(vectors("oracle-gnucobol.tsv"));
        long decode = rows.stream().filter(r -> "decodifica".equals(r.get("operazione"))).count();
        long encode = rows.stream().filter(r -> "codifica".equals(r.get("operazione"))).count();
        long encodeOk = rows.stream().filter(r -> "codifica".equals(r.get("operazione")) && "ok".equals(r.get("stato"))).count();
        long rejected = rows.stream().filter(r -> "codifica".equals(r.get("operazione")) && "errore".equals(r.get("stato"))).count();
        assertEquals(EXPECTED_ROWS, rows.size(), "vettori nel file");
        assertEquals(EXPECTED_DECODE, decode, "vettori di decodifica");
        assertEquals(EXPECTED_ENCODE, encode, "vettori di codifica");
        assertEquals(EXPECTED_ENCODE_OK, encodeOk, "codifiche che riescono");
        assertEquals(EXPECTED_ENCODE_REJECTED, rejected, "codifiche rifiutate");
        return rows.stream().map(r -> dynamicTest(name(r), () -> {
            check(r);
            verified(r);
        }));
    }

    /**
     * Written on standard output only after every check of the vector has passed; surefire keeps it
     * in the report, inside the case, and {@code verify.sh} requires one per vector of the file, in
     * file order ({@code quality/RapportoSurefire.java}).
     */
    private static void verified(VectorFile.Row r) {
        System.out.println(VERIFIED + r.id());
    }

    @TestFactory
    @EnabledIfSystemProperty(named = RUN_PROPERTY, matches = ".*\\S.*", disabledReason = SKIP_REASON)
    Stream<DynamicTest> beyondPictureObservations() throws IOException {
        List<VectorFile.Row> rows = VectorFile.read(vectors("oracle-oltre-picture.tsv"));
        assertEquals(EXPECTED_BEYOND_PICTURE, rows.size(), "osservazioni oltre la PICTURE");
        Set<String> inMainFile = new HashSet<>();
        for (VectorFile.Row r : VectorFile.read(vectors("oracle-gnucobol.tsv"))) {
            if ("comp".equals(r.get("categoria")) && "decodifica".equals(r.get("operazione"))
                    && "oltre-picture".equals(r.get("stato"))) {
                inMainFile.add(r.get("variante") + "|" + Arrays.toString(VectorFile.hex(r.get("ingresso"))));
            }
        }
        return rows.stream().map(r -> dynamicTest(r.id() + " comp " + r.get("variante") + " " + r.get("ingresso"),
                () -> {
                    byte[] input = VectorFile.hex(r.get("ingresso"));
                    assertTrue(inMainFile.contains(r.get("variante") + "|" + Arrays.toString(input)),
                            "caso assente tra i vettori oltre-picture di oracle-gnucobol.tsv");
                    FieldPicture p = FieldPicture.of(FieldCategory.COMP, r.get("variante"));
                    for (DecodedField d : decodedTwice(p, input)) {
                        assertEquals(DecodeStatus.BEYOND_PICTURE, d.status(), "stato");
                        assertEquals(Optional.empty(), d.number(), "nessun valore oltre la PICTURE");
                        assertEquals(Optional.empty(), d.text(), "nessun testo");
                        assertArrayEquals(input, d.originalBytes(), "byte originali");
                        assertArrayEquals(input, GnuCobolFieldCodec.reencode(d), "ricodifica conservativa");
                    }
                    verified(r);
                }));
    }

    private static String name(VectorFile.Row r) {
        String in = r.get("ingresso");
        return r.id() + " " + r.get("categoria") + " " + r.get("variante") + " " + r.get("operazione") + " "
                + (in.length() > 40 ? in.substring(0, 40) + "..." : in);
    }

    static FieldCategory category(String label) {
        return switch (label) {
            case "alfanumerico" -> FieldCategory.ALPHANUMERIC;
            case "display-senza-segno" -> FieldCategory.DISPLAY_UNSIGNED;
            case "display-con-segno" -> FieldCategory.DISPLAY_SIGNED;
            case "comp-3" -> FieldCategory.COMP_3;
            case "comp" -> FieldCategory.COMP;
            default -> throw new IllegalArgumentException("categoria sconosciuta: " + label);
        };
    }

    private static DecodeStatus status(String label) {
        return switch (label) {
            case "valido" -> DecodeStatus.VALID;
            case "non-valido" -> DecodeStatus.INVALID;
            case "oltre-picture" -> DecodeStatus.BEYOND_PICTURE;
            default -> throw new IllegalArgumentException("stato di decodifica sconosciuto: " + label);
        };
    }

    /** Guard bytes before and after the field: plausible bytes of the same kind, different on the two sides. */
    private static byte[] guards(FieldCategory c) {
        return switch (c) {
            case ALPHANUMERIC -> new byte[] {0x5A, 0x59};
            case DISPLAY_UNSIGNED, DISPLAY_SIGNED -> new byte[] {0x37, 0x38};
            case COMP_3 -> new byte[] {0x1C, 0x2D};
            case COMP -> new byte[] {0x01, 0x02};
        };
    }

    /** The field alone at offset 0, and inside a longer record at offset {@value #OFFSET}. */
    private static List<DecodedField> decodedTwice(FieldPicture p, byte[] input) {
        byte[] g = guards(p.category());
        byte[] record = new byte[OFFSET + input.length + OFFSET];
        Arrays.fill(record, 0, OFFSET, g[0]);
        System.arraycopy(input, 0, record, OFFSET, input.length);
        Arrays.fill(record, OFFSET + input.length, record.length, g[1]);
        return List.of(GnuCobolFieldCodec.decode(p, input, 0), GnuCobolFieldCodec.decode(p, record, OFFSET));
    }

    private static void check(VectorFile.Row r) {
        FieldCategory c = category(r.get("categoria"));
        FieldPicture p = FieldPicture.of(c, r.get("variante"));
        boolean alpha = c == FieldCategory.ALPHANUMERIC;
        switch (r.get("operazione")) {
            case "decodifica" -> checkDecode(r, p, alpha);
            case "codifica" -> checkEncode(r, p, alpha);
            default -> fail("operazione sconosciuta: " + r.get("operazione"));
        }
    }

    private static void checkDecode(VectorFile.Row r, FieldPicture p, boolean alpha) {
        byte[] input = VectorFile.hex(r.get("ingresso"));
        DecodeStatus expected = status(r.get("stato"));
        String value = r.get("valore");
        for (DecodedField d : decodedTwice(p, input)) {
            assertEquals(expected, d.status(), "stato");
            assertArrayEquals(input, d.originalBytes(), "byte originali");
            assertArrayEquals(input, GnuCobolFieldCodec.reencode(d), "ricodifica conservativa");
            if ("-".equals(value)) {
                assertEquals(Optional.empty(), d.number(), "nessun valore");
                assertEquals(Optional.empty(), d.text(), "nessun testo");
                continue;
            }
            byte[] written;
            if (alpha) {
                String text = VectorFile.text(value);
                assertEquals(Optional.of(text), d.text(), "testo");
                assertEquals(Optional.empty(), d.number(), "nessun valore numerico");
                written = writeOrNull(() -> GnuCobolFieldCodec.encode(p, text));
            } else {
                BigDecimal number = VectorFile.number(value);
                // equals, not compareTo: a wrong scale with an equal value is an error.
                assertEquals(Optional.of(number), d.number(), "valore e scala");
                assertEquals(Optional.empty(), d.text(), "nessun testo");
                written = writeOrNull(() -> GnuCobolFieldCodec.encode(p, number));
            }
            String bytes = r.get("byte");
            if ("-".equals(bytes)) {
                assertEquals(null, written, "la codifica del valore doveva essere rifiutata");
            } else {
                assertArrayEquals(VectorFile.hex(bytes), written, "codifica del valore come valore nuovo");
            }
        }
    }

    private interface Write {
        byte[] run();
    }

    private static byte[] writeOrNull(Write w) {
        try {
            return w.run();
        } catch (FieldEncodingException e) {
            return null;
        }
    }

    private static void checkEncode(VectorFile.Row r, FieldPicture p, boolean alpha) {
        String in = r.get("ingresso");
        Write w = alpha ? () -> GnuCobolFieldCodec.encode(p, VectorFile.text(in))
                : () -> GnuCobolFieldCodec.encode(p, VectorFile.number(in));
        switch (r.get("stato")) {
            case "ok" -> assertArrayEquals(VectorFile.hex(r.get("byte")), w.run(), "byte della codifica");
            case "errore" -> {
                // the input itself must be readable: only the codec may reject it
                if (alpha) {
                    VectorFile.text(in);
                } else {
                    VectorFile.number(in);
                }
                assertThrows(FieldEncodingException.class, w::run, "valore non rappresentabile: atteso il rifiuto");
            }
            default -> fail("stato di codifica sconosciuto: " + r.get("stato"));
        }
    }
}
