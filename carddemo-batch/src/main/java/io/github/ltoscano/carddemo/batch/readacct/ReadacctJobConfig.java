package io.github.ltoscano.carddemo.batch.readacct;

import java.nio.file.Path;
import java.util.List;
import javax.sql.DataSource;
import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.converter.JobParametersConverter;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.job.parameters.InvalidJobParametersException;
import org.springframework.batch.core.job.parameters.JobParameters;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.Step;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.infrastructure.repeat.RepeatStatus;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.batch.autoconfigure.JobExecutionExitCodeGenerator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Job {@code READACCT} ({@code app/jcl/READACCT.jcl}): un solo passo, che esegue {@link Cbact01c}. Contratto
 * dell'avvio in {@code docs/contratti.md} ("Contratto del job READACCT"):
 * {@code --spring.batch.job.name=READACCT OUTFILE=<percorso> ARRYFILE=<percorso> VBRCFILE=<percorso>}, con i
 * nomi DD del JCL come parametri del job, obbligatori.
 *
 * <p>Riesecuzione: {@link ParametriDiAvvio} da' a ogni avvio un'istanza nuova del job nel repository di
 * Spring Batch, e il passo comincia cancellando le uscite ({@code PREDEL}): due avvii con lo stesso comando
 * riescono entrambi e il secondo sostituisce per intero i file. Nessun incrementatore sul job: in Spring
 * Batch 6.1 farebbe scartare i parametri passati.
 */
@Configuration
public class ReadacctJobConfig {

    /** Nome del job: il nome del JCL. */
    public static final String NOME_JOB = "READACCT";

    /** Nome del passo: il passo del JCL che esegue il programma. */
    public static final String NOME_PASSO = "STEP05";

    static final List<String> PARAMETRI = List.of(Cbact01c.OUTFILE, Cbact01c.ARRYFILE, Cbact01c.VBRCFILE);

    /** {@code ACCTFILE}: la tabella {@code account} della sorgente dati dell'applicazione. */
    @Bean
    SorgenteConti sorgenteContiReadacct(ObjectProvider<DataSource> sorgenteDati) {
        return new SorgenteContiJdbc(sorgenteDati::getObject);
    }

    /** Conversione degli argomenti di avvio usata dal selettore dei job di Spring Boot (vedi {@link ParametriDiAvvio}). */
    @Bean
    JobParametersConverter parametriDiAvvio() {
        return new ParametriDiAvvio();
    }

    @Bean
    ApertureUscite apertureUsciteReadacct() {
        return new ApertureUsciteSuDisco();
    }

    @Bean
    UscitaConsole uscitaConsoleReadacct() {
        return UscitaConsole.standardOutput();
    }

    @Bean
    EsitoReadacct esitoReadacct() {
        return new EsitoReadacct();
    }

    /**
     * Il generatore di codice di uscita di Spring Boot per i job (stato {@code FAILED} → 5), dichiarato qui
     * perche' Spring Boot lo crea solo se non c'e' alcun {@code ExitCodeGenerator}
     * ({@code @ConditionalOnMissingBean(ExitCodeGenerator.class)} in {@code BatchJobLauncherAutoConfiguration}):
     * con {@link EsitoReadacct} da solo, un job fallito per un guasto diverso da {@link FineAnomala} (per esempio
     * un {@code Error}, o un fallimento di {@code installationCheckJob}) farebbe uscire il processo con 0.
     * {@link EsitoReadacct} lo precede: per la fine anomala del programma vale 99.
     */
    @Bean
    JobExecutionExitCodeGenerator codiceDiUscitaDeiJob() {
        return new JobExecutionExitCodeGenerator();
    }

    @Bean
    Step readacctStep(JobRepository jobRepository, SorgenteConti sorgenteConti, ApertureUscite apertureUscite,
            UscitaConsole uscitaConsole) {
        return new StepBuilder(NOME_PASSO, jobRepository)
                .tasklet((contribution, chunkContext) -> {
                    JobParameters parametri = contribution.getStepExecution().getJobParameters();
                    new Cbact01c(sorgenteConti, apertureUscite, percorso(parametri, Cbact01c.OUTFILE),
                            percorso(parametri, Cbact01c.ARRYFILE), percorso(parametri, Cbact01c.VBRCFILE),
                            uscitaConsole.flusso()).esegui();
                    return RepeatStatus.FINISHED;
                })
                .build();
    }

    @Bean
    Job readacctJob(JobRepository jobRepository, Step readacctStep) {
        return new JobBuilder(NOME_JOB, jobRepository)
                .validator(ReadacctJobConfig::verificaParametri)
                .start(readacctStep)
                .build();
    }

    /**
     * I tre parametri sono obbligatori e non vuoti: senza, il job non parte (errore di avvio, come un DD
     * mancante nel JCL), prima di qualunque effetto del programma.
     */
    static void verificaParametri(JobParameters parametri) throws InvalidJobParametersException {
        for (String dd : PARAMETRI) {
            String valore = parametri.getString(dd);
            if (valore == null || valore.isEmpty()) {
                throw new InvalidJobParametersException("parametro del job " + dd + " assente o vuoto: il job "
                        + NOME_JOB + " si avvia con OUTFILE=<percorso> ARRYFILE=<percorso> VBRCFILE=<percorso>");
            }
        }
    }

    private static Path percorso(JobParameters parametri, String dd) {
        String valore = parametri.getString(dd);
        if (valore == null || valore.isEmpty()) {
            throw new IllegalStateException("parametro del job " + dd + " assente");
        }
        return Path.of(valore);
    }
}
