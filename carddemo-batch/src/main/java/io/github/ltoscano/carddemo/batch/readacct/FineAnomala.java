package io.github.ltoscano.carddemo.batch.readacct;

import java.io.Serial;

/**
 * Fine anomala di {@code CBACT01C}: {@code 9999-ABEND-PROGRAM} e {@code CALL 'CEE3ABD'}
 * ({@code CBACT01C.cbl:406-410}). Quando il passo termina con questa eccezione il processo esce con
 * {@link EsitoReadacct#USCITA_FINE_ANOMALA}; le righe di console e la cancellazione dei file di uscita
 * sono gia' avvenute.
 */
public final class FineAnomala extends RuntimeException {

    @Serial
    private static final long serialVersionUID = 1L;

    private final String fase;

    /**
     * @param fase la fase del programma in cui e' avvenuto l'errore (vedi {@code docs/programmi/CBACT01C.md})
     * @param causa l'errore Java, o null se non ce n'e' uno
     */
    public FineAnomala(String fase, Throwable causa) {
        super("CBACT01C: fine anomala, fase: " + fase, causa);
        this.fase = fase;
    }

    /** @return la fase del programma in cui e' avvenuto l'errore */
    public String fase() {
        return fase;
    }
}
