package io.github.ltoscano.carddemo.batch.readacct;

import java.util.Properties;
import java.util.UUID;
import org.springframework.batch.core.converter.DefaultJobParametersConverter;
import org.springframework.batch.core.job.parameters.JobParameters;
import org.springframework.batch.core.job.parameters.JobParametersBuilder;

/**
 * Conversione degli argomenti di avvio in parametri del job, usata dal selettore dei job di Spring Boot
 * ({@code JobLauncherApplicationRunner}): quella predefinita di Spring Batch ({@code OUTFILE=<percorso>}
 * diventa un parametro di tipo testo, identificativo) piu' un parametro identificativo {@value #AVVIO} con un
 * valore nuovo a ogni avvio.
 *
 * <p>Perche': un JCL si riesegue sempre, e il contratto di #65 chiede che due avvii con lo stesso comando
 * riescano entrambi. Con gli stessi parametri identificativi Spring Batch rifiuta il secondo avvio di
 * un'istanza completata ({@code JobInstanceAlreadyCompleteException}). Un incrementatore sul job non serve:
 * in Spring Batch 6.1 {@code JobOperator.start} di un job con incrementatore scarta i parametri passati
 * (osservato: il job partiva con il solo {@code run.id} e il validatore lo rifiutava). Il valore di
 * {@value #AVVIO} rende ogni avvio un'istanza nuova senza che il chiamante aggiunga nulla.
 *
 * <p>Un avvio senza parametri (per esempio {@code installationCheckJob}, che ha il suo incrementatore) resta
 * senza parametri: cosi' Spring Batch non avvisa di parametri scartati.
 */
public final class ParametriDiAvvio extends DefaultJobParametersConverter {

    /** Nome del parametro identificativo aggiunto a ogni avvio con parametri. */
    public static final String AVVIO = "menb.avvio";

    @Override
    public JobParameters getJobParameters(Properties properties) {
        JobParameters dati = super.getJobParameters(properties);
        if (dati.isEmpty()) {
            return dati;
        }
        return new JobParametersBuilder(dati).addString(AVVIO, UUID.randomUUID().toString(), true).toJobParameters();
    }
}
