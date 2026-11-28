package io.github.ltoscano.carddemo.batch.readacct;

import java.io.IOException;

/** Un file sequenziale di uscita aperto: scrittura di un record ({@code WRITE}) e chiusura. */
public interface FileUscita {

    /**
     * Scrive i byte del record cosi' come sono (per {@code VBRCFILE} descrittore compreso).
     *
     * @throws IOException se la scrittura fallisce
     */
    void scrivi(byte[] record) throws IOException;

    /**
     * Svuota e chiude il file.
     *
     * @throws IOException se lo svuotamento o la chiusura falliscono
     */
    void chiudi() throws IOException;
}
