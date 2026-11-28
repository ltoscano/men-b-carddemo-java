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
 *       a mano qui sotto (colonne, vincoli, valori predefiniti, indici, oggetti dello schema).</li>
 *   <li>Controllo 3: limiti delle colonne numeriche e comportamento delle colonne {@code CHAR(n)},
 *       sempre con inserimento parametrizzato e senza cast.</li>
 *   <li>Controllo 4: ordinamento numerico della chiave.</li>
 * </ul>
 *
 * <p>Ogni test lavora in una transazione propria che annulla alla fine: i test non si vedono.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AccountSchemaTest {

    /** Codici SQLSTATE di PostgreSQL usati nei rifiuti attesi. */
    static final String VALORE_FUORI_INTERVALLO = "22003";
    static final String TESTO_TROPPO_LUNGO = "22001";
    static final String VIOLAZIONE_CHECK = "23514";
    static final String CHIAVE_DUPLICATA = "23505";

    /**
     * Colonne attese, scritte a mano dalla specifica di #59: posizione | nome | tipo | lunghezza
     * massima | precisione | scala | annullabile | valore predefinito.
     */
    static final List<String> COLONNE_ATTESE = List.of(
            "1|acct_id|numeric|<null>|11|0|NO|<null>",
            "2|acct_active_status|character|1|<null>|<null>|NO|<null>",
            "3|acct_curr_bal|numeric|<null>|12|2|NO|<null>",
            "4|acct_credit_limit|numeric|<null>|12|2|NO|<null>",
            "5|acct_cash_credit_limit|numeric|<null>|12|2|NO|<null>",
            "6|acct_open_date|character|10|<null>|<null>|NO|<null>",
            "7|acct_expiraion_date|character|10|<null>|<null>|NO|<null>",
            "8|acct_reissue_date|character|10|<null>|<null>|NO|<null>",
            "9|acct_curr_cyc_credit|numeric|<null>|12|2|NO|<null>",
            "10|acct_curr_cyc_debit|numeric|<null>|12|2|NO|<null>",
            "11|acct_addr_zip|character|10|<null>|<null>|NO|<null>",
            "12|acct_group_id|character|10|<null>|<null>|NO|<null>");

    /**
     * Tutti i vincoli attesi (nome | tipo | definizione), in ordine di nome. Da PostgreSQL 18 i
     * {@code NOT NULL} sono vincoli del catalogo (tipo {@code n}), uno per colonna.
     */
    static final List<String> VINCOLI_ATTESI = List.of(
            "account_acct_active_status_not_null|n|NOT NULL acct_active_status",
            "account_acct_addr_zip_not_null|n|NOT NULL acct_addr_zip",
            "account_acct_cash_credit_limit_not_null|n|NOT NULL acct_cash_credit_limit",
            "account_acct_credit_limit_not_null|n|NOT NULL acct_credit_limit",
            "account_acct_curr_bal_not_null|n|NOT NULL acct_curr_bal",
            "account_acct_curr_cyc_credit_not_null|n|NOT NULL acct_curr_cyc_credit",
            "account_acct_curr_cyc_debit_not_null|n|NOT NULL acct_curr_cyc_debit",
            "account_acct_expiraion_date_not_null|n|NOT NULL acct_expiraion_date",
            "account_acct_group_id_not_null|n|NOT NULL acct_group_id",
            "account_acct_id_check|c|CHECK ((acct_id >= (0)::numeric))",
            "account_acct_id_not_null|n|NOT NULL acct_id",
            "account_acct_open_date_not_null|n|NOT NULL acct_open_date",
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

    /** Colonne di testo e loro lunghezza {@code n} di {@code CHAR(n)}. */
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
    void colonneNomiOrdineTipiPrecisioneScalaNotNullNessunPredefinito() throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            List<String> lette = PostgresDiProva.righe(c, "select ordinal_position, column_name, data_type,"
                    + " character_maximum_length, numeric_precision, numeric_scale, is_nullable, column_default"
                    + " from information_schema.columns where table_schema = 'public' and table_name = 'account'"
                    + " order by ordinal_position");
            assertEquals(COLONNE_ATTESE, lette, "colonne di account");
            // Valori predefiniti anche dal catalogo di PostgreSQL, non solo da information_schema.
            assertEquals(List.of("0"), PostgresDiProva.righe(c, "select count(*) from pg_attrdef"
                    + " where adrelid = 'public.account'::regclass"), "valori predefiniti di account");
        }
    }

    @Test
    void vincoliChiavePrimariaECheckSullaChiave() throws Exception {
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
     * Osservazione, non requisito della specifica: un importo con piu' di due decimali non e'
     * rifiutato, PostgreSQL lo arrotonda alla scala della colonna (meta' lontano da zero). Chi
     * scrive deve quindi portare il valore alla scala 2 prima (docs/contratti.md).
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

    // --- controllo 3: testo CHAR(n) -----------------------------------------------------------------

    @Test
    void testoPiuLungoConCaratteriEccedentiNonSpazioRifiutato() throws Exception {
        long chiave = 1;
        for (Map.Entry<String, Integer> t : TESTI.entrySet()) {
            for (String valore : List.of("A".repeat(t.getValue()) + "X", " ".repeat(t.getValue()) + "X",
                    "A".repeat(t.getValue()) + " X")) {
                Map<String, Object> riga = rigaValida(chiave++);
                riga.put(t.getKey(), valore);
                rifiutato(riga, TESTO_TROPPO_LUNGO, t.getKey() + " = '" + valore + "'");
            }
        }
    }

    /** Eccedenza di soli spazi: accettata e troncata alla lunghezza della colonna. */
    @Test
    void testoPiuLungoConEccedenzaDiSoliSpaziTroncato() throws Exception {
        long chiave = 1;
        for (Map.Entry<String, Integer> t : TESTI.entrySet()) {
            String pieno = "B".repeat(t.getValue());
            Letto l = scriviERileggi(chiave++, t.getKey(), pieno + "   ");
            assertEquals(pieno, l.jdbc(), t.getKey() + ": lettura JDBC");
            assertEquals(pieno, l.comeTesto(), t.getKey() + ": conversione a text");
            assertEquals(t.getValue(), l.ottetti(), t.getKey() + ": byte memorizzati");
        }
    }

    /** Stringa piu' corta: riempita di spazi; la lettura JDBC li restituisce, la conversione a text li toglie. */
    @Test
    void testoPiuCortoRiempitoDiSpazi() throws Exception {
        long chiave = 1;
        for (Map.Entry<String, Integer> t : TESTI.entrySet()) {
            if (t.getValue() < 2) {
                continue;
            }
            Letto l = scriviERileggi(chiave++, t.getKey(), "C");
            assertEquals("C" + " ".repeat(t.getValue() - 1), l.jdbc(), t.getKey() + ": lettura JDBC");
            assertEquals("C", l.comeTesto(), t.getKey() + ": conversione a text");
            assertEquals(t.getValue(), l.ottetti(), t.getKey() + ": byte memorizzati");
            // Spazi interni e iniziali restano; si tolgono solo quelli finali, e solo nella conversione.
            Letto interni = scriviERileggi(chiave++, t.getKey(), " D E");
            assertEquals(" D E" + " ".repeat(t.getValue() - 4), interni.jdbc(), t.getKey() + ": lettura JDBC");
            assertEquals(" D E", interni.comeTesto(), t.getKey() + ": conversione a text");
        }
    }

    /** Campo di soli spazi (e stringa vuota): memorizzati come n spazi, non come NULL. */
    @Test
    void campoDiSoliSpazi() throws Exception {
        long chiave = 1;
        for (Map.Entry<String, Integer> t : TESTI.entrySet()) {
            for (String valore : List.of(" ".repeat(t.getValue()), "")) {
                Letto l = scriviERileggi(chiave++, t.getKey(), valore);
                assertEquals(" ".repeat(t.getValue()), l.jdbc(), t.getKey() + " = '" + valore + "': lettura JDBC");
                assertEquals("", l.comeTesto(), t.getKey() + " = '" + valore + "': conversione a text");
                assertEquals(t.getValue(), l.ottetti(), t.getKey() + " = '" + valore + "': byte memorizzati");
            }
        }
    }

    /**
     * Confronti: con un parametro passato da {@code setString} (il driver lo invia come
     * {@code varchar}) PostgreSQL confronta come {@code CHAR}, senza tener conto degli spazi
     * finali, come il COBOL che allunga con spazi l'operando piu' corto. Con un parametro
     * convertito esplicitamente a {@code text} il confronto avviene tra testi, la colonna perde gli
     * spazi finali e il valore riempito non e' piu' uguale: e' la trappola da evitare.
     */
    @Test
    void confrontiConParametroVarcharOText() throws Exception {
        try (Connection c = transazione()) {
            Map<String, Object> riga = rigaValida(7);
            riga.put("acct_group_id", "G1");
            inserisci(c, riga);
            assertEquals(1, conta(c, "acct_group_id = ?", "G1"), "parametro corto");
            assertEquals(1, conta(c, "acct_group_id = ?", "G1        "), "parametro riempito a 10");
            assertEquals(1, conta(c, "acct_group_id = ?", "G1  "), "parametro riempito in parte");
            assertEquals(0, conta(c, "acct_group_id = ?", " G1"), "spazio iniziale");
            assertEquals(1, conta(c, "acct_group_id = ?::text", "G1"), "parametro text corto");
            assertEquals(0, conta(c, "acct_group_id = ?::text", "G1        "), "parametro text riempito");
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

    /** Connessione con una transazione aperta: il test la annulla alla fine. */
    private Connection transazione() throws SQLException {
        Connection c = PostgresDiProva.connessione(postgres);
        c.setAutoCommit(false);
        return c;
    }

    /** Riga con valori validi per ogni colonna, nell'ordine della tabella. */
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
        r.put("acct_addr_zip", "12345");
        r.put("acct_group_id", "A");
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
            System.out.println("[account] rifiutato " + descrizione + ": " + e.getSQLState() + " " + e.getMessage());
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

    /** Valore di una colonna di testo riletto in tre modi. */
    record Letto(String jdbc, String comeTesto, int ottetti) {
    }

    private Letto scriviERileggi(long chiave, String colonna, String valore) throws SQLException {
        try (Connection c = transazione()) {
            Map<String, Object> riga = rigaValida(chiave);
            riga.put(colonna, valore);
            inserisci(c, riga);
            Letto l;
            try (PreparedStatement ps = c.prepareStatement("select " + colonna + ", " + colonna + "::text, octet_length("
                    + colonna + ") from account where acct_id = ?")) {
                ps.setBigDecimal(1, BigDecimal.valueOf(chiave));
                try (ResultSet rs = ps.executeQuery()) {
                    assertTrue(rs.next(), "riga " + chiave + " assente");
                    l = new Letto(rs.getString(1), rs.getString(2), rs.getInt(3));
                }
            }
            System.out.println("[account] " + colonna + " scritto '" + valore + "': JDBC '" + l.jdbc() + "', text '"
                    + l.comeTesto() + "', " + l.ottetti() + " byte");
            c.rollback();
            return l;
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
