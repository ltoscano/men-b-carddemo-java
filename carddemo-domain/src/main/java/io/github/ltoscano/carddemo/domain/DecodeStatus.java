package io.github.ltoscano.carddemo.domain;

/**
 * Outcome of decoding the bytes of a field ({@code codifica.md}, "Tre cose distinte per ogni campo").
 */
public enum DecodeStatus {
    /** The bytes are an admitted representation of the type: the field has a value. */
    VALID,
    /** The bytes fail the class test ({@code IS NUMERIC}): no value is assigned. */
    INVALID,
    /** A binary field holds an integer outside its {@code PICTURE}: no value is assigned. */
    BEYOND_PICTURE
}
