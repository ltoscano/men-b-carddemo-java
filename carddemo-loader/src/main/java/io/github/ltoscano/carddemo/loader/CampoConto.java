package io.github.ltoscano.carddemo.loader;

import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.FieldPicture;

/**
 * Tracciato del record {@code ACCOUNT-RECORD} (copybook {@code CVACT01Y}, 300 byte), riportato dal
 * contratto dati {@code docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv}: un
 * elemento per campo elementare, nell'ordine del contratto, con nome COBOL, posizione (offset da 0),
 * lunghezza in byte, categoria e {@code PICTURE} normalizzata per {@link FieldPicture#of}, e la
 * colonna della tabella {@code account} (nessuna per il {@code FILLER}).
 *
 * <p>Il contratto non si legge a run time (la cartella {@code docs/} non entra nel contesto di build
 * delle immagini): il test {@code TracciatoContoTest} di {@code carddemo-parity} confronta questa
 * tabella riga per riga con il file del contratto letto dal repository.
 */
public enum CampoConto {

    ACCT_ID("ACCT-ID", 0, 11, FieldCategory.DISPLAY_UNSIGNED, "9(11)", "acct_id"),
    ACCT_ACTIVE_STATUS("ACCT-ACTIVE-STATUS", 11, 1, FieldCategory.ALPHANUMERIC, "X(1)", "acct_active_status"),
    ACCT_CURR_BAL("ACCT-CURR-BAL", 12, 12, FieldCategory.DISPLAY_SIGNED, "S9(10)V9(2)", "acct_curr_bal"),
    ACCT_CREDIT_LIMIT("ACCT-CREDIT-LIMIT", 24, 12, FieldCategory.DISPLAY_SIGNED, "S9(10)V9(2)", "acct_credit_limit"),
    ACCT_CASH_CREDIT_LIMIT("ACCT-CASH-CREDIT-LIMIT", 36, 12, FieldCategory.DISPLAY_SIGNED, "S9(10)V9(2)",
            "acct_cash_credit_limit"),
    ACCT_OPEN_DATE("ACCT-OPEN-DATE", 48, 10, FieldCategory.ALPHANUMERIC, "X(10)", "acct_open_date"),
    ACCT_EXPIRAION_DATE("ACCT-EXPIRAION-DATE", 58, 10, FieldCategory.ALPHANUMERIC, "X(10)", "acct_expiraion_date"),
    ACCT_REISSUE_DATE("ACCT-REISSUE-DATE", 68, 10, FieldCategory.ALPHANUMERIC, "X(10)", "acct_reissue_date"),
    ACCT_CURR_CYC_CREDIT("ACCT-CURR-CYC-CREDIT", 78, 12, FieldCategory.DISPLAY_SIGNED, "S9(10)V9(2)",
            "acct_curr_cyc_credit"),
    ACCT_CURR_CYC_DEBIT("ACCT-CURR-CYC-DEBIT", 90, 12, FieldCategory.DISPLAY_SIGNED, "S9(10)V9(2)",
            "acct_curr_cyc_debit"),
    ACCT_ADDR_ZIP("ACCT-ADDR-ZIP", 102, 10, FieldCategory.ALPHANUMERIC, "X(10)", "acct_addr_zip"),
    ACCT_GROUP_ID("ACCT-GROUP-ID", 112, 10, FieldCategory.ALPHANUMERIC, "X(10)", "acct_group_id"),
    FILLER("FILLER", 122, 178, FieldCategory.ALPHANUMERIC, "X(178)", null);

    /** Lunghezza del record {@code ACCOUNT-RECORD} in byte (gruppo di livello 01 del contratto). */
    public static final int LUNGHEZZA_RECORD = 300;

    private final String campo;
    private final int offset;
    private final int lunghezza;
    private final FieldCategory categoria;
    private final String picture;
    private final String colonna;
    private final FieldPicture geometria;

    CampoConto(String campo, int offset, int lunghezza, FieldCategory categoria, String picture, String colonna) {
        this.campo = campo;
        this.offset = offset;
        this.lunghezza = lunghezza;
        this.categoria = categoria;
        this.picture = picture;
        this.colonna = colonna;
        this.geometria = FieldPicture.of(categoria, picture);
        if (geometria.length() != lunghezza) {
            throw new IllegalStateException("tracciato incoerente: " + campo + " ha lunghezza " + lunghezza
                    + " ma la PICTURE " + picture + " ne da' " + geometria.length());
        }
    }

    /** @return il nome del campo COBOL, come nel contratto */
    public String campo() {
        return campo;
    }

    /** @return la posizione del primo byte del campo nel record (da 0) */
    public int offset() {
        return offset;
    }

    /** @return la lunghezza del campo in byte */
    public int lunghezza() {
        return lunghezza;
    }

    /** @return la categoria del campo per il codec */
    public FieldCategory categoria() {
        return categoria;
    }

    /** @return la {@code PICTURE} normalizzata ({@code X(n)}, {@code 9(i)}, {@code S9(i)V9(d)}) */
    public String picture() {
        return picture;
    }

    /** @return la colonna della tabella {@code account}, o {@code null} per il {@code FILLER} */
    public String colonna() {
        return colonna;
    }

    /** @return la geometria del campo per il codec */
    public FieldPicture geometria() {
        return geometria;
    }
}
