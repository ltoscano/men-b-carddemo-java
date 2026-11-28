package io.github.ltoscano.carddemo.batch.readacct;

import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.FieldPicture;
import io.github.ltoscano.carddemo.domain.GnuCobolFieldCodec;
import java.util.Arrays;

/**
 * Tracciato di {@code ACCOUNT-RECORD} ({@code COPY CVACT01Y}, {@code CVACT01Y.cpy:4-17}, 300 byte) e
 * ricomposizione del record dai valori di una riga, con la codifica di #54 e i 178 spazi del
 * {@code FILLER}. Le posizioni sono contate da 0 dall'inizio del record.
 */
final class Cvact01y {

    /** Lunghezza di {@code ACCOUNT-RECORD} in byte. */
    static final int LUNGHEZZA = 300;

    /** {@code PIC 9(11)}: {@code ACCT-ID}. */
    static final FieldPicture CHIAVE = FieldPicture.of(FieldCategory.DISPLAY_UNSIGNED, "9(11)");
    /** {@code PIC X(01)}: {@code ACCT-ACTIVE-STATUS}. */
    static final FieldPicture X1 = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(1)");
    /** {@code PIC S9(10)V99} zonato: gli importi del record. */
    static final FieldPicture IMPORTO = FieldPicture.of(FieldCategory.DISPLAY_SIGNED, "S9(10)V9(2)");
    /** {@code PIC X(10)}: date, CAP, gruppo. */
    static final FieldPicture X10 = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(10)");
    /** {@code PIC X(178)}: {@code FILLER}. */
    static final FieldPicture FILLER = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(178)");

    static final int POS_ACCT_ID = 0;
    static final int POS_ACCT_ACTIVE_STATUS = 11;
    static final int POS_ACCT_CURR_BAL = 12;
    static final int POS_ACCT_CREDIT_LIMIT = 24;
    static final int POS_ACCT_CASH_CREDIT_LIMIT = 36;
    static final int POS_ACCT_OPEN_DATE = 48;
    static final int POS_ACCT_EXPIRAION_DATE = 58;
    static final int POS_ACCT_REISSUE_DATE = 68;
    static final int POS_ACCT_CURR_CYC_CREDIT = 78;
    static final int POS_ACCT_CURR_CYC_DEBIT = 90;
    static final int POS_ACCT_ADDR_ZIP = 102;
    static final int POS_ACCT_GROUP_ID = 112;
    static final int POS_FILLER = 122;

    private Cvact01y() {
    }

    /**
     * Ricompone i 300 byte di {@code ACCOUNT-RECORD}: ogni campo con {@code encode} della sua
     * {@code PICTURE}, il {@code FILLER} di spazi ({@code encode} di un testo vuoto).
     *
     * @throws io.github.ltoscano.carddemo.domain.FieldEncodingException se un valore non e' rappresentabile
     *     nella {@code PICTURE} del suo campo
     */
    static byte[] ricomponi(RecordConto c) {
        byte[] r = new byte[LUNGHEZZA];
        metti(r, POS_ACCT_ID, CHIAVE, GnuCobolFieldCodec.encode(CHIAVE, c.acctId()));
        metti(r, POS_ACCT_ACTIVE_STATUS, X1, GnuCobolFieldCodec.encode(X1, c.acctActiveStatus()));
        metti(r, POS_ACCT_CURR_BAL, IMPORTO, GnuCobolFieldCodec.encode(IMPORTO, c.acctCurrBal()));
        metti(r, POS_ACCT_CREDIT_LIMIT, IMPORTO, GnuCobolFieldCodec.encode(IMPORTO, c.acctCreditLimit()));
        metti(r, POS_ACCT_CASH_CREDIT_LIMIT, IMPORTO, GnuCobolFieldCodec.encode(IMPORTO, c.acctCashCreditLimit()));
        metti(r, POS_ACCT_OPEN_DATE, X10, GnuCobolFieldCodec.encode(X10, c.acctOpenDate()));
        metti(r, POS_ACCT_EXPIRAION_DATE, X10, GnuCobolFieldCodec.encode(X10, c.acctExpiraionDate()));
        metti(r, POS_ACCT_REISSUE_DATE, X10, GnuCobolFieldCodec.encode(X10, c.acctReissueDate()));
        metti(r, POS_ACCT_CURR_CYC_CREDIT, IMPORTO, GnuCobolFieldCodec.encode(IMPORTO, c.acctCurrCycCredit()));
        metti(r, POS_ACCT_CURR_CYC_DEBIT, IMPORTO, GnuCobolFieldCodec.encode(IMPORTO, c.acctCurrCycDebit()));
        metti(r, POS_ACCT_ADDR_ZIP, X10, GnuCobolFieldCodec.encode(X10, c.acctAddrZip()));
        metti(r, POS_ACCT_GROUP_ID, X10, GnuCobolFieldCodec.encode(X10, c.acctGroupId()));
        metti(r, POS_FILLER, FILLER, GnuCobolFieldCodec.encode(FILLER, ""));
        return r;
    }

    /** I byte del campo che comincia in {@code posizione} (da 0), lungo quanto la sua {@code PICTURE}. */
    static byte[] campo(byte[] record, int posizione, FieldPicture picture) {
        return Arrays.copyOfRange(record, posizione, posizione + picture.length());
    }

    private static void metti(byte[] record, int posizione, FieldPicture picture, byte[] campo) {
        if (campo.length != picture.length()) {
            throw new IllegalStateException("campo di " + campo.length + " byte per la PICTURE " + picture);
        }
        System.arraycopy(campo, 0, record, posizione, campo.length);
    }
}
