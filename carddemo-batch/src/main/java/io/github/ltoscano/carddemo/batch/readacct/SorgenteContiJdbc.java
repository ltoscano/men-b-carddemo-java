package io.github.ltoscano.carddemo.batch.readacct;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Optional;
import java.util.function.Supplier;
import javax.sql.DataSource;

/**
 * {@code ACCTFILE} sulla tabella {@code account} di PostgreSQL (issue #59): una connessione propria, in
 * sola lettura, con un cursore lato server ({@code fetchSize}, che il driver PostgreSQL usa solo fuori
 * da autocommit), e l'interrogazione {@link #LETTURA}, che dichiara esplicitamente l'ordine crescente di
 * {@code acct_id}: l'ordine di un KSDS letto in sequenza ({@code ACCESS MODE IS SEQUENTIAL},
 * {@code RECORD KEY IS FD-ACCT-ID}, {@code CBACT01C.cbl:29-33}), indipendente dall'ordine fisico delle righe.
 */
public final class SorgenteContiJdbc implements SorgenteConti {

    /** Colonne nell'ordine di {@code CVACT01Y}; ordine crescente della chiave, dichiarato. */
    static final String LETTURA = "select acct_id, acct_active_status, acct_curr_bal, acct_credit_limit,"
            + " acct_cash_credit_limit, acct_open_date, acct_expiraion_date, acct_reissue_date, acct_curr_cyc_credit,"
            + " acct_curr_cyc_debit, acct_addr_zip, acct_group_id from account order by acct_id";

    /** Righe chieste al server per ogni giro del cursore. */
    static final int RIGHE_PER_GIRO = 500;

    private final Supplier<DataSource> sorgenteDati;

    /**
     * @param sorgenteDati fornisce la sorgente dati dell'applicazione al momento dell'apertura (non alla
     *     costruzione: il contesto dei test di avvio non ha sorgente dati)
     */
    public SorgenteContiJdbc(Supplier<DataSource> sorgenteDati) {
        this.sorgenteDati = sorgenteDati;
    }

    @Override
    public CursoreConti apri() throws SQLException {
        Connection connessione = sorgenteDati.get().getConnection();
        PreparedStatement interrogazione = null;
        try {
            connessione.setAutoCommit(false);
            connessione.setReadOnly(true);
            interrogazione = connessione.prepareStatement(LETTURA, ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY);
            interrogazione.setFetchSize(RIGHE_PER_GIRO);
            ResultSet righe = interrogazione.executeQuery();
            return new Cursore(connessione, interrogazione, righe);
        } catch (SQLException | RuntimeException e) {
            chiudiDopoErrore(interrogazione, connessione, e);
            throw e;
        }
    }

    private static void chiudiDopoErrore(PreparedStatement interrogazione, Connection connessione, Exception errore) {
        try {
            if (interrogazione != null) {
                interrogazione.close();
            }
        } catch (SQLException e) {
            errore.addSuppressed(e);
        }
        try {
            connessione.close();
        } catch (SQLException e) {
            errore.addSuppressed(e);
        }
    }

    /** Cursore aperto: righe, interrogazione e connessione, chiusi insieme da {@link #chiudi()}. */
    private static final class Cursore implements CursoreConti {

        private final Connection connessione;
        private final PreparedStatement interrogazione;
        private final ResultSet righe;

        Cursore(Connection connessione, PreparedStatement interrogazione, ResultSet righe) {
            this.connessione = connessione;
            this.interrogazione = interrogazione;
            this.righe = righe;
        }

        @Override
        public Optional<RecordConto> prossimo() throws SQLException {
            if (!righe.next()) {
                return Optional.empty();
            }
            return Optional.of(new RecordConto(righe.getBigDecimal(1), righe.getString(2), righe.getBigDecimal(3),
                    righe.getBigDecimal(4), righe.getBigDecimal(5), righe.getString(6), righe.getString(7),
                    righe.getString(8), righe.getBigDecimal(9), righe.getBigDecimal(10), righe.getString(11),
                    righe.getString(12)));
        }

        /**
         * Chiude righe e interrogazione, conferma la transazione di sola lettura e chiude la connessione.
         * Il primo errore si rilancia; la connessione si chiude comunque.
         */
        @Override
        public void chiudi() throws SQLException {
            SQLException primo = null;
            try {
                righe.close();
                interrogazione.close();
                connessione.commit();
            } catch (SQLException e) {
                primo = e;
            }
            try {
                connessione.close();
            } catch (SQLException e) {
                if (primo == null) {
                    primo = e;
                } else {
                    primo.addSuppressed(e);
                }
            }
            if (primo != null) {
                throw primo;
            }
        }
    }
}
