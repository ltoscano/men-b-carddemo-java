package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/** Cases the vectors do not cover: incomplete fields, offsets, rejected values, scales, pictures. */
class GnuCobolFieldCodecTest {

    /** One field per category, with a valid content of its length. */
    private static final List<Object[]> FIELDS = List.of(
            new Object[] {FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(4)"), new byte[] {0x41, 0x42, 0x43, 0x44}},
            new Object[] {FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(3)"), new byte[] {0x31, 0x32, 0x33}},
            new Object[] {FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(4)V9(2)"), new byte[] {0x30, 0x30, 0x30, 0x31, 0x35, 0x7D}},
            new Object[] {FieldPicture.of(FieldCategory.COMP_3, "S9(9)V9(2)"), new byte[] {0, 0, 0, 0, 0, 0x1D}},
            new Object[] {FieldPicture.of(FieldCategory.COMP, "9(9)"), new byte[] {0, 0, 0, 0x7B}});

    @Test
    void campoIncompletoEOffsetFuoriDalRecordPerOgniCategoria() {
        for (Object[] f : FIELDS) {
            FieldPicture p = (FieldPicture) f[0];
            byte[] b = (byte[]) f[1];
            byte[] doubled = new byte[b.length * 2];
            System.arraycopy(b, 0, doubled, 0, b.length);
            System.arraycopy(b, 0, doubled, b.length, b.length);
            byte[] truncated = new byte[b.length - 1];
            System.arraycopy(b, 0, truncated, 0, truncated.length);
            assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(p, truncated, 0), p + " troncato");
            assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(p, new byte[0], 0), p + " record vuoto");
            assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(p, b, 1), p + " scavalca la fine");
            assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(p, b, b.length + 1), p + " oltre la fine");
            assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(p, doubled, -1), p + " offset negativo");
            assertThrows(IncompleteFieldException.class,
                    () -> GnuCobolFieldCodec.decode(p, doubled, Integer.MAX_VALUE), p + " offset enorme");
            assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(p, null, 0), p + " record assente");
            // the same field at the end of the record is complete
            assertEquals(DecodeStatus.VALID, GnuCobolFieldCodec.decode(p, doubled, b.length).status(), p + " in fondo");
        }
    }

    @Test
    void valoriNonRappresentabiliRifiutati() {
        FieldPicture x = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(3)");
        FieldPicture u = FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(3)");
        FieldPicture s = FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(4)V9(2)");
        FieldPicture pu = FieldPicture.of(FieldCategory.COMP_3, "9(3)");
        FieldPicture ps = FieldPicture.of(FieldCategory.COMP_3, "S9(10)V9(2)");
        FieldPicture bu = FieldPicture.of(FieldCategory.COMP, "9(4)");
        FieldPicture bs = FieldPicture.of(FieldCategory.COMP, "S9(10)V9(2)");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(x, "ABCD"), "testo troppo lungo");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(x, "A" + (char) 0x100), "oltre U+00FF");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(x, (String) null), "testo assente");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(x, BigDecimal.ONE), "numero in alfanumerico");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(u, "1"), "testo in numerico");
        for (FieldPicture p : List.of(u, s, pu, ps, bu, bs)) {
            assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(p, (BigDecimal) null), p + " assente");
            BigDecimal limit = BigDecimal.TEN.pow(p.integerDigits());
            assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(p, limit), p + " oltre la PICTURE");
            BigDecimal max = limit.subtract(BigDecimal.ONE.movePointLeft(p.scale()));
            assertEquals(Optional.of(max), GnuCobolFieldCodec.decode(p, GnuCobolFieldCodec.encode(p, max), 0).number(),
                    p + " estremo della PICTURE");
            if (p.signed()) {
                assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(p, limit.negate()), p + " sotto la PICTURE");
                assertEquals(Optional.of(max.negate()),
                        GnuCobolFieldCodec.decode(p, GnuCobolFieldCodec.encode(p, max.negate()), 0).number(), p + " estremo negativo");
            } else {
                assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(p, new BigDecimal("-1")),
                        p + " negativo senza segno");
            }
        }
    }

    @Test
    void scaleDiverseAccettateSeLaConversioneEEsatta() {
        FieldPicture p = FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(4)V9(2)");
        byte[] expected = {0x30, 0x30, 0x30, 0x31, 0x32, 0x7B};
        assertArrayEquals(new byte[] {0x30, 0x30, 0x30, 0x31, 0x30, 0x7B}, GnuCobolFieldCodec.encode(p, new BigDecimal("1")));
        for (String v : List.of("1.2", "1.20", "1.200", "0.12E+1")) {
            assertArrayEquals(expected, GnuCobolFieldCodec.encode(p, new BigDecimal(v)), v);
        }
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(p, new BigDecimal("1.234")), "1.234");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(p, new BigDecimal("1.201")), "1.201");
        FieldPicture b = FieldPicture.of(FieldCategory.COMP, "9(3)");
        assertArrayEquals(new byte[] {0, 0x64}, GnuCobolFieldCodec.encode(b, new BigDecimal("1E+2")), "1E+2");
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.encode(b, new BigDecimal("0.5")), "0.5 in 9(3)");
    }

    @Test
    void picturesNonValideOIncoerenti() {
        String[][] bad = {
            {"ALPHANUMERIC", "X(0)"}, {"ALPHANUMERIC", "9(3)"}, {"DISPLAY_UNSIGNED", "S9(3)"},
            {"DISPLAY_SIGNED", "9(3)"}, {"COMP", "9(19)"}, {"COMP", "S9(10)V9(9)"}, {"COMP_3", "9(03)"},
            {"COMP_3", "X(3)"}, {"DISPLAY_UNSIGNED", "9(3)V9(0)"}, {"DISPLAY_UNSIGNED", " 9(3)"},
            // forms the glue's regular expressions do not admit (_VAR_X, _VAR_9): P scaling, V without
            // a count, repeated 9s, signs other than a leading S, lowercase, blanks, usage clauses
            {"DISPLAY_UNSIGNED", "P9(4)"}, {"DISPLAY_UNSIGNED", "9(4)P"}, {"DISPLAY_UNSIGNED", "9(2)P(2)"},
            {"COMP_3", "SP9(4)"}, {"COMP", "9(4)PP"}, {"DISPLAY_SIGNED", "S9(4)V99"}, {"DISPLAY_SIGNED", "S9(4)V"},
            {"DISPLAY_SIGNED", "SV9(2)"}, {"DISPLAY_UNSIGNED", "9999"}, {"DISPLAY_UNSIGNED", "9(4)9"},
            {"DISPLAY_SIGNED", "+9(4)"}, {"DISPLAY_SIGNED", "9(4)-"}, {"DISPLAY_SIGNED", "S9(4)S"},
            {"DISPLAY_SIGNED", "s9(4)"}, {"ALPHANUMERIC", "x(4)"}, {"ALPHANUMERIC", "X(4) "}, {"ALPHANUMERIC", "A(4)"},
            {"ALPHANUMERIC", "X(-1)"}, {"COMP_3", "9(4) COMP-3"}, {"COMP_3", "S9(4)V9(2)V9(1)"}, {"COMP", "9(4).V9(2)"},
            {"COMP", ""}, {"ALPHANUMERIC", ""}, {"DISPLAY_UNSIGNED", "9()"},
            // counts that cannot be a Java length (the glue's grammar has no upper limit)
            {"ALPHANUMERIC", "X(2147483648)"}, {"DISPLAY_UNSIGNED", "9(99999999999)"},
            {"DISPLAY_SIGNED", "S9(2147483647)V9(1)"},
        };
        for (String[] b : bad) {
            assertThrows(FieldEncodingException.class, () -> FieldPicture.of(FieldCategory.valueOf(b[0]), b[1]), b[0] + " " + b[1]);
        }
        assertThrows(FieldEncodingException.class, () -> FieldPicture.of(null, "X(1)"));
        assertThrows(FieldEncodingException.class, () -> FieldPicture.of(FieldCategory.COMP, null));
        assertThrows(FieldEncodingException.class, () -> GnuCobolFieldCodec.decode(null, new byte[1], 0));
        FieldPicture p = FieldPicture.of(FieldCategory.COMP_3, "S9(10)V9(2)");
        assertEquals(List.of(7, 10, 2, 12, true), List.of(p.length(), p.integerDigits(), p.scale(), p.digits(), p.signed()));
        assertEquals("COMP_3 S9(10)V9(2)", p.toString());
        assertEquals("S9(10)V9(2)", p.picture());
        assertEquals(FieldCategory.COMP_3, p.category());
        assertEquals(List.of(2, 4, 8), List.of(FieldPicture.of(FieldCategory.COMP, "9(4)").length(),
                FieldPicture.of(FieldCategory.COMP, "9(5)").length(), FieldPicture.of(FieldCategory.COMP, "9(18)").length()));
    }

    /**
     * Counts accepted as by the glue (no upper limit in its grammar), at the boundaries of every
     * category. Every expected result below was obtained from analysis/data-codec/glue/codec.py
     * (command and output in PR #57), with values of at most 28 digits: beyond that the glue is not
     * exact (Python's default Decimal context rounds to 28 digits; integer conversions fail above
     * 4300 digits), while this codec stays exact. Geometry (length, scale) of large counts matches.
     */
    @Test
    void confiniDeiConteggiPerOgniCategoria() {
        FieldPicture x = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(10000)");
        byte[] a = new byte[10000];
        java.util.Arrays.fill(a, (byte) 0x41);
        DecodedField dx = GnuCobolFieldCodec.decode(x, a, 0);
        assertEquals(Optional.of("A".repeat(10000)), dx.text(), "X(10000)");
        assertArrayEquals(a, GnuCobolFieldCodec.reencode(dx));
        assertArrayEquals(a, GnuCobolFieldCodec.encode(x, "A".repeat(10000)));
        FieldPicture xmax = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(2147483647)");
        assertEquals(Integer.MAX_VALUE, xmax.length());
        assertThrows(IncompleteFieldException.class, () -> GnuCobolFieldCodec.decode(xmax, a, 0), "X(2147483647) su 10000 byte");

        // geometry of large counts, as geometria() of the glue: (10000, 0), (10000, 9999), (5001, 0)
        FieldPicture u = FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(10000)");
        FieldPicture s = FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(1)V9(9999)");
        FieldPicture p = FieldPicture.of(FieldCategory.COMP_3, "9(10000)");
        assertEquals(List.of(10000, 0, 10000, 9999, 5001, 0),
                List.of(u.length(), u.scale(), s.length(), s.scale(), p.length(), p.scale()));

        FieldPicture u28 = FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(28)");
        byte[] ones = ascii("1".repeat(28));
        BigDecimal allOnes = new BigDecimal("1".repeat(28));
        assertEquals(Optional.of(allOnes), GnuCobolFieldCodec.decode(u28, ones, 0).number(), "9(28)");
        assertArrayEquals(ones, GnuCobolFieldCodec.encode(u28, allOnes));
        FieldPicture u20 = FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(20)");
        assertArrayEquals(ascii("18446744073709551617"),
                GnuCobolFieldCodec.encode(u20, new BigDecimal("18446744073709551617")), "9(20) oltre 2^64: nessuna perdita");
        // counterexamples of the second validation: through longValue() of a subclass, or (int) after
        // longValueExact(), both became 000000000000000000001; the glue writes these bytes
        FieldPicture u21 = FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(21)");
        assertArrayEquals(ascii("018446744073709551617"),
                GnuCobolFieldCodec.encode(u21, new BigDecimal("18446744073709551617")), "9(21) 2^64 + 1");
        assertArrayEquals(ascii("000000000004294967297"),
                GnuCobolFieldCodec.encode(u21, new BigDecimal("4294967297")), "9(21) 2^32 + 1");

        FieldPicture s27 = FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(1)V9(27)");
        BigDecimal tiny = new BigDecimal("-1E-27");
        byte[] st = GnuCobolFieldCodec.encode(s27, tiny);
        assertArrayEquals(ascii("0".repeat(27) + "J"), st, "S9(1)V9(27) -1E-27");
        assertEquals(Optional.of(tiny), GnuCobolFieldCodec.decode(s27, st, 0).number());

        FieldPicture p28 = FieldPicture.of(FieldCategory.COMP_3, "9(28)");
        BigDecimal nines = new BigDecimal("9".repeat(28));
        byte[] pb = GnuCobolFieldCodec.encode(p28, nines);
        assertEquals("09999999999999999999999999999f", java.util.HexFormat.of().formatHex(pb), "COMP-3 9(28)");
        assertEquals(Optional.of(nines), GnuCobolFieldCodec.decode(p28, pb, 0).number());

        FieldPicture b = FieldPicture.of(FieldCategory.COMP, "S9(18)");
        BigDecimal max = new BigDecimal("999999999999999999");
        assertEquals("0de0b6b3a763ffff", java.util.HexFormat.of().formatHex(GnuCobolFieldCodec.encode(b, max)), "S9(18) massimo");
        byte[] min = GnuCobolFieldCodec.encode(b, max.negate());
        assertEquals("f21f494c589c0001", java.util.HexFormat.of().formatHex(min), "S9(18) minimo");
        assertEquals(Optional.of(max.negate()), GnuCobolFieldCodec.decode(b, min, 0).number());
    }

    private static byte[] ascii(String s) {
        return s.getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    }

    @Test
    void byteOriginaliCopiatiEConservati() {
        FieldPicture p = FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(4)V9(2)");
        byte[] record = {0x30, 0x30, 0x30, 0x30, 0x30, 0x7D};
        DecodedField d = GnuCobolFieldCodec.decode(p, record, 0);
        record[5] = 0x7B;
        byte[] out = d.originalBytes();
        out[0] = 0x39;
        assertArrayEquals(new byte[] {0x30, 0x30, 0x30, 0x30, 0x30, 0x7D}, GnuCobolFieldCodec.reencode(d), "zero negativo conservato");
        assertEquals(Optional.of(new BigDecimal("0.00")), d.number());
        assertArrayEquals(new byte[] {0x30, 0x30, 0x30, 0x30, 0x30, 0x7B}, GnuCobolFieldCodec.encode(p, d.number().orElseThrow()),
                "lo zero nuovo si scrive positivo");
        assertEquals("VALID 0.00 [48, 48, 48, 48, 48, 125]", d.toString());
    }
}
