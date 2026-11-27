package io.github.ltoscano.carddemo.domain;

/**
 * The five field categories of the CardDemo data contracts, as defined in
 * {@code docs/legacy-map/data-contract/codifica.md} (section "Censimento delle rappresentazioni").
 */
public enum FieldCategory {
    /** {@code PIC X(n)}, {@code DISPLAY}: one byte per character. */
    ALPHANUMERIC,
    /** {@code PIC 9(n)}, {@code DISPLAY}: one ASCII digit per byte, no sign. */
    DISPLAY_UNSIGNED,
    /** {@code PIC S9(i)V9(d)}, {@code DISPLAY}: sign embedded in the last digit (overpunch). */
    DISPLAY_SIGNED,
    /** {@code COMP-3} ({@code PACKED-DECIMAL}): two digits per byte, sign in the last half-byte. */
    COMP_3,
    /** {@code COMP} ({@code BINARY}): big-endian integer of 2, 4 or 8 bytes. */
    COMP
}
