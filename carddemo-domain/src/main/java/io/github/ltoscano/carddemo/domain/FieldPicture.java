package io.github.ltoscano.carddemo.domain;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Geometry of a field: category and normalised {@code PICTURE} (the "variante" of
 * {@code codifica.md}: {@code X(n)}, {@code 9(i)}, {@code S9(i)V9(d)}), from which length in
 * bytes, scale and sign follow. Same rules as {@code geometria} in
 * {@code analysis/data-codec/glue/codec.py}.
 */
public final class FieldPicture {

    private static final Pattern ALPHANUMERIC = Pattern.compile("X\\(([1-9][0-9]{0,3})\\)");
    private static final Pattern NUMERIC =
            Pattern.compile("(S?)9\\(([1-9][0-9]{0,3})\\)(?:V9\\(([1-9][0-9]{0,3})\\))?");
    private static final int MAX_BINARY_DIGITS = 18;

    private final FieldCategory category;
    private final String picture;
    private final boolean signed;
    private final int integerDigits;
    private final int scale;
    private final int length;

    private FieldPicture(FieldCategory category, String picture, boolean signed, int integerDigits,
            int scale, int length) {
        this.category = category;
        this.picture = picture;
        this.signed = signed;
        this.integerDigits = integerDigits;
        this.scale = scale;
        this.length = length;
    }

    /**
     * Parses a normalised {@code PICTURE} for a category.
     *
     * @param category the field category
     * @param picture {@code X(n)} for alphanumeric fields, {@code [S]9(i)[V9(d)]} otherwise
     * @return the field geometry
     * @throws FieldEncodingException if the picture is malformed or inconsistent with the category
     */
    public static FieldPicture of(FieldCategory category, String picture) {
        if (category == null || picture == null) {
            throw new FieldEncodingException("categoria o PICTURE assente: " + category + " " + picture);
        }
        if (category == FieldCategory.ALPHANUMERIC) {
            Matcher m = ALPHANUMERIC.matcher(picture);
            if (!m.matches()) {
                throw new FieldEncodingException("PICTURE alfanumerica non valida: " + picture);
            }
            return new FieldPicture(category, picture, false, 0, 0, Integer.parseInt(m.group(1)));
        }
        Matcher m = NUMERIC.matcher(picture);
        if (!m.matches()) {
            throw new FieldEncodingException("PICTURE numerica non valida: " + picture);
        }
        boolean signed = "S".equals(m.group(1));
        int integerDigits = Integer.parseInt(m.group(2));
        int scale = m.group(3) == null ? 0 : Integer.parseInt(m.group(3));
        int digits = integerDigits + scale;
        int length;
        switch (category) {
            case DISPLAY_UNSIGNED, DISPLAY_SIGNED -> {
                if (signed != (category == FieldCategory.DISPLAY_SIGNED)) {
                    throw new FieldEncodingException("PICTURE " + picture + " incoerente con la categoria " + category);
                }
                length = digits;
            }
            case COMP_3 -> length = digits / 2 + 1;
            case COMP -> length = binaryLength(digits, picture);
            default -> throw new FieldEncodingException("categoria senza regola: " + category);
        }
        return new FieldPicture(category, picture, signed, integerDigits, scale, length);
    }

    private static int binaryLength(int digits, String picture) {
        if (digits <= 4) {
            return 2;
        }
        if (digits <= 9) {
            return 4;
        }
        if (digits <= MAX_BINARY_DIGITS) {
            return 8;
        }
        throw new FieldEncodingException("binario con " + digits + " cifre: nessuna regola (" + picture + ")");
    }

    /** @return the field category */
    public FieldCategory category() {
        return category;
    }

    /** @return the normalised {@code PICTURE} as given */
    public String picture() {
        return picture;
    }

    /** @return whether the {@code PICTURE} has a sign ({@code S}) */
    public boolean signed() {
        return signed;
    }

    /** @return digits before the implied decimal point (0 for alphanumeric fields) */
    public int integerDigits() {
        return integerDigits;
    }

    /** @return digits after the implied decimal point: the scale of decoded values */
    public int scale() {
        return scale;
    }

    /** @return all digits of the {@code PICTURE} (0 for alphanumeric fields) */
    public int digits() {
        return integerDigits + scale;
    }

    /** @return length of the field in bytes */
    public int length() {
        return length;
    }

    @Override
    public String toString() {
        return category + " " + picture;
    }
}
