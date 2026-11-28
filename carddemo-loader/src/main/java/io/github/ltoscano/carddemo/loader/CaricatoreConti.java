package io.github.ltoscano.carddemo.loader;

import io.github.ltoscano.carddemo.domain.DecodeStatus;
import io.github.ltoscano.carddemo.domain.DecodedField;
import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.GnuCobolFieldCodec;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;

/**
 * Caricamento del file dei conti nella tabella {@code account} (issue #60).
 *
 * <p>Ingresso: un file di record a lunghezza fissa di {@value CampoConto#LUNGHEZZA_RECORD} byte nel
 * profilo dell'oracle (i byte come li legge e scrive GnuCOBOL), senza terminatori. Ogni campo si
 * decodifica con {@link GnuCobolFieldCodec} secondo il tracciato {@link CampoConto}; nessuna regola
 * di codifica e' riscritta qui.
 *
 * <p>Il caricamento si ferma, senza lasciare righe (transazione annullata), con una diagnosi che
 * dice record, campo e byte, se: la dimensione non e' multipla di 300; un campo numerico non e'
 * valido; un campo numerico non e' in rappresentazione canonica (i suoi byte sono diversi da
 * {@code encode(decode(byte))}: zero con segno negativo, segno alternativo); il {@code FILLER} non e'
 * di 178 spazi; una chiave e' duplicata; un campo di testo contiene il byte nullo, che una colonna
 * di testo di PostgreSQL non rappresenta. Si ferma anche se la tabella non e' vuota: non cancella e
 * non aggiorna. Nulla viene normalizzato.
 *
 * <p>Tutto avviene in una sola transazione, un record alla volta nell'ordine del file.
 */
public final class CaricatoreConti {

    /** Colonne nell'ordine di {@link CampoConto} (il {@code FILLER} non ha colonna). */
    static final String INSERIMENTO = "insert into account (acct_id, acct_active_status, acct_curr_bal,"
            + " acct_credit_limit, acct_cash_credit_limit, acct_open_date, acct_expiraion_date, acct_reissue_date,"
            + " acct_curr_cyc_credit, acct_curr_cyc_debit, acct_addr_zip, acct_group_id)"
            + " values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    static final String CONTEGGIO = "select count(*) from account";

    private static final int SPAZIO = 0x20;
    private static final char NULLO = '\0';
    private static final HexFormat ESADECIMALE = HexFormat.of();

    private CaricatoreConti() {
    }

    /**
     * Carica il file nella tabella {@code account} attraverso la connessione, in una sola
     * transazione che conferma solo se tutto il file e' conforme e la tabella era vuota.
     *
     * @param file il file dei conti
     * @param connessione una connessione a un database con la tabella {@code account}; alla fine
     *     torna allo stato di autocommit che aveva
     * @return il numero di record caricati (0 per un file vuoto)
     * @throws CaricamentoRifiutato se il file non e' conforme o la tabella non e' vuota (nessuna riga
     *     scritta)
     * @throws IOException se il file non si legge
     * @throws SQLException se il database non risponde come atteso (transazione annullata)
     */
    public static int carica(Path file, Connection connessione) throws CaricamentoRifiutato, IOException, SQLException {
        byte[] dati = Files.readAllBytes(file);
        int record = numeroDiRecord(dati, file);
        boolean autocommit = connessione.getAutoCommit();
        connessione.setAutoCommit(false);
        try {
            verificaTabellaVuota(connessione);
            Map<BigDecimal, Integer> chiavi = new HashMap<>();
            try (PreparedStatement inserimento = connessione.prepareStatement(INSERIMENTO)) {
                for (int r = 0; r < record; r++) {
                    preparaRecord(dati, r, chiavi, inserimento);
                    inserisci(inserimento, r);
                }
            }
            connessione.commit();
        } catch (CaricamentoRifiutato | SQLException | RuntimeException e) {
            annulla(connessione, autocommit, e);
            throw e;
        }
        connessione.setAutoCommit(autocommit);
        return record;
    }

    private static int numeroDiRecord(byte[] dati, Path file) throws CaricamentoRifiutato {
        int resto = dati.length % CampoConto.LUNGHEZZA_RECORD;
        if (resto != 0) {
            int completi = dati.length / CampoConto.LUNGHEZZA_RECORD;
            throw new CaricamentoRifiutato("file " + file + ": " + dati.length + " byte, non multiplo di "
                    + CampoConto.LUNGHEZZA_RECORD + ": il record " + (completi + 1) + " e' incompleto, " + resto
                    + " byte dall'offset " + completi * CampoConto.LUNGHEZZA_RECORD + " del file");
        }
        return dati.length / CampoConto.LUNGHEZZA_RECORD;
    }

    private static void verificaTabellaVuota(Connection connessione) throws SQLException, CaricamentoRifiutato {
        try (PreparedStatement conteggio = connessione.prepareStatement(CONTEGGIO);
                ResultSet rs = conteggio.executeQuery()) {
            if (!rs.next()) {
                throw new SQLException("conteggio delle righe di account senza risultato");
            }
            long righe = rs.getLong(1);
            if (righe != 0) {
                throw new CaricamentoRifiutato("la tabella account non e' vuota (" + righe + " righe): il caricamento"
                        + " non cancella e non aggiorna; per ricaricare si ricrea il database (docs/sviluppo.md)");
            }
        }
    }

    /** Decodifica e verifica il record r (da 0) e ne imposta i parametri dell'inserimento. */
    private static void preparaRecord(byte[] dati, int r, Map<BigDecimal, Integer> chiavi,
            PreparedStatement inserimento) throws CaricamentoRifiutato, SQLException {
        int base = r * CampoConto.LUNGHEZZA_RECORD;
        int parametro = 0;
        for (CampoConto campo : CampoConto.values()) {
            DecodedField letto = GnuCobolFieldCodec.decode(campo.geometria(), dati, base + campo.offset());
            if (campo == CampoConto.FILLER) {
                verificaFiller(letto, r, campo);
                continue;
            }
            parametro++;
            if (campo.categoria() == FieldCategory.ALPHANUMERIC) {
                inserimento.setString(parametro, testo(letto, r, campo));
            } else {
                BigDecimal valore = numero(letto, r, campo);
                if (campo == CampoConto.ACCT_ID) {
                    Integer primo = chiavi.putIfAbsent(valore, r + 1);
                    if (primo != null) {
                        throw new CaricamentoRifiutato(dove(r, campo) + ": chiave " + valore.toPlainString()
                                + " duplicata, gia' nel record " + primo);
                    }
                }
                inserimento.setBigDecimal(parametro, valore);
            }
        }
    }

    private static BigDecimal numero(DecodedField letto, int r, CampoConto campo) throws CaricamentoRifiutato {
        byte[] byteLetti = letto.originalBytes();
        if (letto.status() != DecodeStatus.VALID || letto.number().isEmpty()) {
            throw new CaricamentoRifiutato(dove(r, campo) + ": campo numerico non valido (" + letto.status() + "), byte "
                    + ESADECIMALE.formatHex(byteLetti));
        }
        BigDecimal valore = letto.number().get();
        byte[] canonici = GnuCobolFieldCodec.encode(campo.geometria(), valore);
        if (!Arrays.equals(canonici, byteLetti)) {
            throw new CaricamentoRifiutato(dove(r, campo) + ": rappresentazione non canonica del valore "
                    + valore.toPlainString() + ": byte " + ESADECIMALE.formatHex(byteLetti) + ", canonici "
                    + ESADECIMALE.formatHex(canonici));
        }
        return valore;
    }

    private static String testo(DecodedField letto, int r, CampoConto campo) throws CaricamentoRifiutato {
        byte[] byteLetti = letto.originalBytes();
        if (letto.status() != DecodeStatus.VALID || letto.text().isEmpty()) {
            throw new CaricamentoRifiutato(dove(r, campo) + ": campo di testo non decodificato (" + letto.status() + ")");
        }
        String valore = letto.text().get();
        int nullo = valore.indexOf(NULLO);
        if (nullo >= 0) {
            throw new CaricamentoRifiutato(dove(r, campo) + ": byte nullo X'00' all'offset "
                    + (r * CampoConto.LUNGHEZZA_RECORD + campo.offset() + nullo)
                    + " del file, non rappresentabile in una colonna di testo; byte " + ESADECIMALE.formatHex(byteLetti));
        }
        byte[] canonici = GnuCobolFieldCodec.encode(campo.geometria(), valore);
        if (!Arrays.equals(canonici, byteLetti)) {
            throw new CaricamentoRifiutato(dove(r, campo) + ": testo non ricodificabile identico: byte "
                    + ESADECIMALE.formatHex(byteLetti) + ", ricodificati " + ESADECIMALE.formatHex(canonici));
        }
        return valore;
    }

    private static void verificaFiller(DecodedField letto, int r, CampoConto campo) throws CaricamentoRifiutato {
        byte[] byteLetti = letto.originalBytes();
        for (int i = 0; i < byteLetti.length; i++) {
            if (byteLetti[i] != SPAZIO) {
                throw new CaricamentoRifiutato(dove(r, campo) + ": il FILLER deve essere di " + byteLetti.length
                        + " spazi, all'offset " + (r * CampoConto.LUNGHEZZA_RECORD + campo.offset() + i)
                        + " del file c'e' il byte " + ESADECIMALE.toHexDigits(byteLetti[i]));
            }
        }
    }

    private static void inserisci(PreparedStatement inserimento, int r) throws CaricamentoRifiutato {
        int righe;
        try {
            righe = inserimento.executeUpdate();
        } catch (SQLException e) {
            throw new CaricamentoRifiutato(record(r) + ": inserimento rifiutato da PostgreSQL (SQLSTATE "
                    + e.getSQLState() + "): " + e.getMessage(), e);
        }
        if (righe != 1) {
            throw new CaricamentoRifiutato(record(r) + ": l'inserimento ha scritto " + righe + " righe, attesa 1");
        }
    }

    private static void annulla(Connection connessione, boolean autocommit, Exception errore) {
        try {
            connessione.rollback();
            connessione.setAutoCommit(autocommit);
        } catch (SQLException e) {
            errore.addSuppressed(e);
        }
    }

    private static String record(int r) {
        int base = r * CampoConto.LUNGHEZZA_RECORD;
        return "record " + (r + 1) + " (offset " + base + "-" + (base + CampoConto.LUNGHEZZA_RECORD - 1) + " del file)";
    }

    private static String dove(int r, CampoConto campo) {
        int inizio = r * CampoConto.LUNGHEZZA_RECORD + campo.offset();
        return record(r) + ", campo " + campo.campo() + " (offset " + inizio + "-" + (inizio + campo.lunghezza() - 1)
                + " del file, " + campo.offset() + "-" + (campo.offset() + campo.lunghezza() - 1) + " del record)";
    }
}
