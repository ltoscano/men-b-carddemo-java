package io.github.ltoscano.carddemo.batch.readacct;

/**
 * Il file dei conti {@code ACCTFILE} di {@code CBACT01C} ({@code SELECT ACCTFILE-FILE}, righe 29-33:
 * indicizzato, letto in sequenza per chiave). {@link #apri()} corrisponde a {@code OPEN INPUT} (riga 319).
 */
public interface SorgenteConti {

    /**
     * Apre l'accesso ai conti: connessione e interrogazione ordinata per chiave.
     *
     * @return il cursore posizionato prima del primo conto
     * @throws Exception qualunque errore dell'apertura (il programma lo tratta come il ramo d'errore di
     *     {@code 0000-ACCTFILE-OPEN})
     */
    CursoreConti apri() throws Exception;
}
