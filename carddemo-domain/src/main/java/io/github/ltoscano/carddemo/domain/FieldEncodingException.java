package io.github.ltoscano.carddemo.domain;

/**
 * A value that cannot be represented in a field, or a {@code PICTURE} without a rule: the codec
 * rejects it explicitly instead of truncating or rounding.
 */
public class FieldEncodingException extends IllegalArgumentException {

    private static final long serialVersionUID = 1L;

    /**
     * @param message what was rejected and why
     */
    public FieldEncodingException(String message) {
        super(message);
    }

    /**
     * @param message what was rejected and why
     * @param cause the underlying failure
     */
    public FieldEncodingException(String message, Throwable cause) {
        super(message, cause);
    }
}
