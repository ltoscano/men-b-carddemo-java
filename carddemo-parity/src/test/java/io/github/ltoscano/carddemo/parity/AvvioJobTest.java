package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

import io.github.ltoscano.carddemo.parity.provajob.erroreprima.AppErrorePrimaDellaSelezione;
import io.github.ltoscano.carddemo.parity.provajob.nontermina.AppCheNonTermina;
import io.github.ltoscano.carddemo.parity.provajob.readacctfallisce.AppReadacctCheFallisce;
import io.github.ltoscano.carddemo.parity.provajob.readacctsilenziosa.AppReadacctCheFallisceSenzaLog;
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

    private static Path preparaMirato(PostgreSQLContainer postgres) throws Exception {
        Path scenario = ComparatoreReadacct.scenario("mirato");
        ParitaReadacct.prepara(postgres, ParitaReadacct.ingresso(scenario), scenario);
        return scenario;
    }

    @Test
    void nessunJobReadacctRiconosciutoComeMotivoDichiarato() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            Path scenario = preparaMirato(postgres);
            MotivoDichiarato e = assertThrows(MotivoDichiarato.class, () -> ParitaReadacct.avviaEConfronta(
                    AvvioJob.comandoClasse(AppSenzaReadacct.class), ambienteDiProva(postgres), scenario,
                    ParitaReadacct.cartellaUscite(tmp), tmp.resolve("log")));
            assertEquals(AvvioJob.JOB_ASSENTE, e.codice());
            System.out.println("[avvio] job assente -> " + e.getMessage());
            try (var c = PostgresDiProva.connessione(postgres)) {
                assertEquals(List.of("0|0"), PostgresDiProva.righe(c, AvvioJob.CONTEGGIO_JOB),
                        "tabelle di Spring Batch presenti e senza istanze ne' esecuzioni");
            }
        }
    }

    @Test
    void jobDiNomeReadacctConAltroBeanEsisteEFallisceSuiConfrontiPoiSullaRiesecuzione() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            Path scenario = preparaMirato(postgres);
            List<String> comando = AvvioJob.comandoClasse(AppReadacctVuoto.class);
            Path uscite = ParitaReadacct.cartellaUscite(tmp);

            AvvioJob.Esito esito = AvvioJob.avvia(comando, AvvioJob.argomenti(uscite), ambienteDiProva(postgres),
                    tmp.resolve("log"), AvvioJob.limite());
            assertEquals(0, esito.uscita(), "il job di prova doveva terminare con 0: " + esito.riassunto());
            assertFalse(AvvioJob.jobAssente(esito, ambienteDiProva(postgres)), "il rilevatore doveva vedere il job READACCT");
            // le tracce di avvio cercate dal rilevatore sono quelle che Spring Batch scrive davvero
            for (String traccia : AvvioJob.TRACCE_DI_AVVIO) {
                assertTrue(esito.testo().contains(traccia), "traccia di avvio assente nell'uscita reale: " + traccia);
            }

            AssertionError confronti = assertThrows(AssertionError.class,
                    () -> ComparatoreReadacct.confronta(scenario, uscite, esito));
            System.out.println("[avvio] job vuoto -> " + confronti.getMessage());
            assertEquals("FILE-ASSENTE: OUTFILE non e' stato scritto: " + uscite.resolve("OUTFILE"), confronti.getMessage());

            AssertionError riesecuzione = assertThrows(AssertionError.class, () -> ParitaReadacct.riavviaSuSentinelle(
                    comando, ambienteDiProva(postgres), scenario, uscite, tmp.resolve("log")));
            System.out.println("[avvio] sentinelle intatte -> " + riesecuzione.getMessage());
            assertTrue(riesecuzione.getMessage().startsWith("BYTE-DIVERSO: OUTFILE record 1 posizione 1: atteso "),
                    riesecuzione.getMessage());
            assertTrue(riesecuzione.getMessage().endsWith(", trovato 53"), riesecuzione.getMessage());
            assertTrue(Files.readString(uscite.resolve("OUTFILE")).startsWith("SSSS"), "sentinella attesa ancora presente");
        }
    }

    /** Controprova del rilievo 1: job READACCT avviato che fallisce stampando la stessa traccia del job assente. */
    @Test
    void jobReadacctPresenteCheFallisceConIlTestoDelJobAssenteNonEIlMotivoDichiarato() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            Path scenario = preparaMirato(postgres);
            Path uscite = ParitaReadacct.cartellaUscite(tmp);
            List<String> comando = AvvioJob.comandoClasse(AppReadacctCheFallisce.class);
            AvvioJob.Esito esito = AvvioJob.avvia(comando, AvvioJob.argomenti(uscite), ambienteDiProva(postgres),
                    tmp.resolve("log"), AvvioJob.limite());
            assertEquals(1, esito.uscita(), esito.riassunto());
            assertTrue(esito.testo().contains(AvvioJob.CAUSA), "la traccia contraffatta doveva comparire");
            assertFalse(AvvioJob.jobAssente(esito, ambienteDiProva(postgres)), "un job avviato non e' un job assente");
            AssertionError e = assertThrows(AssertionError.class, () -> ParitaReadacct.avviaEConfronta(comando,
                    ambienteDiProva(postgres), scenario, ParitaReadacct.cartellaUscite(tmp.resolve("seconda")), tmp.resolve("log")));
            System.out.println("[avvio] job presente che fallisce -> " + e.getMessage().substring(0, 60));
            assertTrue(e.getMessage().startsWith("CODICE-DI-USCITA: atteso 0, trovato 1;"), e.getMessage());
        }
    }

    /**
     * Controprova del bloccante della seconda validazione: job READACCT avviato che stampa la traccia
     * nativa e fallisce con 1, con il livello di log a WARN fissato nell'applicazione: le righe di
     * avvio non ci sono, e solo il repository di Spring Batch mostra che il job e' partito.
     */
    @Test
    void jobReadacctAvviatoConLogAWarnCheFallisceConLaTracciaNonEIlMotivoDichiarato() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            Path scenario = preparaMirato(postgres);
            Path uscite = ParitaReadacct.cartellaUscite(tmp);
            List<String> comando = AvvioJob.comandoClasse(AppReadacctCheFallisceSenzaLog.class);
            AvvioJob.Esito esito = AvvioJob.avvia(comando, AvvioJob.argomenti(uscite), ambienteDiProva(postgres),
                    tmp.resolve("log"), AvvioJob.limite());
            assertEquals(1, esito.uscita(), esito.riassunto());
            assertTrue(esito.testo().contains(AvvioJob.CAUSA), "la traccia contraffatta doveva comparire");
            for (String traccia : AvvioJob.TRACCE_DI_AVVIO) {
                assertFalse(esito.testo().contains(traccia), "con i log a WARN la traccia di avvio non doveva esserci: " + traccia);
            }
            assertTrue(AvvioJob.tracciaNativa(esito), "le condizioni sull'uscita da sole non distinguono questo caso");
            try (var c = PostgresDiProva.connessione(postgres)) {
                assertEquals(List.of("1|1"), PostgresDiProva.righe(c, AvvioJob.CONTEGGIO_JOB),
                        "il repository di Spring Batch doveva registrare l'istanza e l'esecuzione del job avviato");
            }
            assertFalse(AvvioJob.jobAssente(esito, ambienteDiProva(postgres)), "un job avviato non e' un job assente");
            AssertionError e = assertThrows(AssertionError.class,
                    () -> {
                        AvvioJob.verificaJobPresente(esito, ambienteDiProva(postgres));
                        ComparatoreReadacct.confronta(scenario, uscite, esito);
                    });
            System.out.println("[avvio] job avviato con log a WARN -> " + e.getMessage().substring(0, 60));
            assertTrue(e.getMessage().startsWith("CODICE-DI-USCITA: atteso 0, trovato 1;"), e.getMessage());
        }
    }

    /** Controprova del rilievo 1: errore con il testo del job assente prima della selezione del job. */
    @Test
    void erroreConIlTestoDelJobAssentePrimaDellaSelezioneNonEIlMotivoDichiarato() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            Path scenario = preparaMirato(postgres);
            List<String> comando = AvvioJob.comandoClasse(AppErrorePrimaDellaSelezione.class);
            Path uscite = ParitaReadacct.cartellaUscite(tmp);
            AvvioJob.Esito esito = AvvioJob.avvia(comando, AvvioJob.argomenti(uscite), ambienteDiProva(postgres),
                    tmp.resolve("log"), AvvioJob.limite());
            assertEquals(1, esito.uscita(), esito.riassunto());
            assertTrue(esito.testo().contains(AvvioJob.CAUSA), "l'errore doveva avere lo stesso testo: " + esito.riassunto());
            assertFalse(AvvioJob.jobAssente(esito, ambienteDiProva(postgres)), "un errore prima della selezione non e' un job assente");
            AssertionError e = assertThrows(AssertionError.class,
                    () -> ComparatoreReadacct.confronta(scenario, uscite, esito));
            assertTrue(e.getMessage().startsWith("CODICE-DI-USCITA: atteso 0, trovato 1;"), e.getMessage());
        }
    }

    @Test
    void erroreDelDatabaseDelSoloAvvioNonEIlMotivoDichiarato() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            Path scenario = preparaMirato(postgres);
            // database del job irraggiungibile: porta 1 dello stesso host; il database dei test resta in uso
            String url = "jdbc:postgresql://" + postgres.getHost() + ":1/" + postgres.getDatabaseName();
            Map<String, String> ambiente = AvvioJob.ambiente(url, postgres.getUsername(), postgres.getPassword());
            AssertionError e = assertThrows(AssertionError.class, () -> ParitaReadacct.avviaEConfronta(
                    AvvioJob.comandoJar(), ambiente, scenario, ParitaReadacct.cartellaUscite(tmp), tmp.resolve("log")));
            System.out.println("[avvio] database irraggiungibile -> " + e.getMessage().substring(0, 60));
            assertTrue(e.getMessage().startsWith("CODICE-DI-USCITA: atteso 0, trovato 1;"), e.getMessage());
            try (var c = PostgresDiProva.connessione(postgres)) {
                assertEquals(List.of("1"), PostgresDiProva.righe(c, "select 1"), "il database dei test doveva restare raggiungibile");
            }
        }
    }

    /** Rilievo 2: allo scadere del limite si termina l'intero albero (processo, figlio, nipote). */
    @Test
    void alloScadereDelLimiteSiTerminaLInteroAlbero() throws Exception {
        Path pid = tmp.resolve("pid");
        AssertionError e = assertThrows(AssertionError.class, () -> AvvioJob.avvia(
                AvvioJob.comandoClasse(AppCheNonTermina.class), List.of(), Map.of("MENB_PID_FILE", pid.toString()),
                tmp.resolve("log"), Duration.ofSeconds(8)));
        System.out.println("[avvio] limite di tempo -> " + e.getMessage().substring(0, 120));
        assertTrue(e.getMessage().startsWith("AVVIO-LIMITE-DI-TEMPO: il processo non e' terminato entro PT8S;"
                + " albero terminato, nessun processo sopravvissuto;"), e.getMessage());
        assertTrue(Files.exists(pid), "l'applicazione di prova non ha scritto i pid entro il limite");
        List<Long> pids = new ArrayList<>();
        for (String r : Files.readAllLines(pid, StandardCharsets.US_ASCII)) {
            pids.add(Long.parseLong(r.trim()));
        }
        assertEquals(3, pids.size(), "pid di processo, figlio e nipote");
        for (long p : pids) {
            assertFalse(ProcessHandle.of(p).map(ProcessHandle::isAlive).orElse(false), "processo " + p + " sopravvissuto");
        }
    }
}
