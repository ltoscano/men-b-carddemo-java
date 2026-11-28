package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.ltoscano.carddemo.batch.BatchApplication;
import io.github.ltoscano.carddemo.online.OnlineApplication;
import java.io.InputStream;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import org.flywaydb.core.api.output.MigrateResult;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Controllo 5 di #59: la migrazione applicata due volte non cambia nulla; una migrazione gia'
 * applicata e poi modificata fa fallire l'avvio delle applicazioni (validazione di Flyway attiva);
 * primo avvio e riavvio delle applicazioni {@code online} e {@code batch} su un database vuoto,
 * in entrambi gli ordini, con le tabelle di Spring Batch create dal loro inizializzatore e la
 * tabella {@code account} creata da Flyway.
 *
 * <p>Le applicazioni si avviano qui nello stesso processo, con la loro classe principale e il loro
 * {@code application.properties}: sul classpath di questo modulo ce ne sono due con lo stesso nome
 * (uno per jar), quindi il file si indica esplicitamente ({@code spring.config.location}) e si
 * controlla dal nome dell'applicazione che sia quello giusto. Da riga di comando arrivano solo
 * indirizzo e credenziali del database e la porta HTTP 0 (scelta dal sistema). L'avvio reale delle
 * immagini con Compose e' compito di {@code ./smoke.sh}.
 */
class AccountMigrazioneTest {

    static final String SCRIPT = "V1__account.sql";

    @Test
    void migrazioneApplicataDueVolteNonCambiaNullaENonFallisce() throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            PostgresDiProva.migraDaVuoto(postgres);
            List<String> prima = istantanea(postgres);
            MigrateResult seconda = PostgresDiProva.flyway(postgres).migrate();
            assertTrue(seconda.success, "seconda migrazione non riuscita");
            assertEquals(0, seconda.migrationsExecuted, "migrazioni eseguite la seconda volta");
            assertEquals(prima, istantanea(postgres), "schema e storico cambiati dalla seconda migrazione");
            System.out.println("[migrazione] seconda applicazione: 0 migrazioni, schema e storico invariati");
        }
    }

    /** Cartella temporanea del caso (campo e non parametro: il nome del caso nel rapporto resta senza firma). */
    @TempDir
    Path cartella;

    @Test
    void migrazioneModificataDopoLApplicazioneFaFallireLAvvio() throws Exception {
        String originale = scriptOriginale();
        Path identica = Files.createDirectory(cartella.resolve("identica"));
        Files.writeString(identica.resolve(SCRIPT), originale, StandardCharsets.UTF_8);
        Path modificata = Files.createDirectory(cartella.resolve("modificata"));
        Files.writeString(modificata.resolve(SCRIPT), originale + "-- modifica dopo l'applicazione\n",
                StandardCharsets.UTF_8);

        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            avvia(OnlineApplication.class, "carddemo-online", postgres).close();
            List<String> storico = storico(postgres);
            assertEquals(1, storico.size(), "storico dopo il primo avvio: " + storico);

            for (Class<?> app : List.of(OnlineApplication.class, BatchApplication.class)) {
                String nome = app == OnlineApplication.class ? "carddemo-online" : "carddemo-batch";
                // Controprova: la stessa migrazione, identica, letta da una cartella: l'avvio riesce.
                avvia(app, nome, postgres, "--spring.flyway.locations=filesystem:" + identica).close();
                // Migrazione modificata: Flyway rifiuta la somma di controllo e l'avvio fallisce.
                Throwable errore = assertThrows(Throwable.class,
                        () -> avvia(app, nome, postgres, "--spring.flyway.locations=filesystem:" + modificata).close(),
                        nome + " si e' avviato con una migrazione applicata e poi modificata");
                String catena = catena(errore);
                assertTrue(catena.contains("FlywayValidateException") && catena.contains("checksum mismatch"),
                        nome + ": avvio fallito per un motivo diverso dalla validazione di Flyway: " + catena);
                System.out.println("[migrazione] " + nome + " con migrazione modificata: avvio fallito ("
                        + primaRiga(catena) + ")");
                assertEquals(storico, storico(postgres), "storico cambiato dall'avvio fallito di " + nome);
            }
        }
    }

    @Test
    void primoAvvioERiavvioBatchPoiOnlineSuDatabaseVuoto() throws Exception {
        sequenza(List.of("batch", "online", "batch", "online"));
    }

    @Test
    void primoAvvioERiavvioOnlinePoiBatchSuDatabaseVuoto() throws Exception {
        sequenza(List.of("online", "batch", "online", "batch"));
    }

    /** Avvia e chiude le applicazioni nell'ordine dato, su un database vuoto, controllando lo stato dopo ognuna. */
    private static void sequenza(List<String> ordine) throws Exception {
        try (PostgreSQLContainer postgres = PostgresDiProva.avvia()) {
            try (Connection c = PostgresDiProva.connessione(postgres)) {
                assertEquals(List.of("0"), PostgresDiProva.righe(c, "select count(*) from pg_class c join pg_namespace n"
                        + " on n.oid = c.relnamespace where n.nspname = 'public'"), "database non vuoto all'inizio");
            }
            int lanciBatch = 0;
            List<String> storicoIniziale = null;
            for (String app : ordine) {
                if ("batch".equals(app)) {
                    avvia(BatchApplication.class, "carddemo-batch", postgres).close();
                    lanciBatch++;
                } else {
                    avvia(OnlineApplication.class, "carddemo-online", postgres).close();
                }
                List<String> storico = storico(postgres);
                assertEquals(1, storico.size(), "storico di Flyway dopo " + app + ": " + storico);
                assertTrue(storico.get(0).startsWith("1|1|account|SQL|" + SCRIPT + "|") && storico.get(0).endsWith("|t"),
                        "riga dello storico dopo " + app + ": " + storico.get(0));
                if (storicoIniziale == null) {
                    storicoIniziale = storico;
                }
                assertEquals(storicoIniziale, storico, "storico cambiato dal riavvio di " + app);
                try (Connection c = PostgresDiProva.connessione(postgres)) {
                    // Tipo dal catalogo (relkind 'r' = tabella), non la sola risoluzione del nome.
                    assertEquals("r", tipoDiRelazione(c, "account"), "account dopo " + app);
                    assertEquals(List.of("12"), PostgresDiProva.righe(c, "select count(*) from information_schema.columns"
                            + " where table_schema = 'public' and table_name = 'account'"), "colonne di account dopo " + app);
                    assertEquals(lanciBatch > 0 ? "r" : "<assente>", tipoDiRelazione(c, "batch_job_execution"),
                            "tabelle di Spring Batch dopo " + app + " (lanci batch: " + lanciBatch + ")");
                    if (lanciBatch > 0) {
                        assertEquals(List.of(lanciBatch + "|" + lanciBatch), PostgresDiProva.righe(c,
                                "select count(*), count(*) filter (where status = 'COMPLETED' and exit_code = 'COMPLETED')"
                                        + " from batch_job_execution"), "esecuzioni del job dopo " + app);
                    }
                }
                System.out.println("[migrazione] " + ordine + ": dopo " + app + " storico " + storico
                        + ", lanci batch " + lanciBatch);
            }
        }
    }

    /** relkind di una relazione dello schema public ('r' tabella, 'v' vista, ...), {@code <assente>} se non c'e'. */
    static String tipoDiRelazione(Connection c, String nome) throws Exception {
        List<String> r = PostgresDiProva.righe(c, "select c.relkind from pg_class c join pg_namespace n"
                + " on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = '" + nome + "'");
        return r.isEmpty() ? "<assente>" : String.join(",", r);
    }

    /** Avvia un'applicazione con il suo application.properties sul database del container. */
    static ConfigurableApplicationContext avvia(Class<?> app, String nome, PostgreSQLContainer postgres, String... altri)
            throws Exception {
        List<String> argomenti = new ArrayList<>(List.of(
                "--spring.config.location=" + proprietaDellApplicazione(app),
                "--spring.datasource.url=" + postgres.getJdbcUrl(),
                "--spring.datasource.username=" + postgres.getUsername(),
                "--spring.datasource.password=" + postgres.getPassword(),
                "--server.port=0"));
        argomenti.addAll(List.of(altri));
        ConfigurableApplicationContext contesto = new SpringApplicationBuilder(app).run(argomenti.toArray(String[]::new));
        try {
            assertEquals(nome, contesto.getEnvironment().getProperty("spring.application.name"),
                    "application.properties caricato per " + app.getSimpleName());
        } catch (AssertionError e) {
            contesto.close();
            throw e;
        }
        return contesto;
    }

    /** application.properties dello stesso jar (o cartella di classi) della classe principale. */
    static String proprietaDellApplicazione(Class<?> app) throws Exception {
        URL sorgente = app.getProtectionDomain().getCodeSource().getLocation();
        String base = sorgente.toURI().toString();
        String percorso = base.endsWith(".jar") ? "jar:" + base + "!/application.properties"
                : base + (base.endsWith("/") ? "" : "/") + "application.properties";
        try (InputStream in = URI.create(percorso).toURL().openStream()) {
            assertNotNull(in, "application.properties non leggibile: " + percorso);
        }
        return percorso;
    }

    /** Testo della migrazione V1 dal classpath (jar di carddemo-domain). */
    static String scriptOriginale() throws Exception {
        try (InputStream in = AccountMigrazioneTest.class.getClassLoader().getResourceAsStream("db/migration/" + SCRIPT)) {
            assertNotNull(in, "db/migration/" + SCRIPT + " assente dal classpath");
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /** Storico di Flyway: rango | versione | descrizione | tipo | script | somma di controllo | riuscita. */
    static List<String> storico(PostgreSQLContainer postgres) throws Exception {
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            return PostgresDiProva.righe(c, "select installed_rank, version, description, type, script, checksum, success"
                    + " from flyway_schema_history order by installed_rank");
        }
    }

    /** Colonne, vincoli, indici e oggetti dello schema public, e storico di Flyway. */
    static List<String> istantanea(PostgreSQLContainer postgres) throws Exception {
        List<String> out = new ArrayList<>();
        try (Connection c = PostgresDiProva.connessione(postgres)) {
            out.addAll(PostgresDiProva.righe(c, "select table_name, ordinal_position, column_name, data_type,"
                    + " character_maximum_length, numeric_precision, numeric_scale, is_nullable, column_default"
                    + " from information_schema.columns where table_schema = 'public' order by table_name, ordinal_position"));
            out.addAll(PostgresDiProva.righe(c, "select conrelid::regclass, conname, pg_get_constraintdef(oid)"
                    + " from pg_constraint where connamespace = 'public'::regnamespace order by 1, 2"));
            out.addAll(PostgresDiProva.righe(c, "select indexname, indexdef from pg_indexes where schemaname = 'public'"
                    + " order by indexname"));
            out.addAll(PostgresDiProva.righe(c, "select c.relname, c.relkind from pg_class c join pg_namespace n"
                    + " on n.oid = c.relnamespace where n.nspname = 'public' order by c.relname"));
        }
        out.addAll(storico(postgres));
        return out;
    }

    static String catena(Throwable t) {
        StringBuilder s = new StringBuilder();
        for (Throwable x = t; x != null; x = x.getCause()) {
            s.append(x.getClass().getName()).append(": ").append(x.getMessage()).append('\n');
        }
        return s.toString();
    }

    static String primaRiga(String testo) {
        for (String riga : testo.split("\n")) {
            if (riga.contains("FlywayValidateException")) {
                return riga.length() > 200 ? riga.substring(0, 200) + "..." : riga;
            }
        }
        return testo;
    }
}
