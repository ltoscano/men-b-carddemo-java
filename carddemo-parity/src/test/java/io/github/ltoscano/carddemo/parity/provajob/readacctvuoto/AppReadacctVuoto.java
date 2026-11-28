package io.github.ltoscano.carddemo.parity.provajob.readacctvuoto;

import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.job.parameters.RunIdIncrementer;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.Step;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.infrastructure.repeat.RepeatStatus;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * Applicazione di prova dei test (issue #65), non di produzione: un job il cui nome Spring Batch e'
 * {@code READACCT} e il cui bean si chiama {@code jobDiProva}; non scrive nulla. Serve a provare che
 * il rilevatore riconosce il job per nome e che i confronti e la riesecuzione lo respingono. Il
 * {@link RunIdIncrementer} fa riuscire anche il secondo avvio, cosi' la riesecuzione lo respinge per
 * le sentinelle rimaste e non per un rifiuto di Spring Batch.
 */
@SpringBootApplication
public class AppReadacctVuoto {

    public static void main(String[] args) {
        System.exit(SpringApplication.exit(SpringApplication.run(AppReadacctVuoto.class, args)));
    }

    @Bean
    Step passoCheNonScriveNulla(JobRepository jobRepository) {
        return new StepBuilder("passoCheNonScriveNulla", jobRepository)
                .tasklet((contribution, chunk) -> RepeatStatus.FINISHED).build();
    }

    @Bean
    Job jobDiProva(JobRepository jobRepository, Step passoCheNonScriveNulla) {
        return new JobBuilder("READACCT", jobRepository).incrementer(new RunIdIncrementer()).start(passoCheNonScriveNulla).build();
    }
}
