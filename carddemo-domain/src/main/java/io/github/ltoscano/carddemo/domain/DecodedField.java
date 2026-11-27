package io.github.ltoscano.carddemo.domain;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Optional;

/**
 * Result of decoding a field: the status, the value only when the status is
 * {@link DecodeStatus#VALID}, and always the original bytes, unchanged.
 */
public final class DecodedField {

    private final DecodeStatus status;
    private final BigDecimal number;
    private final String text;
    private final byte[] originalBytes;

    private DecodedField(DecodeStatus status, BigDecimal number, String text, byte[] originalBytes) {
        this.status = status;
        this.number = number;
        this.text = text;
        this.originalBytes = originalBytes.clone();
    }

    static DecodedField validNumber(BigDecimal number, byte[] originalBytes) {
        return new DecodedField(DecodeStatus.VALID, number, null, originalBytes);
    }

    static DecodedField validText(String text, byte[] originalBytes) {
        return new DecodedField(DecodeStatus.VALID, null, text, originalBytes);
    }

    static DecodedField withoutValue(DecodeStatus status, byte[] originalBytes) {
        return new DecodedField(status, null, null, originalBytes);
    }

    /** @return valid, invalid or beyond the {@code PICTURE} */
    public DecodeStatus status() {
        return status;
    }

    /**
     * @return the numeric value, with the scale of the {@code PICTURE}; empty for alphanumeric
     *     fields and for fields that are not valid
     */
    public Optional<BigDecimal> number() {
        return Optional.ofNullable(number);
    }

    /**
     * @return the text of an alphanumeric field (one character per byte); empty for numeric fields
     */
    public Optional<String> text() {
        return Optional.ofNullable(text);
    }

    /** @return a copy of the bytes read, exactly as they were in the record */
    public byte[] originalBytes() {
        return originalBytes.clone();
    }

    @Override
    public String toString() {
        return status + " " + (number != null ? number.toPlainString() : text) + " " + Arrays.toString(originalBytes);
    }
}
