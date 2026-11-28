package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.testcontainers.postgresql.PostgreSQLContainer;

import io.github.ltoscano.carddemo.loader.CaricatoreConti;

/**
 * Percorso del test di parita' di READACCT (issue #65): preparazione del database, avvio del job,
 * confronti, riesecuzione su file sentinella. Usato dai casi di parita' e dalle prove sull'avvio.
 */
final class ParitaReadacct {

    static final String[] USCITE = {"OUTFILE", "ARRYFILE", "VBRCFILE"};

    private ParitaReadacct() {
    }

    /** Ingresso versionato dello scenario: {@code <scenario>/ingresso.rec}. */
    static Path ingresso(Path scenario) {
        return scenario.resolve("ingresso.rec");
    }

    /**
     * Database vuoto e migrato, conti caricati con il caricatore di #60 da {@code daCaricare}; poi il
     * contenuto di {@code account} e' ricomposto con il codificatore indipendente dei test e deve
     * coincidere con {@code <scenario>/ingresso.rec}, ricavato qui dalla cartella dello scenario e non
     * da {@link #ingresso(Path)}: un errore nella scelta del file da caricare non si riflette nell'atteso.
     */
    static void prepara(PostgreSQLContainer postgres, Path daCaricare, Path scenario) throws Exception {
        Path ingressoAtteso = scenario.resolve("ingresso.rec");
        PostgresDiProva.migraDaVuoto(postgres);
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            CaricatoreConti.EsitoCaricamento esito = CaricatoreConti.carica(daCaricare, c);
            assertFalse(esito.giaCaricato(), "il database doveva essere vuoto");
            ContiDiProva.verificaCorrispondenza(ingressoAtteso.toString(), Files.readAllBytes(ingressoAtteso), c);
        }
    }

    static Map<String, String> ambiente(PostgreSQLContainer postgres) {
        return AvvioJob.ambiente(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
    }

    /** Cartella nuova per le uscite: i tre file devono essere assenti prima dell'avvio. */
    static Path cartellaUscite(Path base) throws IOException {
        Path cartella = Files.createDirectories(base.resolve("uscite"));
        for (String nome : USCITE) {
            assertFalse(Files.exists(cartella.resolve(nome)), nome + " gia' presente prima dell'avvio");
        }
        return cartella;
    }

    /**
     * Avvia il job con il comando del contratto e confronta. Se l'applicazione non trova il job
     * READACCT lancia {@link MotivoDichiarato}; ogni altro esito passa per i confronti.
     */
    static void avviaEConfronta(List<String> prefisso, Map<String, String> ambiente, Path scenario, Path uscite,
            Path log) throws Exception {
        AvvioJob.Esito esito = AvvioJob.avvia(prefisso, AvvioJob.argomenti(uscite), ambiente, log, AvvioJob.limite());
        AvvioJob.verificaJobPresente(esito, ambiente);
        ComparatoreReadacct.confronta(scenario, uscite, esito);
    }

    /**
     * Seconda esecuzione: i tre file di uscita sono sostituiti da file piu' lunghi del riferimento con
     * contenuto sentinella, poi il job e' riavviato e tutti i confronti si ripetono.
     */
    static void riavviaSuSentinelle(List<String> prefisso, Map<String, String> ambiente, Path scenario, Path uscite,
            Path log) throws Exception {
        for (String nome : USCITE) {
            long lunghezza = Files.size(scenario.resolve(nome)) + 1000;
            byte[] sentinella = new byte[(int) lunghezza];
            java.util.Arrays.fill(sentinella, (byte) 'S');
            Files.write(uscite.resolve(nome), sentinella);
        }
        avviaEConfronta(prefisso, ambiente, scenario, uscite, log);
    }

    /** Ingresso con i record di 300 byte in ordine inverso: stessi valori, ordine fisico diverso. */
    static Path permutato(Path ingresso, Path cartella) throws IOException {
        byte[] dati = Files.readAllBytes(ingresso);
        int n = dati.length / ContiDiProva.LUNGHEZZA_RECORD;
        assertEquals(0, dati.length % ContiDiProva.LUNGHEZZA_RECORD, "dimensione dell'ingresso");
        byte[] inverso = new byte[dati.length];
        for (int r = 0; r < n; r++) {
            System.arraycopy(dati, r * ContiDiProva.LUNGHEZZA_RECORD, inverso, (n - 1 - r) * ContiDiProva.LUNGHEZZA_RECORD,
                    ContiDiProva.LUNGHEZZA_RECORD);
        }
        Path file = cartella.resolve("ingresso-permutato.rec");
        Files.write(file, inverso);
        return file;
    }

    /** Chiavi della tabella nell'ordine fisico delle righe (ctid), non nell'ordine delle chiavi. */
    static List<String> chiaviInOrdineFisico(PostgreSQLContainer postgres) throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            return PostgresDiProva.righe(c, "select acct_id from account order by ctid");
        }
    }

    /** Chiavi dei record di un file d'ingresso, nell'ordine del file (prime 11 cifre di ogni record). */
    static List<String> chiaviDelFile(Path file) throws IOException {
        byte[] dati = Files.readAllBytes(file);
        List<String> chiavi = new ArrayList<>();
        for (int p = 0; p < dati.length; p += ContiDiProva.LUNGHEZZA_RECORD) {
            chiavi.add(String.valueOf(Long.parseLong(new String(dati, p, 11, java.nio.charset.StandardCharsets.US_ASCII))));
        }
        return chiavi;
    }
}
