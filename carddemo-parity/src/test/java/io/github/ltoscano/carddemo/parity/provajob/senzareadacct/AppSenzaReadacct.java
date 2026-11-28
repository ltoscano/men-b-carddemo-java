package io.github.ltoscano.carddemo.parity.provajob.senzareadacct;

import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.Step;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.infrastructure.repeat.RepeatStatus;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * Applicazione di prova dei test (issue #65), non di produzione: un solo job, di nome
 * {@code altroJob}, nessun job READACCT. Serve a provare il riconoscimento del job assente.
 */
@SpringBootApplication
public class AppSenzaReadacct {

    public static void main(String[] args) {
        System.exit(SpringApplication.exit(SpringApplication.run(AppSenzaReadacct.class, args)));
    }

    @Bean
    Step passoVuoto(JobRepository jobRepository) {
        return new StepBuilder("passoVuoto", jobRepository).tasklet((contribution, chunk) -> RepeatStatus.FINISHED).build();
    }

    @Bean
    Job altroJob(JobRepository jobRepository, Step passoVuoto) {
        return new JobBuilder("altroJob", jobRepository).start(passoVuoto).build();
    }
}
