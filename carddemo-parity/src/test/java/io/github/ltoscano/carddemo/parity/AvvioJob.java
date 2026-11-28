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
 * su due file (nessun blocco per buffer pieni) e si leggono per intero dopo la fine del processo;
 * l'attesa ha un limite di tempo, allo scadere il processo e' terminato e il test fallisce.
 */
final class AvvioJob {

    /** Codice del motivo dichiarato del fallimento atteso dei casi di parita' di READACCT. */
    static final String JOB_ASSENTE = "job-readacct-assente";

    /**
     * Diagnostica nativa di Spring Boot 4.2.0 (BatchJobLauncherAutoConfiguration) per un
     * {@code spring.batch.job.name} che non corrisponde ad alcun job: letta dall'applicazione del
     * 28 nov 2026 (codice di uscita 1, causa {@code IllegalStateException}).
     */
    static final String DIAGNOSTICA_JOB_ASSENTE = "java.lang.IllegalStateException: No job found with name 'READACCT'";
    static final int USCITA_JOB_ASSENTE = 1;

    /** Limite di tempo di un avvio del job. */
    static final Duration LIMITE = Duration.ofMinutes(4);

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
        if (!p.waitFor(limite.toMillis(), TimeUnit.MILLISECONDS)) {
            p.destroyForcibly();
            p.waitFor(30, TimeUnit.SECONDS);
            throw new AssertionError("AVVIO-LIMITE-DI-TEMPO: il job non e' terminato entro " + limite + ": " + comando);
        }
        return new Esito(p.exitValue(), Files.readAllBytes(out), Files.readAllBytes(err));
    }

    /** Vero se e solo se l'esito e' la diagnostica nativa del job READACCT inesistente. */
    static boolean jobAssente(Esito esito) {
        return esito.uscita() == USCITA_JOB_ASSENTE && esito.testo().contains(DIAGNOSTICA_JOB_ASSENTE);
    }

    /** Lancia {@link MotivoDichiarato} se il job READACCT non esiste; altrimenti non fa nulla. */
    static void verificaJobPresente(Esito esito) {
        if (jobAssente(esito)) {
            throw new MotivoDichiarato(JOB_ASSENTE, "l'applicazione non trova un job di nome READACCT ("
                    + DIAGNOSTICA_JOB_ASSENTE + ", codice di uscita " + esito.uscita() + ")");
        }
    }
}
