-- Tabella dei conti (issue #59): una riga per record ACCOUNT-RECORD del file indicizzato dei
-- conti (AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS, chiave KEYS(11 0) in app/jcl/ACCTFILE.jcl).
-- Colonne derivate dal contratto docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv
-- (copybook app/cpy/CVACT01Y.cpy), nell'ordine del copybook, una per campo elementare tranne
-- il FILLER, che non ha colonna. Regola dei tipi: X(n) -> CHAR(n); 9(n) -> NUMERIC(n,0);
-- S9(i)V9(d) -> NUMERIC(i+d,d). Le date restano testo (PIC X(10), non validate dal legacy).
-- Tutte le colonne NOT NULL; nessun valore predefinito; unico vincolo oltre alla chiave primaria
-- il CHECK sulla chiave (9(11) non ha segno); nessun indice oltre a quello della chiave primaria.
-- ACCT-EXPIRAION-DATE: il refuso del copybook si conserva nel nome della colonna.
-- Una migrazione applicata non si modifica: ogni cambiamento e' una migrazione nuova.
CREATE TABLE account (
    acct_id                NUMERIC(11,0) NOT NULL,
    acct_active_status     CHAR(1)       NOT NULL,
    acct_curr_bal          NUMERIC(12,2) NOT NULL,
    acct_credit_limit      NUMERIC(12,2) NOT NULL,
    acct_cash_credit_limit NUMERIC(12,2) NOT NULL,
    acct_open_date         CHAR(10)      NOT NULL,
    acct_expiraion_date    CHAR(10)      NOT NULL,
    acct_reissue_date      CHAR(10)      NOT NULL,
    acct_curr_cyc_credit   NUMERIC(12,2) NOT NULL,
    acct_curr_cyc_debit    NUMERIC(12,2) NOT NULL,
    acct_addr_zip          CHAR(10)      NOT NULL,
    acct_group_id          CHAR(10)      NOT NULL,
    CONSTRAINT account_pkey PRIMARY KEY (acct_id),
    CONSTRAINT account_acct_id_check CHECK (acct_id >= 0)
);
