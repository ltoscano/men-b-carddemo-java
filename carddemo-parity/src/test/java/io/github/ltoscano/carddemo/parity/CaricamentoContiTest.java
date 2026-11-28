package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.ltoscano.carddemo.loader.CaricamentoRifiutato;
import io.github.ltoscano.carddemo.loader.CaricatoreConti;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Issue #60, controlli 1-4 e 6 sul file dei conti che legge l'oracle
 * ({@code analysis/oracle-dati/out/ACCTFILE.rec}, 50 record, #53), caricato con {@link CaricatoreConti}
 * in PostgreSQL reale (immagine di {@code compose.yaml}, migrazione con Flyway), e la riesecuzione:
 * sulla tabella che contiene esattamente il file il caricamento riesce senza scrivere; su una tabella
 * diversa si ferma con la prima differenza, senza scrivere.
 */
class CaricamentoContiTest {

    static PostgreSQLContainer postgres;

    /** Campo e non parametro: con un parametro surefire registrerebbe il caso con la firma. */
    @TempDir
    Path cartella;

    /** Righe con xmin (transazione che le ha scritte): se nulla viene scritto, nulla cambia. */
    static final String RIGHE_CON_XMIN = "select xmin::text, * from account order by acct_id";

    @BeforeAll
    static void avvia() throws Exception {
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

    @Test
    void ilFileDiEsempioSiCaricaECorrispondeRecordPerRecord() throws Exception {
        Path file = ContiDiProva.fileDiEsempio();
        byte[] dati = Files.readAllBytes(file);
        assertEquals(ContiDiProva.RECORD_DI_ESEMPIO * ContiDiProva.LUNGHEZZA_RECORD, dati.length,
                "dimensione di ACCTFILE.rec (#53: 50 record di 300 byte)");
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            List<String> codifica = PostgresDiProva.righe(c, "select current_setting('server_encoding'),"
                    + " current_setting('client_encoding'), pg_encoding_to_char(encoding) from pg_database"
                    + " where datname = current_database()");
            System.out.println("[caricamento] codifica del database (server|client|database): " + codifica);
            assertEquals(List.of("UTF8|UTF8|UTF8"), codifica, "codifica effettiva del database");

            List<BigDecimal> legati = new ArrayList<>();
            CaricatoreConti.EsitoCaricamento esito = CaricatoreConti.carica(file, ContiDiProva.registraImporti(c, legati));
            assertEquals(ContiDiProva.RECORD_DI_ESEMPIO, esito.record(), "record caricati");
            assertFalse(esito.giaCaricato(), "tabella vuota: il caricamento scrive");
            ContiDiProva.verificaParametri("ACCTFILE.rec", dati, legati);
            ContiDiProva.verificaCorrispondenza("ACCTFILE.rec", dati, c);
            // Primo e ultimo conto con valori scritti a mano, letti dai byte del file (xxd): non dipendono
            // da nessun tracciato del codice.
            assertEquals(List.of(
                    "1|Y|194.00|2020.00|1020.00|2014-11-20|2025-05-20|2025-05-20|0.00|0.00|A000000000|          ",
                    "50|Y|492.00|6169.00|4587.00|2011-04-22|2023-03-09|2023-03-09|0.00|0.00|A000000000|          "),
                    PostgresDiProva.righe(c, "select * from account where acct_id in (1, 50) order by acct_id"),
                    "primo e ultimo conto, colonna per colonna");
        }
    }

    @Test
    void secondoCaricamentoDelloStessoFileRiesceSenzaScrivere() throws Exception {
        Path file = ContiDiProva.fileDiEsempio();
        byte[] dati = Files.readAllBytes(file);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            assertFalse(CaricatoreConti.carica(file, c).giaCaricato(), "primo caricamento");
            List<String> prima = PostgresDiProva.righe(c, RIGHE_CON_XMIN);

            List<BigDecimal> legati = new ArrayList<>();
            CaricatoreConti.EsitoCaricamento secondo = CaricatoreConti.carica(file, ContiDiProva.registraImporti(c, legati));
            System.out.println("[caricamento] secondo caricamento: " + secondo);
            assertTrue(secondo.giaCaricato(), "tabella identica al file: gia' caricato");
            assertEquals(ContiDiProva.RECORD_DI_ESEMPIO, secondo.record(), "record del file");
            assertEquals(List.of(), legati, "nessun inserimento preparato sulla tabella gia' caricata");
            assertEquals(prima, PostgresDiProva.righe(c, RIGHE_CON_XMIN), "righe o xmin cambiati: qualcosa e' stato scritto");
            assertTrue(c.getAutoCommit(), "autocommit della connessione ripristinato");
            ContiDiProva.verificaCorrispondenza("ACCTFILE.rec dopo la riesecuzione", dati, c);
        }
    }

    @Test
    void tabellaDiversaDalFileSiFermaConLaPrimaDifferenzaSenzaScrivere() throws Exception {
        Path file = ContiDiProva.fileDiEsempio();
        byte[] dati = Files.readAllBytes(file);
        Path vuoto = Files.write(cartella.resolve("vuoto.rec"), new byte[0]);
        Path primi49 = Files.write(cartella.resolve("primi49.rec"), Arrays.copyOf(dati, 49 * ContiDiProva.LUNGHEZZA_RECORD));
        diversa(file, "update account set acct_curr_bal = acct_curr_bal + 1 where acct_id = 1",
                "Prima differenza: chiave 1, record 1 (offset 0-299 del file), campo ACCT-CURR-BAL"
                        + " (offset 12-23 del file, 12-23 del record): nella tabella 195.00 (byte 30303030303030313935307b)");
        diversa(file, "update account set acct_reissue_date = '2025-05-21' where acct_id = 50",
                "Prima differenza: chiave 50, record 50 (offset 14700-14999 del file), campo ACCT-REISSUE-DATE");
        diversa(file, "delete from account where acct_id = 50",
                "Prima differenza: record 50 (offset 14700-14999 del file): la chiave ACCT-ID del file manca nella tabella");
        diversa(file, "insert into account select 51, acct_active_status, acct_curr_bal, acct_credit_limit,"
                        + " acct_cash_credit_limit, acct_open_date, acct_expiraion_date, acct_reissue_date,"
                        + " acct_curr_cyc_credit, acct_curr_cyc_debit, acct_addr_zip, acct_group_id from account where acct_id = 1",
                "Prima differenza: la tabella ha la chiave 51, che nel file non c'e'");
        diversa(primi49, null, "Prima differenza: la tabella ha la chiave 50, che nel file non c'e'");
        diversa(vuoto, null, "la tabella account non e' vuota (50 righe) e non contiene esattamente i 0 record del file");
    }

    /**
     * Carica il file di esempio, applica l'alterazione (se c'e'), poi carica {@code file}: deve fermarsi
     * con la diagnosi attesa senza cambiare nulla (righe e xmin).
     */
    void diversa(Path file, String alterazione, String diagnosi) throws Exception {
        tabellaVuota();
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            assertFalse(CaricatoreConti.carica(ContiDiProva.fileDiEsempio(), c).giaCaricato(), "caricamento di partenza");
            if (alterazione != null) {
                try (Statement st = c.createStatement()) {
                    st.execute(alterazione);
                }
            }
            List<String> prima = PostgresDiProva.righe(c, RIGHE_CON_XMIN);
            CaricamentoRifiutato e = assertThrows(CaricamentoRifiutato.class, () -> CaricatoreConti.carica(file, c),
                    "tabella diversa dal file accettata (" + alterazione + ")");
            System.out.println("[caricamento] tabella diversa (" + alterazione + "): " + e.getMessage());
            assertTrue(e.getMessage().contains(diagnosi), "diagnosi senza '" + diagnosi + "': " + e.getMessage());
            assertEquals(prima, PostgresDiProva.righe(c, RIGHE_CON_XMIN), "righe cambiate da un caricamento rifiutato");
            assertTrue(c.getAutoCommit(), "autocommit della connessione ripristinato");
        }
    }
}
