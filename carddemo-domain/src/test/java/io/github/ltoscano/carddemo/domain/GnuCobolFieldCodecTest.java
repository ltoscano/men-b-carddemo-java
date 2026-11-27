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
