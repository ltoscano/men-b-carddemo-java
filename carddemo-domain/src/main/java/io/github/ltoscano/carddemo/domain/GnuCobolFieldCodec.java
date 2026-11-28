package io.github.ltoscano.carddemo.domain;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.util.Arrays;

/**
 * Field codec of the {@code oracle-gnucobol} profile: the bytes as the oracle of this repository
 * (GnuCOBOL 3.2, {@code -std=ibm -fbinary-truncate -fsingle-quote -fsign=EBCDIC}) reads and
 * writes them. The rules are those of {@code docs/legacy-map/data-contract/codifica.md}, ported
 * from {@code analysis/data-codec/glue/codec.py}; three distinct operations:
 * <ul>
 *   <li>{@link #decode}: bytes to status and, only if valid, value; the original bytes are kept;</li>
 *   <li>{@link #reencode}: conservative re-encoding, the bytes read, unchanged (a negative zero
 *       stays negative);</li>
 *   <li>{@link #encode(FieldPicture, BigDecimal)} and {@link #encode(FieldPicture, String)}: a new
 *       value to the bytes the profile writes; a value that does not fit is rejected, never
 *       truncated or rounded.</li>
 * </ul>
 * Numbers are {@link BigDecimal} with the scale of the {@code PICTURE}, built from exact integers.
 */
public final class GnuCobolFieldCodec {

    private static final int BYTE_MASK = 0xFF;
    private static final int NIBBLE_MASK = 0x0F;
    private static final int ASCII_ZERO = 0x30;
    private static final int ASCII_NINE = 0x39;
    private static final int SPACE = 0x20;
    private static final int MAX_LATIN1 = 0xFF;
    private static final int DIGITS = 10;

    /**
     * Last byte of a signed {@code DISPLAY} field ({@code -fsign=EBCDIC}, {@code oracle/README.md}):
     * index d is digit d positive or zero ({@code { A ... I}), index 10 + d is digit d negative
     * ({@code } J ... R}).
     */
    private static final byte[] OVERPUNCH = {
        0x7B, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x7D, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52,
    };

    /** {@code COMP-3} sign codes: C positive, D negative, F positive (the only one if unsigned). */
    private static final int PACKED_POSITIVE = 0xC;
    private static final int PACKED_NEGATIVE = 0xD;
    private static final int PACKED_UNSIGNED = 0xF;

    private GnuCobolFieldCodec() {
    }

    /**
     * Decodes the field that starts at {@code offset} in {@code record}.
     *
     * @param picture the field geometry
     * @param record the whole record
     * @param offset position of the first byte of the field (from 0)
     * @return status, value (only if valid) and the original bytes
     * @throws IncompleteFieldException if the field does not lie entirely inside the record; this
     *     is checked before any conversion
     */
    public static DecodedField decode(FieldPicture picture, byte[] record, int offset) {
        if (picture == null) {
            throw new FieldEncodingException("PICTURE assente");
        }
        if (record == null) {
            throw new IncompleteFieldException("record assente per il campo " + picture);
        }
        if (offset < 0 || (long) offset + picture.length() > record.length) {
            throw new IncompleteFieldException("campo " + picture + " di " + picture.length() + " byte all'offset "
                    + offset + ": il record ne ha " + record.length);
        }
        byte[] bytes = Arrays.copyOfRange(record, offset, offset + picture.length());
        return switch (picture.category()) {
            case ALPHANUMERIC -> decodeAlphanumeric(bytes);
            case DISPLAY_UNSIGNED, DISPLAY_SIGNED -> decodeDisplay(picture, bytes);
            case COMP_3 -> decodePacked(picture, bytes);
            case COMP -> decodeBinary(picture, bytes);
        };
    }

    /**
     * Conservative re-encoding.
     *
     * @param field a decoded field
     * @return the bytes read, exactly as they were
     */
    public static byte[] reencode(DecodedField field) {
        return field.originalBytes();
    }

    /**
     * Encodes a new numeric value in the representation written by the profile.
     *
     * @param picture the geometry of a numeric field
     * @param value the value; any scale is accepted if the conversion to the scale of the
     *     {@code PICTURE} is exact
     * @return the bytes of the field
     * @throws FieldEncodingException if the value is missing, has fraction digits beyond the scale,
     *     is negative in an unsigned field, exceeds the {@code PICTURE}, or the field is alphanumeric
     */
    public static byte[] encode(FieldPicture picture, BigDecimal value) {
        if (picture == null) {
            throw new FieldEncodingException("PICTURE assente");
        }
        if (picture.category() == FieldCategory.ALPHANUMERIC) {
            throw new FieldEncodingException("valore numerico per il campo alfanumerico " + picture);
        }
        BigInteger unscaled = unscaled(picture, value);
        return switch (picture.category()) {
            case ALPHANUMERIC -> throw new FieldEncodingException("valore numerico per il campo alfanumerico " + picture);
            case DISPLAY_UNSIGNED, DISPLAY_SIGNED -> encodeDisplay(picture, unscaled);
            case COMP_3 -> encodePacked(picture, unscaled);
            case COMP -> encodeBinary(picture, unscaled);
        };
    }

    /**
     * Encodes a new text in an alphanumeric field: one byte per character (ISO-8859-1, identity on
     * the byte values), left-aligned, padded on the right with spaces (X'20').
     *
     * @param picture the geometry of an alphanumeric field
     * @param text the text
     * @return the bytes of the field
     * @throws FieldEncodingException if the text is missing, longer than the field, contains a
     *     character above U+00FF, or the field is numeric
     */
    public static byte[] encode(FieldPicture picture, String text) {
        if (picture == null) {
            throw new FieldEncodingException("PICTURE assente");
        }
        if (picture.category() != FieldCategory.ALPHANUMERIC) {
            throw new FieldEncodingException("testo per il campo numerico " + picture);
        }
        if (text == null) {
            throw new FieldEncodingException("testo assente per il campo " + picture);
        }
        if (text.length() > picture.length()) {
            throw new FieldEncodingException("testo di " + text.length() + " caratteri in un campo di "
                    + picture.length() + " byte");
        }
        byte[] out = new byte[picture.length()];
        Arrays.fill(out, (byte) SPACE);
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c > MAX_LATIN1) {
                throw new FieldEncodingException("carattere non rappresentabile in ISO-8859-1 alla posizione " + i
                        + " (codice " + (int) c + ")");
            }
            out[i] = (byte) c;
        }
        return out;
    }

    // --- alphanumeric ---------------------------------------------------------------------------

    private static DecodedField decodeAlphanumeric(byte[] bytes) {
        char[] chars = new char[bytes.length];
        for (int i = 0; i < bytes.length; i++) {
            chars[i] = (char) (bytes[i] & BYTE_MASK);
        }
        return DecodedField.validText(new String(chars), bytes);
    }

    // --- DISPLAY ----------------------------------------------------------------------------------

    private static int asciiDigit(int b) {
        return b >= ASCII_ZERO && b <= ASCII_NINE ? b - ASCII_ZERO : -1;
    }

    private static int overpunchIndex(int b) {
        for (int i = 0; i < OVERPUNCH.length; i++) {
            if (OVERPUNCH[i] == (byte) b) {
                return i;
            }
        }
        return -1;
    }

    private static DecodedField decodeDisplay(FieldPicture picture, byte[] bytes) {
        int body = picture.signed() ? bytes.length - 1 : bytes.length;
        BigInteger n = BigInteger.ZERO;
        for (int i = 0; i < body; i++) {
            int digit = asciiDigit(bytes[i] & BYTE_MASK);
            if (digit < 0) {
                return DecodedField.withoutValue(DecodeStatus.INVALID, bytes);
            }
            n = n.multiply(BigInteger.TEN).add(BigInteger.valueOf(digit));
        }
        boolean negative = false;
        if (picture.signed()) {
            int last = bytes[bytes.length - 1] & BYTE_MASK;
            int digit = asciiDigit(last);
            if (digit < 0) {
                int index = overpunchIndex(last);
                if (index < 0) {
                    return DecodedField.withoutValue(DecodeStatus.INVALID, bytes);
                }
                digit = index % DIGITS;
                negative = index >= DIGITS;
            }
            n = n.multiply(BigInteger.TEN).add(BigInteger.valueOf(digit));
        }
        return DecodedField.validNumber(new BigDecimal(negative ? n.negate() : n, picture.scale()), bytes);
    }

    private static byte[] encodeDisplay(FieldPicture picture, BigInteger unscaled) {
        byte[] out = new byte[picture.length()];
        Arrays.fill(out, (byte) ASCII_ZERO);
        String digits = unscaled.abs().toString();
        int start = out.length - digits.length();
        for (int i = 0; i < digits.length(); i++) {
            out[start + i] = (byte) digits.charAt(i);
        }
        if (picture.signed()) {
            int last = out.length - 1;
            int digit = out[last] - ASCII_ZERO;
            out[last] = OVERPUNCH[(unscaled.signum() < 0 ? DIGITS : 0) + digit];
        }
        return out;
    }

    // --- COMP-3 -----------------------------------------------------------------------------------

    private static int nibble(byte[] bytes, int index) {
        int b = bytes[index / 2] & BYTE_MASK;
        return index % 2 == 0 ? b >> 4 : b & NIBBLE_MASK;
    }

    private static DecodedField decodePacked(FieldPicture picture, byte[] bytes) {
        int digitNibbles = bytes.length * 2 - 1;
        // With an even number of digits the first nibble is padding: GnuCOBOL accepts 0-9 there
        // and ignores it in the value (cob_decimal_set_packed); A-F is not valid.
        int padding = digitNibbles - picture.digits();
        BigInteger n = BigInteger.ZERO;
        for (int i = 0; i < digitNibbles; i++) {
            int digit = nibble(bytes, i);
            if (digit >= DIGITS) {
                return DecodedField.withoutValue(DecodeStatus.INVALID, bytes);
            }
            if (i >= padding) {
                n = n.multiply(BigInteger.TEN).add(BigInteger.valueOf(digit));
            }
        }
        int sign = nibble(bytes, digitNibbles);
        boolean negative;
        if (sign == PACKED_UNSIGNED) {
            negative = false;
        } else if (picture.signed() && sign == PACKED_POSITIVE) {
            negative = false;
        } else if (picture.signed() && sign == PACKED_NEGATIVE) {
            negative = true;
        } else {
            return DecodedField.withoutValue(DecodeStatus.INVALID, bytes);
        }
        return DecodedField.validNumber(new BigDecimal(negative ? n.negate() : n, picture.scale()), bytes);
    }

    private static byte[] encodePacked(FieldPicture picture, BigInteger unscaled) {
        int[] nibbles = new int[picture.length() * 2];
        String digits = unscaled.abs().toString();
        int start = nibbles.length - 1 - digits.length();
        for (int i = 0; i < digits.length(); i++) {
            nibbles[start + i] = digits.charAt(i) - ASCII_ZERO;
        }
        int sign;
        if (!picture.signed()) {
            sign = PACKED_UNSIGNED;
        } else if (unscaled.signum() < 0) {
            sign = PACKED_NEGATIVE;
        } else {
            sign = PACKED_POSITIVE;
        }
        nibbles[nibbles.length - 1] = sign;
        byte[] out = new byte[picture.length()];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) ((nibbles[2 * i] << 4) | nibbles[2 * i + 1]);
        }
        return out;
    }

    // --- COMP -------------------------------------------------------------------------------------

    private static DecodedField decodeBinary(FieldPicture picture, byte[] bytes) {
        // Big-endian; two's complement if signed, plain unsigned integer otherwise.
        BigInteger n = picture.signed() ? new BigInteger(bytes) : new BigInteger(1, bytes);
        if (n.abs().compareTo(BigInteger.TEN.pow(picture.digits())) >= 0) {
            // Registro, voce 63: no value for a binary beyond its PICTURE.
            return DecodedField.withoutValue(DecodeStatus.BEYOND_PICTURE, bytes);
        }
        return DecodedField.validNumber(new BigDecimal(n, picture.scale()), bytes);
    }

    private static byte[] encodeBinary(FieldPicture picture, BigInteger unscaled) {
        // Minimal two's complement; inside the PICTURE (at most 18 digits) it always fits the
        // 2, 4 or 8 bytes of the field, and is extended on the left with the sign.
        byte[] minimal = unscaled.toByteArray();
        if (minimal.length > picture.length()) {
            throw new FieldEncodingException(unscaled + " non sta in " + picture.length() + " byte");
        }
        byte[] out = new byte[picture.length()];
        Arrays.fill(out, unscaled.signum() < 0 ? (byte) BYTE_MASK : 0);
        System.arraycopy(minimal, 0, out, out.length - minimal.length, minimal.length);
        return out;
    }

    // --- new numeric values -----------------------------------------------------------------------

    private static BigInteger unscaled(FieldPicture picture, BigDecimal value) {
        if (value == null) {
            throw new FieldEncodingException("valore assente per il campo " + picture);
        }
        BigDecimal scaled;
        try {
            scaled = value.setScale(picture.scale());
        } catch (ArithmeticException e) {
            throw new FieldEncodingException(value.toPlainString() + ": cifre decimali oltre la scala "
                    + picture.scale() + " di " + picture, e);
        }
        BigInteger n = scaled.unscaledValue();
        if (n.signum() < 0 && !picture.signed()) {
            throw new FieldEncodingException(value.toPlainString() + ": negativo nel campo senza segno " + picture);
        }
        if (n.abs().compareTo(BigInteger.TEN.pow(picture.digits())) >= 0) {
            throw new FieldEncodingException(value.toPlainString() + ": oltre la PICTURE " + picture);
        }
        return n;
    }
}
