package io.github.ltoscano.carddemo.loader;

import io.github.ltoscano.carddemo.domain.DecodeStatus;
import io.github.ltoscano.carddemo.domain.DecodedField;
import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.FieldEncodingException;
import io.github.ltoscano.carddemo.domain.GnuCobolFieldCodec;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
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
 * di testo di PostgreSQL non rappresenta. Nulla viene normalizzato. Un importo passa al database solo
 * con esattamente la scala della colonna.
 *
 * <p>Tabella non vuota: non cancella e non aggiorna mai. Se la tabella contiene esattamente i record
 * del file (stesse chiavi, ogni riga ricomposta in 300 byte uguale al record), termina con successo
 * senza scrivere ({@link EsitoCaricamento#giaCaricato()}); altrimenti si ferma con la prima differenza.
 *
 * <p>Tutto avviene in una sola transazione, che comincia bloccando la tabella ({@value #BLOCCO}):
 * controllo e caricamento sono serializzati, due caricatori non possono entrambi trovarla vuota.
 * I record si inseriscono uno alla volta nell'ordine del file.
 */
public final class CaricatoreConti {

    /** Colonne nell'ordine di {@link CampoConto} (il {@code FILLER} non ha colonna). */
    static final String INSERIMENTO = "insert into account (acct_id, acct_active_status, acct_curr_bal,"
            + " acct_credit_limit, acct_cash_credit_limit, acct_open_date, acct_expiraion_date, acct_reissue_date,"
            + " acct_curr_cyc_credit, acct_curr_cyc_debit, acct_addr_zip, acct_group_id)"
            + " values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    static final String CONTEGGIO = "select count(*) from account";

    /**
     * Blocco della tabella fino alla fine della transazione: EXCLUSIVE esclude un altro caricatore (e
     * ogni scrittura) ma lascia le letture.
     */
    static final String BLOCCO = "lock table account in exclusive mode";

    /** Lettura della tabella per il confronto con il file, nell'ordine di {@link CampoConto}. */
    static final String LETTURA = "select acct_id, acct_active_status, acct_curr_bal, acct_credit_limit,"
            + " acct_cash_credit_limit, acct_open_date, acct_expiraion_date, acct_reissue_date, acct_curr_cyc_credit,"
            + " acct_curr_cyc_debit, acct_addr_zip, acct_group_id from account order by acct_id";

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
     * @return i record del file (0 per un file vuoto) e se la tabella li conteneva gia'
     * @throws CaricamentoRifiutato se il file non e' conforme, o la tabella non e' vuota e non contiene
     *     esattamente i record del file (nessuna riga scritta)
     * @throws IOException se il file non si legge
     * @throws SQLException se il database non risponde come atteso (transazione annullata)
     */
    public static EsitoCaricamento carica(Path file, Connection connessione)
            throws CaricamentoRifiutato, IOException, SQLException {
        byte[] dati = Files.readAllBytes(file);
        int record = numeroDiRecord(dati, file);
        boolean autocommit = connessione.getAutoCommit();
        connessione.setAutoCommit(false);
        EsitoCaricamento esito;
        try {
            // Controllo della tabella e caricamento serializzati: un secondo caricatore attende qui la
            // fine della transazione del primo, poi trova la tabella piena e la confronta con il file.
            try (Statement blocco = connessione.createStatement()) {
                blocco.execute(BLOCCO);
            }
            long righe = righe(connessione);
            Map<BigDecimal, Posizione> chiavi = new HashMap<>();
            if (righe == 0) {
                try (PreparedStatement inserimento = connessione.prepareStatement(INSERIMENTO)) {
                    for (int r = 0; r < record; r++) {
                        lega(inserimento, decodifica(dati, r, chiavi));
                        inserisci(inserimento, r);
                    }
                }
                connessione.commit();
                esito = new EsitoCaricamento(record, false);
            } else {
                for (int r = 0; r < record; r++) {
                    decodifica(dati, r, chiavi);
                }
                confronta(connessione, dati, chiavi, righe);
                // Nessuna scrittura: la transazione si chiude senza conferma.
                connessione.rollback();
                esito = new EsitoCaricamento(record, true);
            }
        } catch (CaricamentoRifiutato | SQLException | RuntimeException e) {
            annulla(connessione, autocommit, e);
            throw e;
        }
        connessione.setAutoCommit(autocommit);
        return esito;
    }

    /**
     * Esito di un caricamento riuscito.
     *
     * @param record i record del file
     * @param giaCaricato vero se la tabella conteneva gia' esattamente quei record: nulla e' stato scritto
     */
    public record EsitoCaricamento(int record, boolean giaCaricato) {
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

    private static long righe(Connection connessione) throws SQLException {
        try (PreparedStatement conteggio = connessione.prepareStatement(CONTEGGIO);
                ResultSet rs = conteggio.executeQuery()) {
            if (!rs.next()) {
                throw new SQLException("conteggio delle righe di account senza risultato");
            }
            return rs.getLong(1);
        }
    }

    /**
     * Record del file (da 0) in cui compare una chiave. Un tipo proprio e non {@code Integer}: niente
     * conversioni implicite di numeri ({@code intValue()}), che l'ispezione del codice compilato vieta.
     */
    private record Posizione(int record) {
    }

    /** Valore di una colonna, con il campo da cui viene e il record (da 0). */
    private record Valore(CampoConto campo, int record, Object valore) {
    }

    /**
     * Decodifica e verifica il record r (da 0): i valori delle colonne nell'ordine di
     * {@link CampoConto}. La chiave si registra in {@code chiavi} (chiave → record da 0).
     */
    private static List<Valore> decodifica(byte[] dati, int r, Map<BigDecimal, Posizione> chiavi)
            throws CaricamentoRifiutato {
        int base = r * CampoConto.LUNGHEZZA_RECORD;
        List<Valore> valori = new ArrayList<>();
        for (CampoConto campo : CampoConto.values()) {
            DecodedField letto = GnuCobolFieldCodec.decode(campo.geometria(), dati, base + campo.offset());
            if (campo == CampoConto.FILLER) {
                verificaFiller(letto, r, campo);
                continue;
            }
            if (campo.categoria() == FieldCategory.ALPHANUMERIC) {
                valori.add(new Valore(campo, r, testo(letto, r, campo)));
            } else {
                BigDecimal valore = numero(letto, r, campo);
                if (campo == CampoConto.ACCT_ID) {
                    Posizione primo = chiavi.putIfAbsent(valore, new Posizione(r));
                    if (primo != null) {
                        throw new CaricamentoRifiutato(dove(r, campo) + ": chiave " + valore.toPlainString()
                                + " duplicata, gia' nel record " + (primo.record() + 1));
                    }
                }
                valori.add(new Valore(campo, r, valore));
            }
        }
        return valori;
    }

    /**
     * Parametri dell'inserimento. Un importo passa al database solo con esattamente la scala della
     * colonna (quella della {@code PICTURE}): PostgreSQL arrotonderebbe in silenzio i decimali in piu'.
     */
    private static void lega(PreparedStatement inserimento, List<Valore> valori)
            throws CaricamentoRifiutato, SQLException {
        int parametro = 0;
        for (Valore v : valori) {
            parametro++;
            if (v.valore() instanceof BigDecimal numero) {
                if (numero.scale() != v.campo().geometria().scale()) {
                    throw new CaricamentoRifiutato(dove(v.record(), v.campo()) + ": valore " + numero.toPlainString()
                            + " con scala " + numero.scale() + ", la colonna " + v.campo().colonna() + " ha scala "
                            + v.campo().geometria().scale());
                }
                inserimento.setBigDecimal(parametro, numero);
            } else {
                inserimento.setString(parametro, (String) v.valore());
            }
        }
    }

    /**
     * Tabella non vuota: deve contenere esattamente i record del file (stesse chiavi, e ogni riga
     * ricomposta in 300 byte con {@code encode} e il {@code FILLER} di spazi uguale al record del
     * file). Altrimenti si ferma con la prima differenza, in ordine di chiave.
     */
    private static void confronta(Connection connessione, byte[] dati, Map<BigDecimal, Posizione> chiavi, long righe)
            throws CaricamentoRifiutato, SQLException {
        String premessa = "la tabella account non e' vuota (" + righe + " righe) e non contiene esattamente i "
                + chiavi.size() + " record del file: il caricamento non cancella e non aggiorna; per ricaricare si"
                + " ricrea il database (docs/sviluppo.md). Prima differenza: ";
        Map<BigDecimal, Posizione> mancanti = new HashMap<>(chiavi);
        try (PreparedStatement lettura = connessione.prepareStatement(LETTURA); ResultSet rs = lettura.executeQuery()) {
            while (rs.next()) {
                BigDecimal chiave = rs.getBigDecimal(CampoConto.ACCT_ID.colonna());
                Posizione posizione = mancanti.remove(chiave);
                if (posizione == null) {
                    throw new CaricamentoRifiutato(premessa + "la tabella ha la chiave " + chiave.toPlainString()
                            + (chiavi.containsKey(chiave) ? " ripetuta" : ", che nel file non c'e'"));
                }
                int r = posizione.record();
                int base = r * CampoConto.LUNGHEZZA_RECORD;
                for (CampoConto campo : CampoConto.values()) {
                    if (campo == CampoConto.FILLER) {
                        continue;
                    }
                    byte[] nelFile = Arrays.copyOfRange(dati, base + campo.offset(), base + campo.offset() + campo.lunghezza());
                    Object nellaTabella = campo.categoria() == FieldCategory.ALPHANUMERIC ? rs.getString(campo.colonna())
                            : rs.getBigDecimal(campo.colonna());
                    String ricomposto = ricomponi(campo, nellaTabella, nelFile);
                    if (ricomposto != null) {
                        throw new CaricamentoRifiutato(premessa + "chiave " + chiave.toPlainString() + ", "
                                + dove(r, campo) + ": nella tabella " + ricomposto + ", nel file byte "
                                + ESADECIMALE.formatHex(nelFile));
                    }
                }
            }
        }
        if (!mancanti.isEmpty()) {
            int primo = Integer.MAX_VALUE;
            for (Posizione p : mancanti.values()) {
                primo = Math.min(primo, p.record());
            }
            throw new CaricamentoRifiutato(premessa + record(primo) + ": la chiave "
                    + CampoConto.ACCT_ID.campo() + " del file manca nella tabella");
        }
    }

    /** Null se il valore della tabella, ricodificato, da' i byte del file; altrimenti la sua descrizione. */
    private static String ricomponi(CampoConto campo, Object valore, byte[] nelFile) {
        if (valore == null) {
            return "NULL";
        }
        byte[] byteRicomposti;
        try {
            if (valore instanceof BigDecimal numero) {
                byteRicomposti = GnuCobolFieldCodec.encode(campo.geometria(), numero);
            } else {
                String testo = (String) valore;
                if (testo.length() != campo.lunghezza()) {
                    return "un testo di " + testo.length() + " caratteri, attesi " + campo.lunghezza();
                }
                byteRicomposti = GnuCobolFieldCodec.encode(campo.geometria(), testo);
            }
        } catch (FieldEncodingException e) {
            return "un valore non ricodificabile (" + e.getMessage() + ")";
        }
        if (Arrays.equals(byteRicomposti, nelFile)) {
            return null;
        }
        return (valore instanceof BigDecimal numero ? numero.toPlainString() : "'" + valore + "'") + " (byte "
                + ESADECIMALE.formatHex(byteRicomposti) + ")";
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
