package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Tabella {@code account} (issue #59), controlli 1, 3 e 4 della specifica, contro PostgreSQL
 * reale (immagine di {@code compose.yaml}) dopo la migrazione applicata da Flyway a un database
 * vuoto.
 *
 * <ul>
 *   <li>Controllo 1: forma della tabella letta dal catalogo e confrontata con le attese scritte
 *       a mano qui sotto (colonne con collazione, vincoli, valori predefiniti, indici, oggetti dello
 *       schema).</li>
 *   <li>Controllo 3: limiti delle colonne numeriche e comportamento delle colonne di testo
 *       ({@code TEXT COLLATE "C"} con lunghezza esatta n), sempre con inserimento parametrizzato
 *       e senza cast.</li>
 *   <li>Controllo 4: ordinamento numerico della chiave.</li>
 * </ul>
 *
 * <p>Ogni test lavora in una transazione propria che annulla alla fine: i test non si vedono.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AccountSchemaTest {

    /** Codici SQLSTATE di PostgreSQL usati nei rifiuti attesi. */
    static final String VALORE_FUORI_INTERVALLO = "22003";
    static final String VIOLAZIONE_CHECK = "23514";
    static final String CHIAVE_DUPLICATA = "23505";

    /**
     * Colonne attese, scritte a mano dalla specifica di #59: posizione | nome | tipo | lunghezza
     * massima | precisione | scala | collazione | annullabile | valore predefinito. Le colonne di
     * testo sono {@code text} senza lunghezza nel tipo: la lunghezza sta nel vincolo.
     */
    static final List<String> COLONNE_ATTESE = List.of(
            "1|acct_id|numeric|<null>|11|0|<null>|NO|<null>",
            "2|acct_active_status|text|<null>|<null>|<null>|C|NO|<null>",
            "3|acct_curr_bal|numeric|<null>|12|2|<null>|NO|<null>",
            "4|acct_credit_limit|numeric|<null>|12|2|<null>|NO|<null>",
            "5|acct_cash_credit_limit|numeric|<null>|12|2|<null>|NO|<null>",
            "6|acct_open_date|text|<null>|<null>|<null>|C|NO|<null>",
            "7|acct_expiraion_date|text|<null>|<null>|<null>|C|NO|<null>",
            "8|acct_reissue_date|text|<null>|<null>|<null>|C|NO|<null>",
            "9|acct_curr_cyc_credit|numeric|<null>|12|2|<null>|NO|<null>",
            "10|acct_curr_cyc_debit|numeric|<null>|12|2|<null>|NO|<null>",
            "11|acct_addr_zip|text|<null>|<null>|<null>|C|NO|<null>",
            "12|acct_group_id|text|<null>|<null>|<null>|C|NO|<null>");

    /**
     * Tutti i vincoli attesi (nome | tipo | definizione), in ordine di nome. Da PostgreSQL 18 i
     * {@code NOT NULL} sono vincoli del catalogo (tipo {@code n}), uno per colonna.
     */
    static final List<String> VINCOLI_ATTESI = List.of(
            "account_acct_active_status_check|c|CHECK ((char_length(acct_active_status) = 1))",
            "account_acct_active_status_not_null|n|NOT NULL acct_active_status",
            "account_acct_addr_zip_check|c|CHECK ((char_length(acct_addr_zip) = 10))",
            "account_acct_addr_zip_not_null|n|NOT NULL acct_addr_zip",
            "account_acct_cash_credit_limit_not_null|n|NOT NULL acct_cash_credit_limit",
            "account_acct_credit_limit_not_null|n|NOT NULL acct_credit_limit",
            "account_acct_curr_bal_not_null|n|NOT NULL acct_curr_bal",
            "account_acct_curr_cyc_credit_not_null|n|NOT NULL acct_curr_cyc_credit",
            "account_acct_curr_cyc_debit_not_null|n|NOT NULL acct_curr_cyc_debit",
            "account_acct_expiraion_date_check|c|CHECK ((char_length(acct_expiraion_date) = 10))",
            "account_acct_expiraion_date_not_null|n|NOT NULL acct_expiraion_date",
            "account_acct_group_id_check|c|CHECK ((char_length(acct_group_id) = 10))",
            "account_acct_group_id_not_null|n|NOT NULL acct_group_id",
            "account_acct_id_check|c|CHECK ((acct_id >= (0)::numeric))",
            "account_acct_id_not_null|n|NOT NULL acct_id",
            "account_acct_open_date_check|c|CHECK ((char_length(acct_open_date) = 10))",
            "account_acct_open_date_not_null|n|NOT NULL acct_open_date",
            "account_acct_reissue_date_check|c|CHECK ((char_length(acct_reissue_date) = 10))",
            "account_acct_reissue_date_not_null|n|NOT NULL acct_reissue_date",
            "account_pkey|p|PRIMARY KEY (acct_id)");

    /** Unico indice atteso: quello implicito della chiave primaria. */
    static final List<String> INDICI_ATTESI = List.of(
            "account_pkey|CREATE UNIQUE INDEX account_pkey ON public.account USING btree (acct_id)");

    /**
     * Oggetti dello schema {@code public} dopo la migrazione (nome | tipo di relazione): la tabella,
     * il suo indice e lo storico di Flyway con i suoi due indici. Nient'altro (viste, sequenze,
     * tabelle, indici).
     */
    static final List<String> OGGETTI_ATTESI = List.of(
            "account|r",
            "account_pkey|i",
            "flyway_schema_history|r",
            "flyway_schema_history_pk|i",
            "flyway_schema_history_s_idx|i");

    /** Colonne numeriche: nome, massimo e minimo della PICTURE, primo valore con una cifra intera in piu'. */
    record Numerica(String colonna, BigDecimal massimo, BigDecimal minimo, BigDecimal oltre) {
    }

    static final List<Numerica> NUMERICHE = List.of(
            new Numerica("acct_id", new BigDecimal("99999999999"), new BigDecimal("0"), new BigDecimal("100000000000")),
            importo("acct_curr_bal"),
            importo("acct_credit_limit"),
            importo("acct_cash_credit_limit"),
            importo("acct_curr_cyc_credit"),
            importo("acct_curr_cyc_debit"));

    /** S9(10)V99: da -9999999999.99 a 9999999999.99. */
    static Numerica importo(String colonna) {
        return new Numerica(colonna, new BigDecimal("9999999999.99"), new BigDecimal("-9999999999.99"),
                new BigDecimal("10000000000.00"));
    }

    /** Colonne di testo e loro lunghezza n (PIC X(n)). */
    static final Map<String, Integer> TESTI = testi();

    static Map<String, Integer> testi() {
        Map<String, Integer> m = new LinkedHashMap<>();
        m.put("acct_active_status", 1);
        m.put("acct_open_date", 10);
        m.put("acct_expiraion_date", 10);
        m.put("acct_reissue_date", 10);
        m.put("acct_addr_zip", 10);
        m.put("acct_group_id", 10);
        return m;
    }

    private PostgreSQLContainer postgres;

    @BeforeAll
    void avviaEMigra() throws Exception {
        postgres = PostgresDiProva.avvia();
        PostgresDiProva.migraDaVuoto(postgres);
    }

    @AfterAll
    void ferma() {
        if (postgres != null) {
            postgres.close();
        }
    }

    // --- controllo 1: forma della tabella -------------------------------------------------------

    @Test
    void colonneNomiOrdineTipiPrecisioneScalaCollazioneNotNullNessunPredefinito() throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            List<String> lette = PostgresDiProva.righe(c, "select ordinal_position, column_name, data_type,"
                    + " character_maximum_length, numeric_precision, numeric_scale, collation_name, is_nullable,"
                    + " column_default from information_schema.columns"
                    + " where table_schema = 'public' and table_name = 'account' order by ordinal_position");
            assertEquals(COLONNE_ATTESE, lette, "colonne di account");
            // Valori predefiniti anche dal catalogo di PostgreSQL, non solo da information_schema.
            assertEquals(List.of("0"), PostgresDiProva.righe(c, "select count(*) from pg_attrdef"
                    + " where adrelid = 'public.account'::regclass"), "valori predefiniti di account");
        }
    }

    @Test
    void vincoliChiavePrimariaCheckSullaChiaveELunghezzaDeiTesti() throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            List<String> letti = PostgresDiProva.righe(c, "select conname, contype, pg_get_constraintdef(oid)"
                    + " from pg_constraint where conrelid = 'public.account'::regclass order by conname");
            assertEquals(VINCOLI_ATTESI, letti, "vincoli di account");
        }
    }

    @Test
    void soloLIndiceDellaChiavePrimaria() throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            List<String> letti = PostgresDiProva.righe(c, "select indexname, indexdef from pg_indexes"
                    + " where schemaname = 'public' and tablename = 'account' order by indexname");
            assertEquals(INDICI_ATTESI, letti, "indici di account");
        }
    }

    @Test
    void oggettiDelloSchemaETrigger() throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            assertEquals(OGGETTI_ATTESI, PostgresDiProva.righe(c, "select c.relname, c.relkind from pg_class c"
                    + " join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'"
                    + " order by c.relname"), "oggetti dello schema public");
            assertEquals(List.of("0"), PostgresDiProva.righe(c, "select count(*) from pg_trigger"
                    + " where tgrelid = 'public.account'::regclass"), "trigger su account");
        }
    }

    // --- controllo 3: limiti numerici --------------------------------------------------------------

    @Test
    void massimoEMinimoDellaPictureSiRileggonoIdentici() throws Exception {
        long chiave = 1;
        for (Numerica n : NUMERICHE) {
            for (BigDecimal valore : List.of(n.massimo(), n.minimo())) {
                try (Connection c = transazione()) {
                    Map<String, Object> riga = rigaValida(chiave++);
                    riga.put(n.colonna(), valore);
                    inserisci(c, riga);
                    BigDecimal letto = leggiNumero(c, n.colonna(), (BigDecimal) riga.get("acct_id"));
                    // equals, non compareTo: stesso valore e stessa scala.
                    assertEquals(valore, letto, n.colonna() + ": valore riletto");
                    assertEquals(valore.scale(), letto.scale(), n.colonna() + ": scala riletta");
                    System.out.println("[account] " + n.colonna() + " = " + valore + " riletto " + letto);
                    c.rollback();
                }
            }
        }
    }

    @Test
    void unaCifraInteraInPiuERifiutata() throws Exception {
        long chiave = 1;
        for (Numerica n : NUMERICHE) {
            List<BigDecimal> oltre = new ArrayList<>(List.of(n.oltre()));
            if (n.minimo().signum() < 0) {
                oltre.add(n.oltre().negate());
            }
            for (BigDecimal valore : oltre) {
                Map<String, Object> riga = rigaValida(chiave++);
                riga.put(n.colonna(), valore);
                rifiutato(riga, VALORE_FUORI_INTERVALLO, n.colonna() + " = " + valore);
            }
        }
    }

    @Test
    void chiaveNegativaRifiutata() throws Exception {
        Map<String, Object> riga = rigaValida(1);
        riga.put("acct_id", new BigDecimal("-1"));
        String messaggio = rifiutato(riga, VIOLAZIONE_CHECK, "acct_id = -1");
        assertTrue(messaggio.contains("account_acct_id_check"), "vincolo violato: " + messaggio);
    }

    @Test
    void chiaveDuplicataRifiutata() throws Exception {
        try (Connection c = transazione()) {
            inserisci(c, rigaValida(42));
            SQLException e = assertThrows(SQLException.class, () -> inserisci(c, rigaValida(42)),
                    "seconda riga con acct_id = 42");
            assertEquals(CHIAVE_DUPLICATA, e.getSQLState(), "SQLSTATE della chiave duplicata: " + e.getMessage());
            assertTrue(e.getMessage().contains("account_pkey"), "vincolo violato: " + e.getMessage());
            c.rollback();
        }
    }

    /**
     * Un importo con piu' di due decimali non e' rifiutato: PostgreSQL lo arrotonda alla scala
     * della colonna (meta' lontano da zero). Da qui la regola: gli importi si scrivono gia' alla
     * scala della colonna (docs/contratti.md).
     */
    @Test
    void decimaliInPiuArrotondatiDalDatabase() throws Exception {
        String[][] casi = {{"0.005", "0.01"}, {"-0.005", "-0.01"}, {"1.234", "1.23"}, {"9999999999.994", "9999999999.99"}};
        long chiave = 1;
        for (String[] caso : casi) {
            try (Connection c = transazione()) {
                Map<String, Object> riga = rigaValida(chiave++);
                riga.put("acct_curr_bal", new BigDecimal(caso[0]));
                inserisci(c, riga);
                BigDecimal letto = leggiNumero(c, "acct_curr_bal", (BigDecimal) riga.get("acct_id"));
                assertEquals(new BigDecimal(caso[1]), letto, "acct_curr_bal scritto " + caso[0]);
                System.out.println("[account] acct_curr_bal scritto " + caso[0] + " riletto " + letto);
                c.rollback();
            }
        }
    }

    // --- controllo 3: testo, esattamente n caratteri -----------------------------------------------

    /**
     * Un valore di lunghezza diversa da n e' rifiutato dal vincolo di lunghezza della colonna,
     * anche quando l'eccedenza e' di soli spazi (con {@code VARCHAR(n)} o {@code CHAR(n)} sarebbe
     * troncato senza errore) e anche quando il valore e' di soli spazi o vuoto.
     */
    @Test
    void testoPiuLungoOPiuCortoRifiutatoAncheConSoliSpazi() throws Exception {
        long chiave = 1;
        List<String> difformi = new ArrayList<>();
        for (Map.Entry<String, Integer> t : TESTI.entrySet()) {
            int n = t.getValue();
            List<String> valori = new ArrayList<>(List.of(
                    pieno("G", n) + "X", // eccedenza con un carattere non spazio
                    pieno("G", n) + " ", // eccedenza di un solo spazio
                    pieno("G", n) + " ".repeat(12), // eccedenza di soli spazi, lunga
                    " ".repeat(n + 1), // soli spazi, uno in piu'
                    "")); // vuoto
            if (n > 1) {
                valori.add("G"); // piu' corto, non riempito
                valori.add(" ".repeat(n - 1)); // soli spazi, uno in meno
            }
            for (String valore : valori) {
                Map<String, Object> riga = rigaValida(chiave++);
                riga.put(t.getKey(), valore);
                String esito = esitoInserimento(riga);
                String atteso = VIOLAZIONE_CHECK + " account_" + t.getKey() + "_check";
                System.out.println("[account] " + t.getKey() + " = '" + valore + "' (" + valore.length()
                        + " caratteri): " + esito);
                if (!esito.equals(atteso)) {
                    difformi.add(t.getKey() + " = '" + valore + "' (" + valore.length() + " caratteri): " + esito
                            + ", atteso " + atteso);
                }
            }
        }
        // Tutti i casi si provano prima di decidere: l'elenco dice quali valori sono passati o con quale errore.
        assertEquals(List.of(), difformi, "valori di lunghezza diversa da n non rifiutati dal vincolo di lunghezza");
    }

    /**
     * Esito di un inserimento in una transazione annullata: {@code ACCETTATO}, oppure SQLSTATE e
     * nome del vincolo violato (dal messaggio di PostgreSQL), oppure SQLSTATE e prima riga del messaggio.
     */
    private String esitoInserimento(Map<String, Object> riga) throws SQLException {
        try (Connection c = transazione()) {
            try {
                inserisci(c, riga);
                return "ACCETTATO";
            } catch (SQLException e) {
                Matcher m = Pattern.compile("violates check constraint \"([a-z_]+)\"")
                        .matcher(e.getMessage());
                return e.getSQLState() + " " + (m.find() ? m.group(1) : e.getMessage().split("\n")[0]);
            } finally {
                c.rollback();
            }
        }
    }

    /** Un valore di n caratteri si rilegge identico via JDBC, spazi finali compresi. */
    @Test
    void testoDiNCaratteriRilettoIdenticoSpaziCompresi() throws Exception {
        long chiave = 1;
        for (Map.Entry<String, Integer> t : TESTI.entrySet()) {
            int n = t.getValue();
            List<String> valori = new ArrayList<>(List.of(" ".repeat(n), "Z".repeat(n)));
            if (n > 1) {
                valori.add(pieno("G1", n)); // spazi finali
                valori.add(pieno(" D E", n)); // spazi iniziali, interni e finali
            }
            for (String valore : valori) {
                try (Connection c = transazione()) {
                    Map<String, Object> riga = rigaValida(chiave++);
                    riga.put(t.getKey(), valore);
                    inserisci(c, riga);
                    try (PreparedStatement ps = c.prepareStatement("select " + t.getKey() + ", char_length("
                            + t.getKey() + ") from account where acct_id = ?")) {
                        ps.setBigDecimal(1, (BigDecimal) riga.get("acct_id"));
                        try (ResultSet rs = ps.executeQuery()) {
                            assertTrue(rs.next(), "riga assente");
                            assertEquals(valore, rs.getString(1), t.getKey() + ": lettura JDBC");
                            assertEquals(n, rs.getInt(2), t.getKey() + ": char_length");
                            System.out.println("[account] " + t.getKey() + " scritto '" + valore + "' riletto '"
                                    + rs.getString(1) + "'");
                        }
                    }
                    c.rollback();
                }
            }
        }
    }

    /**
     * Confronti con un parametro di n caratteri: uguaglianza, {@code lower} su entrambi i lati
     * (come {@code FUNCTION LOWER-CASE} in {@code COACTUPC.cbl}) e conversione a {@code text}
     * trovano la riga; lo stesso parametro senza gli spazi finali non la trova.
     */
    @Test
    void confrontiConParametroDiNCaratteri() throws Exception {
        try (Connection c = transazione()) {
            Map<String, Object> riga = rigaValida(7);
            riga.put("acct_group_id", pieno("G1", 10));
            inserisci(c, riga);
            assertEquals(1, conta(c, "acct_group_id = ?", pieno("G1", 10)), "= con 10 caratteri");
            assertEquals(1, conta(c, "lower(acct_group_id) = lower(?)", pieno("g1", 10)), "lower con 10 caratteri");
            assertEquals(1, conta(c, "acct_group_id::text = ?", pieno("G1", 10)), "::text con 10 caratteri");
            assertEquals(0, conta(c, "acct_group_id = ?", "G1"), "= senza spazi finali");
            assertEquals(0, conta(c, "lower(acct_group_id) = lower(?)", "g1"), "lower senza spazi finali");
            assertEquals(0, conta(c, "acct_group_id::text = ?", "G1"), "::text senza spazi finali");
            c.rollback();
        }
    }

    /** Ordinamento delle colonne di testo per codice del carattere (collazione "C"). */
    @Test
    void ordinamentoDeiTestiPerCodiceDelCarattere() throws Exception {
        List<String> sparsi = List.of("g1", "B", " ", "a", "G1", "1", "b", "A", "a1", "A1");
        List<String> attesi = List.of(" ", "1", "A", "A1", "B", "G1", "a", "a1", "b", "g1");
        try (Connection c = transazione()) {
            long chiave = 1;
            for (String s : sparsi) {
                Map<String, Object> riga = rigaValida(chiave++);
                riga.put("acct_group_id", pieno(s, 10));
                inserisci(c, riga);
            }
            List<String> letti = new ArrayList<>();
            try (PreparedStatement ps = c.prepareStatement("select acct_group_id from account order by acct_group_id");
                    ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    letti.add(rs.getString(1));
                }
            }
            assertEquals(attesi.stream().map(s -> pieno(s, 10)).toList(), letti, "ORDER BY acct_group_id");
            // La collazione del database e' un'altra: l'ordine sopra viene dalla collazione della colonna.
            assertEquals(List.of("en_US.utf8|UTF8"), PostgresDiProva.righe(c, "select datcollate || '|' ||"
                    + " pg_encoding_to_char(encoding) from pg_database where datname = current_database()"),
                    "collazione e codifica del database");
            c.rollback();
        }
    }

    // --- controllo 4: ordinamento ---------------------------------------------------------------------

    @Test
    void ordinePerChiaveNumericoCrescente() throws Exception {
        try (Connection c = transazione()) {
            for (long chiave : new long[] {100, 99999999999L, 9, 10}) {
                inserisci(c, rigaValida(chiave));
            }
            List<BigDecimal> lette = new ArrayList<>();
            try (PreparedStatement ps = c.prepareStatement("select acct_id from account order by acct_id");
                    ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    lette.add(rs.getBigDecimal(1));
                }
            }
            assertEquals(List.of(new BigDecimal("9"), new BigDecimal("10"), new BigDecimal("100"),
                    new BigDecimal("99999999999")), lette, "acct_id in ORDER BY acct_id");
            c.rollback();
        }
    }

    // --- appoggio ------------------------------------------------------------------------------------

    /** Il testo allungato con spazi a n caratteri (come un campo PIC X(n) del COBOL). */
    static String pieno(String s, int n) {
        if (s.length() > n) {
            throw new IllegalArgumentException("'" + s + "' piu' lungo di " + n);
        }
        return s + " ".repeat(n - s.length());
    }

    /** Connessione con una transazione aperta: il test la annulla alla fine. */
    private Connection transazione() throws SQLException {
        Connection c = PostgresDiProva.connessione(postgres);
        c.setAutoCommit(false);
        return c;
    }

    /** Riga con valori validi per ogni colonna, nell'ordine della tabella; testi di n caratteri. */
    static Map<String, Object> rigaValida(long chiave) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("acct_id", BigDecimal.valueOf(chiave));
        r.put("acct_active_status", "Y");
        r.put("acct_curr_bal", new BigDecimal("0.00"));
        r.put("acct_credit_limit", new BigDecimal("0.00"));
        r.put("acct_cash_credit_limit", new BigDecimal("0.00"));
        r.put("acct_open_date", "2014-11-20");
        r.put("acct_expiraion_date", "2025-05-20");
        r.put("acct_reissue_date", "2025-05-20");
        r.put("acct_curr_cyc_credit", new BigDecimal("0.00"));
        r.put("acct_curr_cyc_debit", new BigDecimal("0.00"));
        r.put("acct_addr_zip", pieno("12345", 10));
        r.put("acct_group_id", pieno("A", 10));
        return r;
    }

    /** INSERT parametrizzato, senza cast: BigDecimal con setBigDecimal, testo con setString. */
    static void inserisci(Connection c, Map<String, Object> riga) throws SQLException {
        String colonne = String.join(", ", riga.keySet());
        String segnaposto = String.join(", ", riga.keySet().stream().map(k -> "?").toList());
        try (PreparedStatement ps = c.prepareStatement("insert into account (" + colonne + ") values (" + segnaposto + ")")) {
            int i = 1;
            for (Object v : riga.values()) {
                if (v instanceof BigDecimal d) {
                    ps.setBigDecimal(i++, d);
                } else {
                    ps.setString(i++, (String) v);
                }
            }
            assertEquals(1, ps.executeUpdate(), "righe inserite");
        }
    }

    /** L'inserimento deve fallire con il codice SQLSTATE atteso; restituisce il messaggio. */
    private String rifiutato(Map<String, Object> riga, String sqlState, String descrizione) throws SQLException {
        try (Connection c = transazione()) {
            SQLException e = assertThrows(SQLException.class, () -> inserisci(c, riga), descrizione + " accettato");
            assertEquals(sqlState, e.getSQLState(), descrizione + ": SQLSTATE (" + e.getMessage() + ")");
            System.out.println("[account] rifiutato " + descrizione + ": " + e.getSQLState() + " "
                    + e.getMessage().split("\n")[0]);
            c.rollback();
            return e.getMessage();
        }
    }

    private static BigDecimal leggiNumero(Connection c, String colonna, BigDecimal chiave) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement("select " + colonna + " from account where acct_id = ?")) {
            ps.setBigDecimal(1, chiave);
            try (ResultSet rs = ps.executeQuery()) {
                assertTrue(rs.next(), "riga " + chiave + " assente");
                return rs.getBigDecimal(1);
            }
        }
    }

    private static int conta(Connection c, String condizione, String parametro) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement("select count(*) from account where " + condizione)) {
            ps.setString(1, parametro);
            try (ResultSet rs = ps.executeQuery()) {
                assertTrue(rs.next());
                return rs.getInt(1);
            }
        }
    }
}
