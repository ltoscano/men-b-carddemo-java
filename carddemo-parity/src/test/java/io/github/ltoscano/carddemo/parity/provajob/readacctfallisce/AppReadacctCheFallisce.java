package io.github.ltoscano.carddemo.parity.provajob.readacctfallisce;

import org.springframework.batch.core.job.Job;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.job.parameters.RunIdIncrementer;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.Step;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * Applicazione di prova dei test (issue #65, controprova del rilievo 1 del Validatore), non di
 * produzione: il job READACCT esiste, entra nel passo, stampa sullo standard output la stessa traccia
 * della diagnostica nativa del job assente (eccezione del bean del selettore, riga {@code Caused by}
 * e i due frame), cosi' che solo le tracce di avvio di Spring Batch la distinguano,
 * solleva un'IllegalStateException con lo stesso testo e termina con 1 senza scrivere le uscite.
 * Il riconoscimento del job assente deve respingerla: il job e' stato avviato.
 */
@SpringBootApplication
public class AppReadacctCheFallisce {

    static final String TESTO = "No job found with name 'READACCT'";

    public static void main(String[] args) {
        int codice = SpringApplication.exit(SpringApplication.run(AppReadacctCheFallisce.class, args));
        System.exit(codice == 0 ? 0 : 1);
    }

    @Bean
    Step passoCheFallisce(JobRepository jobRepository) {
        return new StepBuilder("passoCheFallisce", jobRepository).tasklet((contribution, chunk) -> {
            System.out.println("org.springframework.beans.factory.BeanCreationException: Error creating bean with name"
                    + " 'jobLauncherApplicationRunner' defined in class path resource"
                    + " [org/springframework/boot/batch/autoconfigure/BatchJobLauncherAutoConfiguration.class]: " + TESTO);
            System.out.println("Caused by: java.lang.IllegalStateException: " + TESTO);
            System.out.println("\tat org.springframework.util.Assert.state(Assert.java:102)");
            System.out.println("\tat org.springframework.boot.batch.autoconfigure.JobLauncherApplicationRunner"
                    + ".afterPropertiesSet(JobLauncherApplicationRunner.java:90)");
            throw new IllegalStateException(TESTO);
        }).build();
    }

    @Bean
    Job jobCheFallisce(JobRepository jobRepository, Step passoCheFallisce) {
        return new JobBuilder("READACCT", jobRepository).incrementer(new RunIdIncrementer()).start(passoCheFallisce).build();
    }
}
