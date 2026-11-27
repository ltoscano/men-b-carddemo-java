package io.github.ltoscano.carddemo.domain;

/**
 * The field does not lie entirely inside the record (missing record, negative offset, offset past
 * the end, truncated field): nothing is converted, there is neither a status nor a value.
 */
public final class IncompleteFieldException extends FieldEncodingException {

    private static final long serialVersionUID = 1L;

    /**
     * @param message which field, which offset, how long the record is
     */
    public IncompleteFieldException(String message) {
        super(message);
    }
}
