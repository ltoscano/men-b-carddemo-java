package io.github.ltoscano.carddemo.batch.readacct;

import static io.github.ltoscano.carddemo.batch.readacct.Prove.esempio1;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.ltoscano.carddemo.batch.BatchApplication;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.job.parameters.InvalidJobParametersException;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.support.GenericApplicationContext;

/**
 * Il job {@code READACCT} nell'applicazione vera ({@link BatchApplication}, selettore dei job di Spring Boot,
 * repository di Spring Batch senza persistenza del profilo {@code test}): nome del job, parametri, codice di
 * uscita calcolato da {@code SpringApplication.exit} come nel {@code main}. Al posto della tabella dei conti e
 * dello standard output, una sorgente finta e una console in memoria (bean primari registrati prima
 * dell'avvio): nessun database in questo modulo, che si costruisce anche dentro la build dell'immagine.
 */
class ReadacctJobTest {

    @TempDir
    Path tmp;

    private final Prove.Registro registro = new Prove.Registro();
    private final Prove.Console console = new Prove.Console(registro);

    private ConfigurableApplicationContext avvia(Prove.Conti conti, String... argomenti) {
        ApplicationContextInitializer<GenericApplicationContext> sostituti = contesto -> {
            contesto.registerBean("sorgenteContiDiProva", SorgenteConti.class, () -> conti, d -> d.setPrimary(true));
            contesto.registerBean("uscitaConsoleDiProva", UscitaConsole.class, () -> UscitaConsole.su(console),
                    d -> d.setPrimary(true));
        };
        return new SpringApplicationBuilder(BatchApplication.class).profiles("test").initializers(sostituti)
                .run(argomenti);
    }

    private String[] argomenti() {
        return new String[] {"--spring.batch.job.name=READACCT", "OUTFILE=" + tmp.resolve("OUTFILE"),
            "ARRYFILE=" + tmp.resolve("ARRYFILE"), "VBRCFILE=" + tmp.resolve("VBRCFILE")};
    }

    @Test
    void ilJobSiChiamaReadacctERiesceConCodiceZero() throws Exception {
        try (ConfigurableApplicationContext contesto = avvia(new Prove.Conti(List.of(esempio1())), argomenti())) {
            assertEquals(List.of("READACCT"), contesto.getBeansOfType(Job.class).values().stream().map(Job::getName)
                    .filter("READACCT"::equals).toList());
            assertEquals(0, SpringApplication.exit(contesto), "codice di uscita a fine regolare");
        }
        assertArrayEquals(Prove.hex(Cbact01cTest.OUT_E1), Files.readAllBytes(tmp.resolve("OUTFILE")));
        assertArrayEquals(Prove.hex(Cbact01cTest.ARR_E1), Files.readAllBytes(tmp.resolve("ARRYFILE")));
        assertArrayEquals(Prove.hex(Prove.vbrcE1(1)), Files.readAllBytes(tmp.resolve("VBRCFILE")));
        List<String> attese = new java.util.ArrayList<>(List.of(Cbact01c.START));
        attese.addAll(Cbact01cTest.righeE1("00000000001", "00000000000{"));
        attese.add(Cbact01c.END);
        assertEquals(attese, console.righe());
    }

    @Test
    void fineAnomalaDelProgrammaDaCodiceNovantanoveENessunFile() throws Exception {
        for (String p : List.of("OUTFILE", "ARRYFILE", "VBRCFILE")) {
            Files.write(tmp.resolve(p), "SENTINELLA".getBytes(StandardCharsets.US_ASCII));
        }
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        conti.guastoApertura = true;
        try (ConfigurableApplicationContext contesto = avvia(conti, argomenti())) {
            assertEquals(EsitoReadacct.USCITA_FINE_ANOMALA, SpringApplication.exit(contesto),
                    "codice di uscita della fine anomala");
        }
        assertEquals(List.of(Cbact01c.START, "ERROR OPENING ACCTFILE", "ABENDING PROGRAM"), console.righe());
        for (String p : List.of("OUTFILE", "ARRYFILE", "VBRCFILE")) {
            assertFalse(Files.exists(tmp.resolve(p)), p + " rimasto");
        }
    }

    @Test
    void fineAnomalaAMetaLetturaDaCodiceNovantanove() throws Exception {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1(), Prove.conDebito(esempio1(), 2, "0.00")));
        conti.guastoLettura = 2;
        try (ConfigurableApplicationContext contesto = avvia(conti, argomenti())) {
            assertEquals(EsitoReadacct.USCITA_FINE_ANOMALA, SpringApplication.exit(contesto));
        }
        List<String> attese = new java.util.ArrayList<>(List.of(Cbact01c.START));
        attese.addAll(Cbact01cTest.righeE1("00000000001", "00000000000{"));
        attese.addAll(List.of("ERROR READING ACCOUNT FILE", "ABENDING PROGRAM"));
        assertEquals(attese, console.righe());
        for (String p : List.of("OUTFILE", "ARRYFILE", "VBRCFILE")) {
            assertFalse(Files.exists(tmp.resolve(p)), p + " rimasto");
        }
    }

    @Test
    void parametroMancanteEUnErroreDiAvvioNonUnaFineDelProgramma() throws Exception {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        Files.write(tmp.resolve("OUTFILE"), "SENTINELLA".getBytes(StandardCharsets.US_ASCII));
        RuntimeException e = assertThrows(RuntimeException.class, () -> avvia(conti, "--spring.batch.job.name=READACCT",
                "OUTFILE=" + tmp.resolve("OUTFILE"), "ARRYFILE=" + tmp.resolve("ARRYFILE")));
        boolean parametri = false;
        for (Throwable t = e; t != null; t = t.getCause()) {
            parametri |= t instanceof InvalidJobParametersException && t.getMessage().contains("VBRCFILE");
        }
        assertTrue(parametri, "atteso il rifiuto dei parametri del job, trovato: " + e);
        assertEquals(0, conti.aperture, "il programma non doveva partire");
        assertEquals(List.of(), console.righe());
        assertTrue(Files.exists(tmp.resolve("OUTFILE")), "senza job nessun PREDEL");
    }

    @Test
    void ogniAvvioConParametriEUnIstanzaNuovaConGliStessiPercorsi() {
        java.util.Properties argomenti = new java.util.Properties();
        argomenti.setProperty("OUTFILE", "/u/OUTFILE");
        argomenti.setProperty("ARRYFILE", "/u/ARRYFILE");
        argomenti.setProperty("VBRCFILE", "/u/VBRCFILE");
        org.springframework.batch.core.job.parameters.JobParameters primo = new ParametriDiAvvio().getJobParameters(argomenti);
        org.springframework.batch.core.job.parameters.JobParameters secondo = new ParametriDiAvvio().getJobParameters(argomenti);
        for (String dd : List.of("OUTFILE", "ARRYFILE", "VBRCFILE")) {
            assertEquals("/u/" + dd, primo.getString(dd));
            assertEquals("/u/" + dd, secondo.getString(dd));
        }
        assertTrue(primo.getParameter(ParametriDiAvvio.AVVIO).identifying(), "il parametro dell'avvio deve identificare l'istanza");
        assertFalse(primo.getString(ParametriDiAvvio.AVVIO).equals(secondo.getString(ParametriDiAvvio.AVVIO)),
                "due avvii con lo stesso comando devono essere istanze diverse");
        assertTrue(new ParametriDiAvvio().getJobParameters(new java.util.Properties()).isEmpty(),
                "un avvio senza parametri resta senza parametri");
    }

    @Test
    void parametroVuotoRifiutato() {
        Prove.Conti conti = new Prove.Conti(List.of(esempio1()));
        RuntimeException e = assertThrows(RuntimeException.class, () -> avvia(conti, "--spring.batch.job.name=READACCT",
                "OUTFILE=", "ARRYFILE=" + tmp.resolve("ARRYFILE"), "VBRCFILE=" + tmp.resolve("VBRCFILE")));
        boolean parametri = false;
        for (Throwable t = e; t != null; t = t.getCause()) {
            parametri |= t instanceof InvalidJobParametersException && t.getMessage().contains("OUTFILE");
        }
        assertTrue(parametri, "atteso il rifiuto dei parametri del job, trovato: " + e);
        assertEquals(0, conti.aperture);
    }
}
