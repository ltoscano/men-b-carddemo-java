package io.github.ltoscano.carddemo.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * Exhaustive cases of the reference check ({@code analysis/data-codec/glue/verifica.py}, lines
 * 20-22 and 336-356; cases built as {@code comune.casi_esaustivi}): for every {@code DISPLAY}
 * variant of the census, all 256 values of the last byte (signed fields) and of the first byte of
 * the body, against a rule written here independently of the codec. Vectors alone are not enough:
 * a parser that accepts {@code +123} in a {@code 9(4)} passes them all.
 */
class DisplayExhaustiveTest {

    /** Sign table written a second time, as text: positive 0-9, then negative 0-9. */
    private static final String SIGN_TABLE = "{ABCDEFGHI}JKLMNOPQR";
    private static final int[] UNSIGNED = {1, 3, 4, 7, 9, 11, 16};
    private static final String[] SIGNED = {"S9(4)V9(2)", "S9(9)V9(2)", "S9(10)V9(2)"};
    private static final byte ONE = '1';
    private static final byte POSITIVE_ZERO = '{';
    private static final int EXPECTED_CASES = 3 * 256 + (UNSIGNED.length + SIGNED.length) * 256;

    private record Expected(DecodeStatus status, Optional<BigDecimal> value) {
    }

    private static boolean isDigit(int b) {
        return b >= '0' && b <= '9';
    }

    /** The rule: body of plain ASCII digits; last byte of a signed field in the table or a plain digit. */
    private static Expected rule(boolean signed, int scale, byte[] input) {
        int body = signed ? input.length - 1 : input.length;
        StringBuilder digits = new StringBuilder();
        for (int i = 0; i < body; i++) {
            int b = input[i] & 0xFF;
            if (!isDigit(b)) {
                return new Expected(DecodeStatus.INVALID, Optional.empty());
            }
            digits.append((char) b);
        }
        boolean negative = false;
        if (signed) {
            int last = input[input.length - 1] & 0xFF;
            int index = SIGN_TABLE.indexOf((char) last);
            if (index >= 0) {
                digits.append((char) ('0' + index % 10));
                negative = index >= 10;
            } else if (isDigit(last)) {
                digits.append((char) last);
            } else {
                return new Expected(DecodeStatus.INVALID, Optional.empty());
            }
        }
        BigInteger n = new BigInteger(digits.toString());
        return new Expected(DecodeStatus.VALID, Optional.of(new BigDecimal(negative ? n.negate() : n, scale)));
    }

    @Test
    void ogniValoreDellUltimoEDelPrimoByteDeiDisplay() {
        List<String> errors = new ArrayList<>();
        int cases = 0;
        List<FieldPicture> pictures = new ArrayList<>();
        for (int n : UNSIGNED) {
            pictures.add(FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(" + n + ")"));
        }
        for (String s : SIGNED) {
            pictures.add(FieldPicture.of(FieldCategory.DISPLAY_SIGNED, s));
        }
        for (FieldPicture p : pictures) {
            int n = p.length();
            for (int b = 0; b < 256; b++) {
                List<byte[]> inputs = new ArrayList<>();
                if (p.signed()) {
                    byte[] last = new byte[n];
                    Arrays.fill(last, ONE);
                    last[n - 1] = (byte) b;
                    inputs.add(last);
                    byte[] first = new byte[n];
                    Arrays.fill(first, ONE);
                    first[0] = (byte) b;
                    first[n - 1] = POSITIVE_ZERO;
                    inputs.add(first);
                } else {
                    byte[] first = new byte[n];
                    Arrays.fill(first, ONE);
                    first[0] = (byte) b;
                    inputs.add(first);
                }
                for (byte[] input : inputs) {
                    cases++;
                    Expected e = rule(p.signed(), p.scale(), input);
                    DecodedField d = GnuCobolFieldCodec.decode(p, input, 0);
                    if (d.status() != e.status() || !d.number().equals(e.value())) {
                        errors.add(p + " byte " + Arrays.toString(input) + ": atteso " + e + ", ottenuto " + d);
                    }
                }
            }
        }
        assertEquals(EXPECTED_CASES, cases, "casi esaustivi");
        assertTrue(errors.isEmpty(), errors.size() + " casi esaustivi diversi dalla regola, i primi: "
                + errors.subList(0, Math.min(10, errors.size())));
    }
}
