package io.github.ltoscano.carddemo.batch.readacct;

import org.springframework.batch.core.job.JobExecution;
import org.springframework.boot.ExitCodeGenerator;
import org.springframework.boot.batch.autoconfigure.JobExecutionEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.core.Ordered;

/**
 * Codice di uscita del processo per il job {@code READACCT}: {@value #USCITA_FINE_ANOMALA} se un'esecuzione
 * del job e' terminata con {@link FineAnomala} (la fine anomala del programma, {@code CEE3ABD}), altrimenti
 * nessun contributo (0). Precede gli altri generatori di Spring Boot ({@link Ordered#HIGHEST_PRECEDENCE}):
 * {@code SpringApplication.exit} prende il primo codice diverso da 0, e quello di Spring Batch per un job
 * fallito (lo stato {@code FAILED}, 5) non distinguerebbe la fine anomala da un errore qualunque.
 *
 * <p>Gli errori di avvio dell'applicazione (database irraggiungibile all'avvio, parametri del job mancanti)
 * non arrivano qui: fanno fallire l'avvio di Spring Boot e il processo esce con 1.
 */
public final class EsitoReadacct implements ExitCodeGenerator, ApplicationListener<JobExecutionEvent>, Ordered {

    /** Codice di uscita della fine anomala: lo stesso dello stub {@code CEE3ABD} dell'oracle (#4). */
    public static final int USCITA_FINE_ANOMALA = 99;

    private volatile boolean fineAnomala;

    @Override
    public void onApplicationEvent(JobExecutionEvent evento) {
        JobExecution esecuzione = evento.getJobExecution();
        if (!ReadacctJobConfig.NOME_JOB.equals(esecuzione.getJobInstance().getJobName())) {
            return;
        }
        for (Throwable errore : esecuzione.getAllFailureExceptions()) {
            for (Throwable t = errore; t != null; t = t.getCause()) {
                if (t instanceof FineAnomala) {
                    fineAnomala = true;
                    return;
                }
            }
        }
    }

    @Override
    public int getExitCode() {
        return fineAnomala ? USCITA_FINE_ANOMALA : 0;
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
