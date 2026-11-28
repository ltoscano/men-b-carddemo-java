package io.github.ltoscano.carddemo.parity.provajob.erroreprima;

import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.Step;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.infrastructure.repeat.RepeatStatus;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * Applicazione di prova dei test (issue #65, controprova del rilievo 1 del Validatore), non di
 * produzione: durante la creazione del contesto, prima che il selettore di Spring Boot scelga il job,
 * un bean fallisce con un'IllegalStateException dal testo identico a quello della diagnostica nativa
 * del job assente. Termina con 1. Il riconoscimento del job assente deve respingerla.
 */
@SpringBootApplication
public class AppErrorePrimaDellaSelezione {

    public static void main(String[] args) {
        System.exit(SpringApplication.exit(SpringApplication.run(AppErrorePrimaDellaSelezione.class, args)));
    }

    @Bean
    static InitializingBean erroreConLoStessoTesto() {
        return () -> {
            throw new IllegalStateException("No job found with name 'READACCT'");
        };
    }

    @Bean
    Step passoVuoto(JobRepository jobRepository) {
        return new StepBuilder("passoVuoto", jobRepository).tasklet((contribution, chunk) -> RepeatStatus.FINISHED).build();
    }

    @Bean
    Job jobPresente(JobRepository jobRepository, Step passoVuoto) {
        return new JobBuilder("READACCT", jobRepository).start(passoVuoto).build();
    }
}
