package io.github.ltoscano.carddemo.batch.readacct;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/**
 * Il contratto esterno del processo (rilievo 3 della validazione 1 della PR #70): ogni riga della tabella degli
 * errori, e la corsa regolare, attraverso l'applicazione batch vera in un processo proprio ({@link AvvioConGuasti}):
 * codice di uscita del processo (99 dedicato a ogni fine anomala del programma, 0 a fine regolare), standard output
 * byte per byte (solo le righe dei DISPLAY, nient'altro), nessuno dei tre file rimasto, partendo da tre file
 * sentinella, che all'apertura dei conti devono essere gia' assenti (PREDEL). Nessun database: sorgente dei conti
 * finta e guasti sui file di {@link Prove}, come in {@link Cbact01cTest}.
 */
class ReadacctProcessoTest {

    /** Limite di un avvio; allo scadere il processo e i suoi discendenti si terminano e il caso fallisce. */
    static final long LIMITE_SECONDI = 120;

    @TempDir
    Path tmp;

    record Esito(int uscita, byte[] stdout, String stderr) {
    }

    private List<Path> uscite() {
        return List.of(tmp.resolve("OUTFILE"), tmp.resolve("ARRYFILE"), tmp.resolve("VBRCFILE"));
    }

    private Esito avvia(GuastoDiProva guasto) throws Exception {
        for (Path p : uscite()) {
            Files.write(p, "SENTINELLA DI UNA CORSA PRECEDENTE".getBytes(StandardCharsets.US_ASCII));
        }
        Path out = tmp.resolve("stdout.bin");
        Path err = tmp.resolve("stderr.txt");
        List<String> comando = new ArrayList<>(List.of(Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-cp", System.getProperty("java.class.path"), AvvioConGuasti.class.getName(), guasto.name(),
                "--spring.batch.job.name=READACCT", "OUTFILE=" + uscite().get(0), "ARRYFILE=" + uscite().get(1),
                "VBRCFILE=" + uscite().get(2)));
        Process p = new ProcessBuilder(comando).redirectOutput(out.toFile()).redirectError(err.toFile())
                .redirectInput(ProcessBuilder.Redirect.from(new File("/dev/null"))).start();
        if (!p.waitFor(LIMITE_SECONDI, TimeUnit.SECONDS)) {
            p.descendants().forEach(ProcessHandle::destroyForcibly);
            p.destroyForcibly();
            p.waitFor(20, TimeUnit.SECONDS);
            throw new AssertionError("il processo non e' terminato entro " + LIMITE_SECONDI + " s: " + comando);
        }
        return new Esito(p.exitValue(), Files.readAllBytes(out), Files.readString(err, StandardCharsets.ISO_8859_1));
    }

    /** Righe di console attese (senza LF) per il guasto, con i due conti dell'applicazione di prova. */
    static List<String> consoleAttesa(GuastoDiProva guasto) {
        List<String> primo = Cbact01cTest.righeE1("00000000001", "00000000000{");
        List<String> secondo = Cbact01cTest.righeE1("00000000002", "00000000000{");
        List<String> r = new ArrayList<>();
        r.add(Cbact01c.START);
        switch (guasto) {
            case NESSUNO, CHIUSURA_OUTFILE, CHIUSURA_ARRYFILE, CHIUSURA_VBRCFILE -> {
                r.addAll(primo);
                r.addAll(secondo);
                r.add(Cbact01c.END);
            }
            case APERTURA_CONTI -> fine(r, "ERROR OPENING ACCTFILE");
            case LETTURA_PRIMO_CONTO -> fine(r, "ERROR READING ACCOUNT FILE");
            case LETTURA_A_META -> {
                r.addAll(primo);
                fine(r, "ERROR READING ACCOUNT FILE");
            }
            case CREAZIONE_OUTFILE -> fine(r, "ERROR OPENING OUTFILE");
            case CREAZIONE_ARRYFILE -> fine(r, "ERROR OPENING ARRAYFILE");
            case CREAZIONE_VBRCFILE -> fine(r, "ERROR OPENING VBRC FILE");
            case SCRITTURA_OUTFILE -> {
                r.addAll(primo);
                r.addAll(secondo.subList(0, 12));
                fine(r, "ACCOUNT FILE WRITE STATUS IS:");
            }
            case SCRITTURA_ARRYFILE -> {
                r.addAll(primo.subList(0, 12));
                fine(r, "ACCOUNT FILE WRITE STATUS IS:");
            }
            case SCRITTURA_PRIMO_RECORD_VARIABILE, SCRITTURA_SECONDO_RECORD_VARIABILE -> {
                r.addAll(primo.subList(0, 14));
                fine(r, "ACCOUNT FILE WRITE STATUS IS:");
            }
            case CHIUSURA_CONTI -> {
                r.addAll(primo);
                r.addAll(secondo);
                fine(r, "ERROR CLOSING ACCOUNT FILE");
            }
            default -> throw new IllegalStateException(guasto.name());
        }
        return r;
    }

    private static void fine(List<String> r, String messaggio) {
        r.add(messaggio);
        r.add("ABENDING PROGRAM");
    }

    private static byte[] byteDelleRighe(List<String> righe) {
        StringBuilder s = new StringBuilder();
        for (String riga : righe) {
            s.append(riga).append('\n');
        }
        return s.toString().getBytes(StandardCharsets.ISO_8859_1);
    }

    @ParameterizedTest
    @EnumSource(value = GuastoDiProva.class, names = {"NESSUNO", "ERRORE_GRAVE_APERTURA"}, mode = EnumSource.Mode.EXCLUDE)
    void ogniRigaDellaTabellaDegliErroriNelProcessoVero(GuastoDiProva guasto) throws Exception {
        Esito e = avvia(guasto);
        assertEquals(EsitoReadacct.USCITA_FINE_ANOMALA, e.uscita(), "codice di uscita del processo; stderr: " + e.stderr());
        assertEquals(Prove.latin1(byteDelleRighe(consoleAttesa(guasto))), Prove.latin1(e.stdout()),
                "standard output del processo, byte per byte");
        for (Path p : uscite()) {
            assertFalse(Files.exists(p), p.getFileName() + " rimasto dopo la fine anomala");
        }
        assertFalse(e.stderr().contains(AvvioConGuasti.SENTINELLA), "PREDEL dopo l'apertura dei conti");
        assertTrue(e.stderr().contains("CBACT01C: fine anomala nella fase"), "dettaglio dell'errore sullo standard error");
    }

    /**
     * Un guasto che il programma non intercetta (un {@link Error}, non un'eccezione) non e' una fine anomala del
     * programma: il processo deve comunque uscire con un codice diverso da 0, quello di Spring Batch per un job
     * fallito (stato {@code FAILED}, 5), e non con 0. Prima della correzione del giro 1 il generatore di codice
     * di Spring Boot spariva ({@code @ConditionalOnMissingBean(ExitCodeGenerator.class)}) e il processo usciva con 0.
     */
    @Test
    void unGuastoNonIntercettatoNonEsceConZero() throws Exception {
        Esito e = avvia(GuastoDiProva.ERRORE_GRAVE_APERTURA);
        assertEquals(5, e.uscita(), "codice di uscita del processo; stderr: " + e.stderr());
        assertEquals(Prove.latin1(byteDelleRighe(List.of(Cbact01c.START))), Prove.latin1(e.stdout()),
                "standard output del processo: solo la riga di inizio, nessuna riga della tabella degli errori");
        for (Path p : uscite()) {
            assertFalse(Files.exists(p), p.getFileName() + " rimasto dopo l'errore");
        }
    }

    @Test
    void corsaRegolareNelProcessoVero() throws Exception {
        Esito e = avvia(GuastoDiProva.NESSUNO);
        assertEquals(0, e.uscita(), "codice di uscita del processo; stderr: " + e.stderr());
        assertEquals(Prove.latin1(byteDelleRighe(consoleAttesa(GuastoDiProva.NESSUNO))), Prove.latin1(e.stdout()),
                "standard output del processo, byte per byte");
        assertEquals(Prove.outE1(1, Prove.DEBITO_2525) + Prove.outE1(2, Prove.DEBITO_2525),
                Prove.HEX.formatHex(Files.readAllBytes(uscite().get(0))), "OUTFILE");
        assertEquals(Prove.arrE1(1) + Prove.arrE1(2), Prove.HEX.formatHex(Files.readAllBytes(uscite().get(1))), "ARRYFILE");
        assertEquals(Prove.vbrcE1(1) + Prove.vbrcE1(2), Prove.HEX.formatHex(Files.readAllBytes(uscite().get(2))),
                "VBRCFILE");
        assertFalse(e.stderr().contains(AvvioConGuasti.SENTINELLA), "PREDEL dopo l'apertura dei conti");
    }
}
