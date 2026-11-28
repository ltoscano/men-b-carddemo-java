package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import io.github.ltoscano.carddemo.loader.CaricamentoRifiutato;
import io.github.ltoscano.carddemo.loader.CaricatoreConti;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Issue #60, concorrenza: due caricatori avviati insieme sullo stesso database vuoto. Al piu' uno
 * scrive; l'altro si ferma o trova la tabella identica al suo file.
 *
 * <p>Per farli arrivare davvero insieme al controllo della tabella, il test tiene un blocco
 * {@code ACCESS EXCLUSIVE} su {@code account} finche' entrambi non risultano in attesa su quella
 * tabella ({@code pg_locks}, non concesso), poi lo rilascia: da quel momento competono. Senza la
 * serializzazione nel caricatore entrambi troverebbero la tabella vuota.
 */
class CaricamentoConcorrenteTest {

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

    @Test
    void dueCaricatoriInsiemeConLeStesseChiavi() throws Exception {
        byte[] dati = file(1, 2, 3);
        Path a = Files.write(cartella.resolve("a.rec"), dati);
        Path b = Files.write(cartella.resolve("b.rec"), dati);
        List<Object> esiti = insieme(a, b);
        int scritto = 0;
        int giaCaricato = 0;
        for (Object e : esiti) {
            if (!(e instanceof CaricatoreConti.EsitoCaricamento esito)) {
                fail("con lo stesso file entrambi devono riuscire (uno scrive, l'altro lo trova gia' caricato): " + esiti);
                return;
            }
            if (esito.giaCaricato()) {
                giaCaricato++;
            } else {
                scritto++;
            }
        }
        assertEquals(1, scritto, "caricatori che hanno scritto: " + esiti);
        assertEquals(1, giaCaricato, "caricatori che hanno trovato la tabella gia' caricata: " + esiti);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            ContiDiProva.verificaCorrispondenza("concorrenti, stesse chiavi", dati, c);
        }
    }

    @Test
    void dueCaricatoriInsiemeConChiaviDisgiunte() throws Exception {
        byte[] datiA = file(1, 2);
        byte[] datiB = file(3, 4);
        Path a = Files.write(cartella.resolve("a.rec"), datiA);
        Path b = Files.write(cartella.resolve("b.rec"), datiB);
        List<Object> esiti = insieme(a, b);
        int riusciti = 0;
        int vincitore = -1;
        for (int i = 0; i < 2; i++) {
            Object e = esiti.get(i);
            if (e instanceof CaricatoreConti.EsitoCaricamento esito) {
                assertTrue(!esito.giaCaricato(), "chiavi disgiunte: nessuno puo' trovare la tabella identica: " + esiti);
                riusciti++;
                vincitore = i;
            } else if (e instanceof CaricamentoRifiutato r) {
                assertTrue(r.getMessage().contains("non contiene esattamente i 2 record del file"), r.getMessage());
            } else {
                fail("esito inatteso: " + e);
            }
        }
        assertEquals(1, riusciti, "con chiavi disgiunte deve riuscire uno solo: " + esiti);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            ContiDiProva.verificaCorrispondenza("concorrenti, chiavi disgiunte", vincitore == 0 ? datiA : datiB, c);
        }
    }

    /** File di record validi con le chiavi date. */
    byte[] file(long... chiavi) {
        byte[][] r = new byte[chiavi.length][];
        for (int i = 0; i < chiavi.length; i++) {
            r[i] = ContiDiProva.record(tracciato, CaricamentoContiCasiTest.ordinario(chiavi[i]));
        }
        return ContiDiProva.unisci(r);
    }

    /** Avvia i due caricamenti insieme; per ciascuno l'esito o l'eccezione. Ogni attesa ha un limite. */
    List<Object> insieme(Path a, Path b) throws Exception {
        ExecutorService esecutori = Executors.newFixedThreadPool(2);
        try (Connection cancello = PostgresDiProva.connessione(postgres);
                Connection osservatore = PostgresDiProva.connessione(postgres)) {
            cancello.setAutoCommit(false);
            try (Statement st = cancello.createStatement()) {
                st.execute("lock table account in access exclusive mode");
            }
            List<Future<Object>> futuri = new ArrayList<>();
            for (Path p : List.of(a, b)) {
                futuri.add(esecutori.submit(() -> {
                    try (Connection c = PostgresDiProva.connessione(postgres)) {
                        return CaricatoreConti.carica(p, c);
                    } catch (CaricamentoRifiutato e) {
                        return e;
                    }
                }));
            }
            long scadenza = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
            String inAttesa = "0";
            while (!"2".equals(inAttesa)) {
                inAttesa = PostgresDiProva.righe(osservatore, "select count(*) from pg_locks where relation ="
                        + " 'public.account'::regclass and not granted").get(0);
                if (System.nanoTime() > scadenza) {
                    fail("i due caricatori non risultano in attesa sulla tabella entro 30 s (" + inAttesa + " in attesa)");
                }
                Thread.sleep(50);
            }
            cancello.commit();
            List<Object> esiti = new ArrayList<>();
            for (Future<Object> f : futuri) {
                esiti.add(f.get(60, TimeUnit.SECONDS));
            }
            System.out.println("[caricamento] concorrenti: " + esiti);
            return esiti;
        } finally {
            esecutori.shutdownNow();
            assertTrue(esecutori.awaitTermination(30, TimeUnit.SECONDS), "caricatori ancora in esecuzione");
        }
    }
}
