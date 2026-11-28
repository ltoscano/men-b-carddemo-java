package io.github.ltoscano.carddemo.loader;

/**
 * Il caricamento dei conti si e' fermato: file non conforme (dimensione, campo non valido o non
 * canonico, {@code FILLER} non vuoto, chiave duplicata, byte nullo in un testo) o tabella non vuota.
 * Il messaggio e' la diagnosi, con numero di record, campo e byte quando riguarda il file. Nessuna
 * riga resta scritta: la transazione e' annullata.
 */
public class CaricamentoRifiutato extends Exception {

    private static final long serialVersionUID = 1L;

    /**
     * @param diagnosi che cosa ha fermato il caricamento e dove
     */
    public CaricamentoRifiutato(String diagnosi) {
        super(diagnosi);
    }

    /**
     * @param diagnosi che cosa ha fermato il caricamento e dove
     * @param causa l'errore che lo ha provocato
     */
    public CaricamentoRifiutato(String diagnosi, Throwable causa) {
        super(diagnosi, causa);
    }
}
