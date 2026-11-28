package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.ltoscano.carddemo.loader.CaricamentoRifiutato;
import io.github.ltoscano.carddemo.loader.CaricatoreConti;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.Statement;
import java.util.List;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Issue #60, controlli 1-4 sul file dei conti che legge l'oracle ({@code analysis/oracle-dati/out/ACCTFILE.rec},
 * 50 record, #53), caricato con {@link CaricatoreConti} in PostgreSQL reale (immagine di
 * {@code compose.yaml}, migrazione con Flyway). Anche la riesecuzione: su una tabella non vuota il
 * caricamento si ferma e non cambia nulla.
 */
class CaricamentoContiTest {

    static PostgreSQLContainer postgres;

    /** Campo e non parametro: con un parametro surefire registrerebbe il caso con la firma. */
    @TempDir
    Path cartella;

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

            assertEquals(ContiDiProva.RECORD_DI_ESEMPIO, CaricatoreConti.carica(file, c), "record caricati");
            ContiDiProva.verificaCorrispondenza("ACCTFILE.rec", dati, c);
            assertEquals(List.of("1|50"), PostgresDiProva.righe(c, "select min(acct_id), max(acct_id) from account"),
                    "prima e ultima chiave");
        }
    }

    @Test
    void caricamentoSuTabellaNonVuotaSiFermaSenzaCambiareNulla() throws Exception {
        Path file = ContiDiProva.fileDiEsempio();
        byte[] dati = Files.readAllBytes(file);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            assertEquals(ContiDiProva.RECORD_DI_ESEMPIO, CaricatoreConti.carica(file, c), "primo caricamento");
            List<String> prima = PostgresDiProva.righe(c, "select * from account order by acct_id");

            CaricamentoRifiutato secondo = assertThrows(CaricamentoRifiutato.class, () -> CaricatoreConti.carica(file, c),
                    "secondo caricamento sulla tabella piena");
            System.out.println("[caricamento] secondo caricamento: " + secondo.getMessage());
            assertTrue(secondo.getMessage().contains("la tabella account non e' vuota (50 righe)"), secondo.getMessage());

            Path vuoto = Files.write(cartella.resolve("vuoto.rec"), new byte[0]);
            CaricamentoRifiutato terzo = assertThrows(CaricamentoRifiutato.class, () -> CaricatoreConti.carica(vuoto, c),
                    "file vuoto sulla tabella piena");
            assertTrue(terzo.getMessage().contains("non e' vuota"), terzo.getMessage());

            assertEquals(prima, PostgresDiProva.righe(c, "select * from account order by acct_id"),
                    "righe cambiate dopo i caricamenti rifiutati");
            assertTrue(c.getAutoCommit(), "autocommit della connessione ripristinato");
            ContiDiProva.verificaCorrispondenza("ACCTFILE.rec dopo la riesecuzione", dati, c);
        }
    }
}
