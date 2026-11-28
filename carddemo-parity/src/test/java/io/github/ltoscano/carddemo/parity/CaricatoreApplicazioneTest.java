package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.github.ltoscano.carddemo.loader.CaricatoreApplication;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Issue #60: l'applicazione del caricatore avviata nel processo dei test su un PostgreSQL vuoto
 * (immagine di {@code compose.yaml}), con il suo {@code application.properties} indicato
 * esplicitamente (sul classpath di {@code carddemo-parity} ce ne sono tre con lo stesso nome).
 * Applica da se' la migrazione, carica e termina con il codice dell'esito; una seconda esecuzione
 * sulla tabella piena e un file rifiutato terminano con il codice di rifiuto senza cambiare nulla.
 *
 * <p>Limite (come per {@code AccountMigrazioneTest}): il classpath e' quello di {@code carddemo-parity},
 * piu' ricco di quello distribuito; la prova con l'immagine del caricatore e' nello smoke.
 */
class CaricatoreApplicazioneTest {

    /** Campo e non parametro: con un parametro surefire registrerebbe il caso con la firma. */
    @TempDir
    Path cartella;

    @Test
    void ilCaricatoreMigraCaricaETerminaConZeroPoiRifiutaLaSecondaEsecuzione() throws Exception {
        Path file = ContiDiProva.fileDiEsempio();
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            try (Connection c = PostgresDiProva.connessione(postgres)) {
                assertEquals(List.of("0"), PostgresDiProva.righe(c, "select count(*) from pg_class c join pg_namespace n"
                        + " on n.oid = c.relnamespace where n.nspname = 'public'"), "database non vuoto prima dell'avvio");
            }
            assertEquals(CaricatoreApplication.USCITA_RIUSCITA, esegui(postgres, file.toString()), "primo caricamento");
            try (Connection c = PostgresDiProva.connessione(postgres)) {
                assertEquals(List.of("1|1|V1__account.sql|t"), PostgresDiProva.righe(c, "select installed_rank, version,"
                        + " script, success from flyway_schema_history order by installed_rank"), "storico di Flyway");
                ContiDiProva.verificaCorrispondenza("ACCTFILE.rec (applicazione)", Files.readAllBytes(file), c);
            }
            assertEquals(CaricatoreApplication.USCITA_RIFIUTATO, esegui(postgres, file.toString()),
                    "seconda esecuzione sulla tabella piena");
            try (Connection c = PostgresDiProva.connessione(postgres)) {
                ContiDiProva.verificaCorrispondenza("ACCTFILE.rec (dopo la seconda esecuzione)", Files.readAllBytes(file), c);
            }
        }
    }

    @Test
    void fileRifiutatoTerminaConIlCodiceDiRifiutoEZeroRighe() throws Exception {
        byte[] dati = Files.readAllBytes(ContiDiProva.fileDiEsempio());
        Path troncato = Files.write(cartella.resolve("troncato.rec"), Arrays.copyOf(dati, dati.length - 1));
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            assertEquals(CaricatoreApplication.USCITA_RIFIUTATO, esegui(postgres, troncato.toString()), "file troncato");
            try (Connection c = PostgresDiProva.connessione(postgres)) {
                assertEquals(0, ContiDiProva.righe(c), "righe dopo un file rifiutato");
            }
            assertEquals(CaricatoreApplication.USCITA_ERRORE, esegui(postgres, cartella.resolve("assente.rec").toString()),
                    "file inesistente");
            assertEquals(CaricatoreApplication.USCITA_ERRORE, esegui(postgres), "nessun file indicato");
            assertEquals(CaricatoreApplication.USCITA_ERRORE, esegui(postgres, troncato.toString(), troncato.toString()),
                    "due file indicati");
        }
    }

    static int esegui(PostgreSQLContainer postgres, String... file) throws Exception {
        String[] opzioni = {
            "--spring.config.location=" + AccountMigrazioneTest.proprietaDellApplicazione(CaricatoreApplication.class),
            "--spring.datasource.url=" + postgres.getJdbcUrl(),
            "--spring.datasource.username=" + postgres.getUsername(),
            "--spring.datasource.password=" + postgres.getPassword(),
        };
        String[] argomenti = Arrays.copyOf(opzioni, opzioni.length + file.length);
        System.arraycopy(file, 0, argomenti, opzioni.length, file.length);
        return CaricatoreApplication.esegui(argomenti);
    }
}
