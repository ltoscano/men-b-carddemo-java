package io.github.ltoscano.carddemo.batch;

import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.job.parameters.RunIdIncrementer;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.Step;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.infrastructure.repeat.RepeatStatus;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Job di verifica dell'installazione: un solo passo che non fa nulla e termina.
 * Dimostra che il runner batch esegue davvero un job e ne registra l'esito
 * nell'archivio dei metadati. Nessuna logica, nessun accesso a tabelle.
 * Il {@link RunIdIncrementer} assegna a ogni lancio un parametro {@code run.id}
 * diverso, quindi ogni lancio crea una nuova istanza del job.
 */
@Configuration
public class InstallationCheckJobConfig {

    @Bean
    Step installationCheckStep(JobRepository jobRepository) {
        return new StepBuilder("installationCheckStep", jobRepository)
                .tasklet((contribution, chunkContext) -> RepeatStatus.FINISHED)
                .build();
    }

    @Bean
    Job installationCheckJob(JobRepository jobRepository, Step installationCheckStep) {
        return new JobBuilder("installationCheckJob", jobRepository)
                .incrementer(new RunIdIncrementer())
                .start(installationCheckStep)
                .build();
    }
}
