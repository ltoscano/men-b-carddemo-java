package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

import io.github.ltoscano.carddemo.parity.provajob.readacctvuoto.AppReadacctVuoto;
import io.github.ltoscano.carddemo.parity.provajob.senzareadacct.AppSenzaReadacct;

/**
 * Prove sull'avvio e sul riconoscimento del job READACCT (issue #65), con applicazioni di prova dei
 * test (pacchetto {@code provajob}) lanciate in un processo proprio, e con il jar vero per l'errore
 * del database. Non marcate: devono passare ora e dopo la traduzione.
 */
class AvvioJobTest {

    @TempDir
    Path tmp;

    /** Ambiente delle applicazioni di prova: connessione, nessun server web, metadati di Spring Batch. */
    private static Map<String, String> ambienteDiProva(PostgreSQLContainer postgres) {
        Map<String, String> ambiente = new HashMap<>(ParitaReadacct.ambiente(postgres));
        ambiente.put("SPRING_MAIN_WEB_APPLICATION_TYPE", "none");
        ambiente.put("SPRING_BATCH_JDBC_INITIALIZE_SCHEMA", "always");
        return ambiente;
    }

    @Test
    void nessunJobReadacctRiconosciutoComeMotivoDichiarato() throws Exception {
        Path scenario = ComparatoreReadacct.scenario("mirato");
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            ParitaReadacct.prepara(postgres, ParitaReadacct.ingresso(scenario), scenario);
            MotivoDichiarato e = assertThrows(MotivoDichiarato.class, () -> ParitaReadacct.avviaEConfronta(
                    AvvioJob.comandoClasse(AppSenzaReadacct.class), ambienteDiProva(postgres), scenario,
                    ParitaReadacct.cartellaUscite(tmp), tmp.resolve("log")));
            assertEquals(AvvioJob.JOB_ASSENTE, e.codice());
            System.out.println("[avvio] job assente -> " + e.getMessage());
        }
    }

    @Test
    void jobDiNomeReadacctConAltroBeanEsisteEFallisceSuiConfrontiPoiSullaRiesecuzione() throws Exception {
        Path scenario = ComparatoreReadacct.scenario("mirato");
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            ParitaReadacct.prepara(postgres, ParitaReadacct.ingresso(scenario), scenario);
            List<String> comando = AvvioJob.comandoClasse(AppReadacctVuoto.class);
            Path uscite = ParitaReadacct.cartellaUscite(tmp);

            AvvioJob.Esito esito = AvvioJob.avvia(comando, AvvioJob.argomenti(uscite), ambienteDiProva(postgres),
                    tmp.resolve("log"), AvvioJob.LIMITE);
            assertEquals(0, esito.uscita(), "il job di prova doveva terminare con 0: " + esito.riassunto());
            assertFalse(AvvioJob.jobAssente(esito), "il rilevatore doveva vedere il job READACCT");

            AssertionError confronti = assertThrows(AssertionError.class,
                    () -> ComparatoreReadacct.confronta(scenario, uscite, esito));
            System.out.println("[avvio] job vuoto -> " + confronti.getMessage());
            assertTrue(confronti.getMessage().startsWith("FILE-ASSENTE: OUTFILE"), confronti.getMessage());

            AssertionError riesecuzione = assertThrows(AssertionError.class, () -> ParitaReadacct.riavviaSuSentinelle(
                    comando, ambienteDiProva(postgres), scenario, uscite, tmp.resolve("log")));
            System.out.println("[avvio] sentinelle intatte -> " + riesecuzione.getMessage());
            assertTrue(riesecuzione.getMessage().startsWith("LUNGHEZZA: OUTFILE")
                    || riesecuzione.getMessage().startsWith("BYTE-DIVERSO: OUTFILE record 1"), riesecuzione.getMessage());
            assertTrue(Files.readString(uscite.resolve("OUTFILE")).startsWith("SSSS"), "sentinella attesa ancora presente");
        }
    }

    @Test
    void erroreDelDatabaseDelSoloAvvioNonEIlMotivoDichiarato() throws Exception {
        Path scenario = ComparatoreReadacct.scenario("mirato");
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            ParitaReadacct.prepara(postgres, ParitaReadacct.ingresso(scenario), scenario);
            // database del job irraggiungibile: porta 1 dello stesso host; il database dei test resta in uso
            String url = "jdbc:postgresql://" + postgres.getHost() + ":1/" + postgres.getDatabaseName();
            Map<String, String> ambiente = AvvioJob.ambiente(url, postgres.getUsername(), postgres.getPassword());
            AssertionError e = assertThrows(AssertionError.class, () -> ParitaReadacct.avviaEConfronta(
                    AvvioJob.comandoJar(), ambiente, scenario, ParitaReadacct.cartellaUscite(tmp), tmp.resolve("log")));
            System.out.println("[avvio] database irraggiungibile -> " + e.getMessage().substring(0, 60));
            assertTrue(e.getMessage().startsWith("CODICE-DI-USCITA"), e.getMessage());
            assertEquals(List.of("1"), PostgresDiProva.righe(PostgresDiProva.connessione(postgres), "select 1"),
                    "il database dei test doveva restare raggiungibile");
        }
    }
}
