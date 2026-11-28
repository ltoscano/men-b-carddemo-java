package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import io.github.ltoscano.carddemo.loader.CaricamentoRifiutato;
import io.github.ltoscano.carddemo.loader.CaricatoreConti;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Issue #60, controllo 5: casi costruiti nel test (file temporanei) caricati con
 * {@link CaricatoreConti} in PostgreSQL reale.
 *
 * <p>Rifiutati, ciascuno con la sua diagnosi (record, campo, byte) e zero righe scritte: il record
 * difettoso e' il terzo di quattro, quindi un caricamento che confermasse prima dell'errore
 * lascerebbe due righe. Accettati: massimo e minimo della {@code PICTURE}, file vuoto, record
 * distinguibili campo per campo, caratteri oltre ASCII; a ognuno si applicano i controlli 1-4.
 */
class CaricamentoContiCasiTest {

    static PostgreSQLContainer postgres;
    static List<ContiDiProva.Campo> tracciato;

    @TempDir
    Path cartella;

    @BeforeAll
    static void avvia() throws Exception {
        tracciato = ContiDiProva.tracciato();
        postgres = PostgresDiProva.avvia();
        PostgresDiProva.migraDaVuoto(postgres);
    }

    @AfterAll
    static void ferma() {
        if (postgres != null) {
            postgres.close();
        }
    }

    @BeforeEach
    void tabellaVuota() throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres); Statement st = c.createStatement()) {
            st.execute("truncate account");
            assertEquals(0, ContiDiProva.righe(c), "tabella non vuota prima del caso");
        }
    }

    // --- rifiutati ------------------------------------------------------------------------------

    @Test
    void zeroNegativoRifiutato() throws Exception {
        rifiutato("zero-negativo", alterato("acct_curr_bal", "00000000000}"),
                "record 3 (offset 600-899 del file), campo ACCT-CURR-BAL (offset 612-623 del file, 12-23 del record)",
                "rappresentazione non canonica del valore 0.00: byte 30303030303030303030307d, canonici 30303030303030303030307b");
    }

    @Test
    void segnoAlternativoRifiutato() throws Exception {
        // Ultimo byte cifra ASCII (positivo per la decodifica) invece della sovrapposizione '{'.
        rifiutato("segno-alternativo", alterato("acct_credit_limit", "000000500000"),
                "campo ACCT-CREDIT-LIMIT (offset 624-635 del file, 24-35 del record)",
                "rappresentazione non canonica del valore 5000.00: byte 303030303030353030303030, canonici 30303030303035303030307b");
    }

    @Test
    void fillerNonVuotoRifiutato() throws Exception {
        byte[][] r = quattro();
        r[2][299] = 'X';
        rifiutato("filler", r, "record 3 (offset 600-899 del file), campo FILLER (offset 722-899 del file, 122-299 del record)",
                "il FILLER deve essere di 178 spazi, all'offset 899 del file c'e' il byte 58");
    }

    @Test
    void campoNumericoConSpaziRifiutato() throws Exception {
        rifiutato("numerico-spazi", alterato("acct_cash_credit_limit", " ".repeat(12)),
                "campo ACCT-CASH-CREDIT-LIMIT (offset 636-647 del file, 36-47 del record)",
                "campo numerico non valido (INVALID), byte 202020202020202020202020");
    }

    @Test
    void chiaveDuplicataRifiutata() throws Exception {
        byte[][] r = quattro();
        r[2] = ContiDiProva.record(tracciato, ordinario(1));
        rifiutato("chiave-duplicata", r, "record 3 (offset 600-899 del file), campo ACCT-ID (offset 600-610 del file, 0-10 del record)",
                "chiave 1 duplicata, gia' nel record 1");
    }

    @Test
    void fileTroncatoRifiutato() throws Exception {
        byte[] intero = ContiDiProva.unisci(quattro());
        byte[] troncato = Arrays.copyOf(intero, intero.length - 1);
        rifiutatoFile("troncato", troncato, "1199 byte, non multiplo di 300: il record 4 e' incompleto, 299 byte dall'offset 900 del file");
    }

    @Test
    void byteNulloInUnCampoDiTestoRifiutato() throws Exception {
        byte[][] r = quattro();
        r[2][campo("acct_group_id").offset() + 2] = 0;
        rifiutato("byte-nullo", r, "campo ACCT-GROUP-ID (offset 712-721 del file, 112-121 del record)",
                "byte nullo X'00' all'offset 714 del file, non rappresentabile in una colonna di testo");
    }

    // --- accettati ------------------------------------------------------------------------------

    @Test
    void importoMassimoEMinimoDellaPictureAccettati() throws Exception {
        Map<String, Object> minimo = ordinario(0);
        Map<String, Object> massimo = ordinario(99999999999L);
        for (String importo : List.of("acct_curr_bal", "acct_credit_limit", "acct_cash_credit_limit",
                "acct_curr_cyc_credit", "acct_curr_cyc_debit")) {
            minimo.put(importo, new BigDecimal("-9999999999.99"));
            massimo.put(importo, new BigDecimal("9999999999.99"));
        }
        accettato("massimo-minimo", ContiDiProva.unisci(ContiDiProva.record(tracciato, minimo),
                ContiDiProva.record(tracciato, massimo)), List.of(minimo, massimo));
    }

    @Test
    void fileVuotoAccettatoZeroRighe() throws Exception {
        Path file = Files.write(cartella.resolve("vuoto.rec"), new byte[0]);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            assertEquals(new CaricatoreConti.EsitoCaricamento(0, false), CaricatoreConti.carica(file, c),
                    "esito di un file vuoto su tabella vuota");
            assertEquals(0, ContiDiProva.righe(c), "righe dopo un file vuoto");
            ContiDiProva.verificaCorrispondenza("vuoto", new byte[0], c);
        }
        System.out.println("[caricamento] file vuoto: 0 record, 0 righe, caricamento riuscito");
    }

    @Test
    void recordDistinguibiliCampoPerCampoAccettati() throws Exception {
        Map<String, Object> r1 = valori(10, "N", "-1234.56", "5000.00", "1500.00", "2010-01-01", "2026-02-02",
                "2024-03-03", "111.11", "-222.22", "12345     ", "GRUPPO1   ");
        Map<String, Object> r2 = valori(20, "X", "-0.01", "7000.50", "300.25", "2011-04-04", "2027-05-05",
                "2025-06-06", "-333.33", "444.44", "98765-4321", "G2        ");
        Map<String, Object> r3 = valori(30, "A", "42.00", "100.00", "99.99", "2012-07-07", "2028-08-08",
                "2026-09-09", "5.55", "6.66", "ZIP3      ", "GRUPPO-TRE");
        for (Map<String, Object> r : List.of(r1, r2, r3)) {
            assertNotEquals("Y", r.get("acct_active_status"));
            assertNotEquals(r.get("acct_credit_limit"), r.get("acct_cash_credit_limit"));
            assertNotEquals(r.get("acct_open_date"), r.get("acct_expiraion_date"));
            assertNotEquals(r.get("acct_open_date"), r.get("acct_reissue_date"));
            assertNotEquals(r.get("acct_expiraion_date"), r.get("acct_reissue_date"));
            assertNotEquals(0, ((BigDecimal) r.get("acct_curr_cyc_credit")).signum());
            assertNotEquals(0, ((BigDecimal) r.get("acct_curr_cyc_debit")).signum());
            assertNotEquals(r.get("acct_curr_cyc_credit"), r.get("acct_curr_cyc_debit"));
            assertNotEquals(r.get("acct_addr_zip"), r.get("acct_group_id"));
            assertNotEquals(" ".repeat(10), r.get("acct_group_id"));
        }
        accettato("distinguibili", ContiDiProva.unisci(ContiDiProva.record(tracciato, r1),
                ContiDiProva.record(tracciato, r2), ContiDiProva.record(tracciato, r3)), List.of(r1, r2, r3));
    }

    @Test
    void caratteriOltreAsciiAccettatiERicodificatiIdentici() throws Exception {
        // I 128 byte 0x80-0xFF distribuiti nei campi di testo di tre record (51 caratteri per record).
        int prossimo = 0x80;
        List<String> testi = List.of("acct_active_status", "acct_open_date", "acct_expiraion_date",
                "acct_reissue_date", "acct_addr_zip", "acct_group_id");
        Map<String, Object>[] record = new Map[3];
        for (int k = 0; k < 3; k++) {
            record[k] = ordinario(k + 1);
            for (String t : testi) {
                StringBuilder s = new StringBuilder();
                for (int i = 0; i < campo(t).lunghezza(); i++) {
                    s.append(prossimo <= 0xFF ? (char) prossimo++ : (char) ('a' + i));
                }
                record[k].put(t, s.toString());
            }
        }
        assertTrue(prossimo > 0xFF, "non tutti i byte 0x80-0xFF sono nei record");
        byte[] file = ContiDiProva.unisci(ContiDiProva.record(tracciato, record[0]),
                ContiDiProva.record(tracciato, record[1]), ContiDiProva.record(tracciato, record[2]));
        for (int b = 0x80; b <= 0xFF; b++) {
            boolean presente = false;
            for (byte x : file) {
                presente |= (x & 0xFF) == b;
            }
            assertTrue(presente, "byte " + Integer.toHexString(b) + " assente dal file costruito");
        }
        accettato("oltre-ascii", file, List.of(record));
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            List<String> lunghezze = PostgresDiProva.righe(c, "select acct_id, char_length(acct_group_id),"
                    + " octet_length(acct_group_id) from account order by acct_id");
            System.out.println("[caricamento] oltre ASCII, acct_group_id (chiave|caratteri|byte UTF-8): " + lunghezze);
            assertEquals("1|10|20", lunghezze.get(0), "caratteri e byte UTF-8 del gruppo del record 1");
        }
    }

    // --- appoggio -------------------------------------------------------------------------------

    static ContiDiProva.Campo campo(String colonna) {
        for (ContiDiProva.Campo c : tracciato) {
            if (colonna.equals(c.colonna())) {
                return c;
            }
        }
        fail("colonna " + colonna + " assente dal tracciato");
        return null;
    }

    static Map<String, Object> valori(long id, String stato, String saldo, String limite, String limiteContanti,
            String apertura, String scadenza, String riemissione, String credito, String addebito, String cap,
            String gruppo) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("acct_id", BigDecimal.valueOf(id));
        m.put("acct_active_status", stato);
        m.put("acct_curr_bal", new BigDecimal(saldo));
        m.put("acct_credit_limit", new BigDecimal(limite));
        m.put("acct_cash_credit_limit", new BigDecimal(limiteContanti));
        m.put("acct_open_date", apertura);
        m.put("acct_expiraion_date", scadenza);
        m.put("acct_reissue_date", riemissione);
        m.put("acct_curr_cyc_credit", new BigDecimal(credito));
        m.put("acct_curr_cyc_debit", new BigDecimal(addebito));
        m.put("acct_addr_zip", cap);
        m.put("acct_group_id", gruppo);
        return m;
    }

    /** Record valido qualsiasi, con la chiave data. */
    static Map<String, Object> ordinario(long id) {
        return valori(id, "Y", "194.00", "2020.00", "1020.00", "2014-11-20", "2025-05-20", "2025-05-20", "0.00",
                "0.00", "A000000000", " ".repeat(10));
    }

    /** Quattro record validi con chiavi 1-4. */
    static byte[][] quattro() {
        byte[][] r = new byte[4][];
        for (int i = 0; i < 4; i++) {
            r[i] = ContiDiProva.record(tracciato, ordinario(i + 1));
        }
        return r;
    }

    /** Quattro record validi, con i byte della colonna data del terzo sostituiti dal testo ASCII dato. */
    static byte[][] alterato(String colonna, String byteAscii) {
        byte[][] r = quattro();
        ContiDiProva.Campo c = campo(colonna);
        byte[] b = byteAscii.getBytes(StandardCharsets.US_ASCII);
        assertEquals(c.lunghezza(), b.length, "lunghezza dei byte sostitutivi di " + colonna);
        System.arraycopy(b, 0, r[2], c.offset(), b.length);
        return r;
    }

    void rifiutato(String nome, byte[][] record, String... diagnosi) throws Exception {
        rifiutatoFile(nome, ContiDiProva.unisci(record), diagnosi);
    }

    void rifiutatoFile(String nome, byte[] dati, String... diagnosi) throws Exception {
        Path file = Files.write(cartella.resolve(nome + ".rec"), dati);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            CaricamentoRifiutato e = assertThrows(CaricamentoRifiutato.class, () -> CaricatoreConti.carica(file, c),
                    nome + ": caricamento non rifiutato");
            System.out.println("[caricamento] " + nome + " rifiutato: " + e.getMessage());
            for (String d : diagnosi) {
                assertTrue(e.getMessage().contains(d), nome + ": diagnosi senza '" + d + "': " + e.getMessage());
            }
            assertTrue(c.getAutoCommit(), nome + ": autocommit della connessione non ripristinato");
        }
        try (Connection altra = PostgresDiProva.connessione(postgres)) {
            assertEquals(0, ContiDiProva.righe(altra), nome + ": righe scritte da un caricamento rifiutato");
        }
    }

    void accettato(String nome, byte[] dati, List<Map<String, Object>> attesi) throws Exception {
        Path file = Files.write(cartella.resolve(nome + ".rec"), dati);
        List<BigDecimal> legati = new ArrayList<>();
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            CaricatoreConti.EsitoCaricamento esito = CaricatoreConti.carica(file, ContiDiProva.registraImporti(c, legati));
            assertEquals(attesi.size(), esito.record(), nome + ": record caricati");
            assertTrue(!esito.giaCaricato(), nome + ": tabella vuota, il caricamento scrive");
        }
        ContiDiProva.verificaParametri(nome, dati, legati);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            ContiDiProva.verificaCorrispondenza(nome, dati, c);
            // Ogni colonna di ogni riga, letta via JDBC, uguale al valore da cui il record e' stato costruito.
            try (PreparedStatement st = c.prepareStatement("select * from account order by acct_id");
                    ResultSet rs = st.executeQuery()) {
                for (Map<String, Object> atteso : attesi) {
                    assertTrue(rs.next(), nome + ": righe mancanti");
                    for (Map.Entry<String, Object> v : atteso.entrySet()) {
                        Object letto = v.getValue() instanceof BigDecimal ? rs.getBigDecimal(v.getKey())
                                : rs.getString(v.getKey());
                        assertEquals(v.getValue(), letto, nome + ": colonna " + v.getKey() + " della chiave " + atteso.get("acct_id"));
                    }
                }
                assertTrue(!rs.next(), nome + ": righe in piu'");
            }
        }
    }
}
