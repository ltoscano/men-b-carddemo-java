package io.github.ltoscano.carddemo.batch.readacct;

import java.util.Optional;

/** Lettura sequenziale aperta di {@code ACCTFILE}, in ordine crescente di {@code ACCT-ID}. */
public interface CursoreConti {

    /**
     * {@code READ ACCTFILE-FILE INTO ACCOUNT-RECORD} ({@code CBACT01C.cbl:166}).
     *
     * @return il conto successivo, o nessuno a fine file (stato {@code 10})
     * @throws Exception qualunque errore della lettura (ramo d'errore di {@code 1000-ACCTFILE-GET-NEXT})
     */
    Optional<RecordConto> prossimo() throws Exception;

    /**
     * {@code CLOSE ACCTFILE-FILE} ({@code CBACT01C.cbl:390}).
     *
     * @throws Exception qualunque errore della chiusura (ramo d'errore di {@code 9000-ACCTFILE-CLOSE})
     */
    void chiudi() throws Exception;
}
