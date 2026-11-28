package io.github.ltoscano.carddemo.parity;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * Avvio del job READACCT in un processo proprio (issue #65, contratto in {@code docs/contratti.md}).
 *
 * <p>Il processo e' lanciato con il java della JVM dei test; standard output e standard error vanno
 * su due file (nessun blocco per buffer pieni) e si leggono per intero dopo la fine del processo.
 * L'attesa ha un limite di tempo: allo scadere, o se il test viene interrotto, si termina l'intero
 * albero del processo (discendenti compresi), con attese limitate, e si verifica che nessuno sopravviva.
 */
final class AvvioJob {

    /** Codice del motivo dichiarato del fallimento atteso dei casi di parita' di READACCT. */
    static final String JOB_ASSENTE = "job-readacct-assente";

    /*
     * Diagnostica nativa di Spring Boot 4.2.0 per uno spring.batch.job.name che non corrisponde ad
     * alcun job, letta dall'applicazione del 28 nov 2026 (codice di uscita 1): il bean
     * jobLauncherApplicationRunner non si crea perche' JobLauncherApplicationRunner.afterPropertiesSet
     * chiama Assert.state, che solleva l'IllegalStateException. La traccia, sullo standard output, e':
     *   org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'jobLauncherApplicationRunner' ...
     *   ...
     *   Caused by: java.lang.IllegalStateException: No job found with name 'READACCT'
     *   	at org.springframework.util.Assert.state(Assert.java:102) ...
     *   	at org.springframework.boot.batch.autoconfigure.JobLauncherApplicationRunner.afterPropertiesSet(JobLauncherApplicationRunner.java:90) ...
     */
    static final String ECCEZIONE_BEAN =
            "org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'jobLauncherApplicationRunner'";
    static final String CAUSA = "Caused by: java.lang.IllegalStateException: No job found with name 'READACCT'";
    static final String PRIMO_FRAME = "\tat org.springframework.util.Assert.state(";
    static final String SECONDO_FRAME =
            "\tat org.springframework.boot.batch.autoconfigure.JobLauncherApplicationRunner.afterPropertiesSet(";
    static final int USCITA_JOB_ASSENTE = 1;

    /** Righe di Spring Batch che mostrano l'avvio di un job o di un passo: con una di queste il job esiste. */
    static final List<String> TRACCE_DI_AVVIO = List.of("] launched with the following parameters", "Executing step: [");

    /** Limite di tempo predefinito di un avvio; si cambia con la proprieta' di sistema {@value #PROPRIETA_LIMITE}. */
    static final String PROPRIETA_LIMITE = "menb.avvio.limite";
    static final Duration LIMITE_PREDEFINITO = Duration.ofMinutes(4);

    /** Attesa limitata della fine di ogni processo dell'albero dopo la terminazione forzata. */
    static final Duration ATTESA_TERMINAZIONE = Duration.ofSeconds(20);

    /** Esito di un avvio: codice di uscita, standard output e standard error per intero. */
    record Esito(int uscita, byte[] stdout, byte[] stderr) {

        String testo() {
            return new String(stdout, StandardCharsets.ISO_8859_1) + "\n" + new String(stderr, StandardCharsets.ISO_8859_1);
        }

        String riassunto() {
            String t = testo();
            return "codice di uscita " + uscita + "; uscita (ultimi 3000 caratteri): "
                    + t.substring(Math.max(0, t.length() - 3000));
        }
    }

    private AvvioJob() {
    }

    /** Limite di un avvio: {@value #PROPRIETA_LIMITE} (durata ISO-8601, per esempio PT4M) o {@link #LIMITE_PREDEFINITO}. */
    static Duration limite() {
        String valore = System.getProperty(PROPRIETA_LIMITE);
        return valore == null || valore.isEmpty() ? LIMITE_PREDEFINITO : Duration.parse(valore);
    }

    /** Jar eseguibile di carddemo-batch di questa build (proprieta' {@code menb.batch.jar} del POM). */
    static Path jarBatch() {
        String valore = System.getProperty("menb.batch.jar");
        assertTrue(valore != null && !valore.isEmpty(), "proprieta' menb.batch.jar assente");
        Path jar = Path.of(valore);
        assertTrue(Files.isRegularFile(jar), "jar eseguibile di carddemo-batch assente: " + jar);
        return jar;
    }

    /** Prefisso del comando: java -jar &lt;jar di carddemo-batch&gt;. */
    static List<String> comandoJar() {
        return List.of(java(), "-jar", jarBatch().toString());
    }

    /** Prefisso del comando per un'applicazione di prova dei test: java -cp &lt;classpath dei test&gt; &lt;classe&gt;. */
    static List<String> comandoClasse(Class<?> principale) {
        return List.of(java(), "-cp", System.getProperty("java.class.path"), principale.getName());
    }

    private static String java() {
        return Path.of(System.getProperty("java.home"), "bin", "java").toString();
    }

    /** Argomenti del contratto, e nessun altro. */
    static List<String> argomenti(Path cartella) {
        return List.of("--spring.batch.job.name=READACCT", "OUTFILE=" + cartella.resolve("OUTFILE"),
                "ARRYFILE=" + cartella.resolve("ARRYFILE"), "VBRCFILE=" + cartella.resolve("VBRCFILE"));
    }

    /** Ambiente della connessione: proprieta' standard di Spring come variabili d'ambiente. */
    static Map<String, String> ambiente(String url, String utente, String password) {
        return Map.of("SPRING_DATASOURCE_URL", url, "SPRING_DATASOURCE_USERNAME", utente,
                "SPRING_DATASOURCE_PASSWORD", password);
    }

    /** Lancia il processo e ne attende la fine entro {@code limite}; i log vanno in {@code log}. */
    static Esito avvia(List<String> prefisso, List<String> argomenti, Map<String, String> ambiente, Path log,
            Duration limite) throws IOException, InterruptedException {
        List<String> comando = new ArrayList<>(prefisso);
        comando.addAll(argomenti);
        Files.createDirectories(log);
        Path out = Files.createTempFile(log, "stdout-", ".txt");
        Path err = Files.createTempFile(log, "stderr-", ".txt");
        ProcessBuilder pb = new ProcessBuilder(comando).redirectOutput(out.toFile()).redirectError(err.toFile())
                .redirectInput(ProcessBuilder.Redirect.from(new java.io.File("/dev/null")));
        pb.environment().putAll(ambiente);
        Process p = pb.start();
        boolean terminato;
        try {
            terminato = p.waitFor(limite.toMillis(), TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            terminaAlbero(p.toHandle());
            throw e;
        }
        if (!terminato) {
            List<Long> sopravvissuti = terminaAlbero(p.toHandle());
            throw new AssertionError("AVVIO-LIMITE-DI-TEMPO: il processo non e' terminato entro " + limite + "; "
                    + (sopravvissuti.isEmpty() ? "albero terminato, nessun processo sopravvissuto"
                            : "processi ancora vivi dopo la terminazione: " + sopravvissuti)
                    + "; comando: " + comando);
        }
        return new Esito(p.exitValue(), Files.readAllBytes(out), Files.readAllBytes(err));
    }

    /**
     * Termina forzatamente il processo e tutti i suoi discendenti (elenco preso prima di terminare,
     * perche' un figlio orfano non risulta piu' discendente), attende la fine di ciascuno per al piu'
     * {@link #ATTESA_TERMINAZIONE} e restituisce i pid di quelli ancora vivi.
     */
    static List<Long> terminaAlbero(ProcessHandle radice) throws InterruptedException {
        // dalle foglie alla radice: ogni processo e' terminato mentre il suo genitore e' ancora vivo e
        // puo' raccoglierlo; un orfano terminato dopo la morte del genitore resterebbe zombie
        List<ProcessHandle> albero = new ArrayList<>(radice.descendants().toList());
        albero.sort((a, b) -> Integer.compare(profondita(b, radice), profondita(a, radice)));
        albero.add(radice);
        long scadenza = System.nanoTime() + ATTESA_TERMINAZIONE.toNanos();
        List<Long> vivi = new ArrayList<>();
        for (ProcessHandle h : albero) {
            h.destroyForcibly();
            long resto = Math.max(0, scadenza - System.nanoTime());
            try {
                h.onExit().get(resto, TimeUnit.NANOSECONDS);
            } catch (java.util.concurrent.TimeoutException | java.util.concurrent.ExecutionException e) {
                // verificato sotto con isAlive
            }
        }
        for (ProcessHandle h : albero) {
            if (h.isAlive()) {
                vivi.add(h.pid());
            }
        }
        return vivi;
    }

    private static int profondita(ProcessHandle h, ProcessHandle radice) {
        int d = 0;
        for (ProcessHandle p = h; p.pid() != radice.pid() && d < 1000; d++) {
            java.util.Optional<ProcessHandle> genitore = p.parent();
            if (genitore.isEmpty()) {
                break;
            }
            p = genitore.get();
        }
        return d;
    }

    /**
     * Vero se e solo se l'esito e' la diagnostica nativa del selettore di Spring Boot per il job
     * READACCT inesistente: codice di uscita 1; in uno stesso flusso (stdout o stderr) la riga
     * {@link #ECCEZIONE_BEAN} e, esattamente una volta, la riga {@link #CAUSA} seguita subito da
     * {@link #PRIMO_FRAME} e {@link #SECONDO_FRAME}; in nessuno dei due flussi una traccia di avvio di
     * un job o di un passo ({@link #TRACCE_DI_AVVIO}); e, indipendentemente dai log dell'applicazione,
     * nessun job registrato nel repository JDBC di Spring Batch ({@link #nessunJobRegistrato}). Ogni
     * altro errore, prima o dopo la selezione, no.
     */
    static boolean jobAssente(Esito esito, Map<String, String> ambiente) {
        return tracciaNativa(esito) && nessunJobRegistrato(ambiente);
    }

    /**
     * Evidenza indipendente dai log dell'applicazione sotto prova: il repository JDBC di Spring Batch
     * dell'applicazione (tabelle {@code batch_job_instance} e {@code batch_job_execution}, create
     * all'avvio da {@code spring.batch.jdbc.initialize-schema=always}) esiste e non registra alcuna
     * istanza ne' esecuzione di job. Un job avviato vi lascia almeno un'istanza e un'esecuzione prima
     * di entrare nel primo passo. Database irraggiungibile o tabelle assenti: non e' il job assente.
     */
    static boolean nessunJobRegistrato(Map<String, String> ambiente) {
        try (java.sql.Connection c = java.sql.DriverManager.getConnection(ambiente.get("SPRING_DATASOURCE_URL"),
                ambiente.get("SPRING_DATASOURCE_USERNAME"), ambiente.get("SPRING_DATASOURCE_PASSWORD"));
                java.sql.Statement st = c.createStatement();
                java.sql.ResultSet rs = st.executeQuery(CONTEGGIO_JOB)) {
            return rs.next() && rs.getLong(1) == 0 && rs.getLong(2) == 0;
        } catch (java.sql.SQLException e) {
            return false;
        }
    }

    static final String CONTEGGIO_JOB =
            "select (select count(*) from batch_job_instance), (select count(*) from batch_job_execution)";

    /** Condizioni sull'uscita del processo (vedi {@link #jobAssente}): codice, traccia nativa, nessuna traccia di avvio. */
    static boolean tracciaNativa(Esito esito) {
        if (esito.uscita() != USCITA_JOB_ASSENTE) {
            return false;
        }
        String testo = esito.testo();
        for (String traccia : TRACCE_DI_AVVIO) {
            if (testo.contains(traccia)) {
                return false;
            }
        }
        int blocchi = 0;
        for (byte[] flusso : List.of(esito.stdout(), esito.stderr())) {
            String[] righe = new String(flusso, StandardCharsets.ISO_8859_1).split("\r?\n", -1);
            boolean bean = false;
            int qui = 0;
            for (int i = 0; i < righe.length; i++) {
                if (righe[i].startsWith(ECCEZIONE_BEAN)) {
                    bean = true;
                }
                if (righe[i].equals(CAUSA)) {
                    if (i + 2 >= righe.length || !righe[i + 1].startsWith(PRIMO_FRAME)
                            || !righe[i + 2].startsWith(SECONDO_FRAME)) {
                        return false;
                    }
                    qui++;
                }
            }
            if (qui > 0 && !bean) {
                return false;
            }
            blocchi += qui;
        }
        return blocchi == 1;
    }

    /** Lancia {@link MotivoDichiarato} se il job READACCT non esiste; altrimenti non fa nulla. */
    static void verificaJobPresente(Esito esito, Map<String, String> ambiente) {
        if (jobAssente(esito, ambiente)) {
            throw new MotivoDichiarato(JOB_ASSENTE, "l'applicazione non trova un job di nome READACCT ("
                    + "diagnostica del selettore di Spring Boot: " + CAUSA.substring("Caused by: ".length())
                    + " da JobLauncherApplicationRunner.afterPropertiesSet, codice di uscita " + esito.uscita() + ")");
        }
    }
}
