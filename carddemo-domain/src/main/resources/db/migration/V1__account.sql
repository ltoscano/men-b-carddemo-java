-- Tabella dei conti (issue #59): una riga per record ACCOUNT-RECORD del file indicizzato dei
-- conti (AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS, chiave KEYS(11 0) in app/jcl/ACCTFILE.jcl).
-- Colonne derivate dal contratto docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv
-- (copybook app/cpy/CVACT01Y.cpy), nell'ordine del copybook, una per campo elementare tranne
-- il FILLER, che non ha colonna. Regola dei tipi:
--   X(n)       -> TEXT COLLATE "C" con CHECK (char_length(colonna) = n): sempre esattamente n
--                 caratteri, spazi finali compresi; confronti e ordinamenti per codice del carattere.
--                 Non CHAR(n) (toglie gli spazi finali nelle conversioni a text, anche implicite)
--                 ne' VARCHAR(n) (tronca senza errore l'eccedenza di soli spazi prima del vincolo).
--   9(n)       -> NUMERIC(n,0)
--   S9(i)V9(d) -> NUMERIC(i+d,d)
-- Le date restano testo (PIC X(10), non validate dal legacy).
-- Tutte le colonne NOT NULL; nessun valore predefinito; vincoli oltre alla chiave primaria: il
-- CHECK sulla chiave (9(11) non ha segno) e la lunghezza esatta dei testi; nessun indice oltre a
-- quello della chiave primaria.
-- ACCT-EXPIRAION-DATE: il refuso del copybook si conserva nel nome della colonna.
-- Una migrazione applicata non si modifica: ogni cambiamento e' una migrazione nuova.
CREATE TABLE account (
    acct_id                NUMERIC(11,0)    NOT NULL,
    acct_active_status     TEXT COLLATE "C" NOT NULL,
    acct_curr_bal          NUMERIC(12,2)    NOT NULL,
    acct_credit_limit      NUMERIC(12,2)    NOT NULL,
    acct_cash_credit_limit NUMERIC(12,2)    NOT NULL,
    acct_open_date         TEXT COLLATE "C" NOT NULL,
    acct_expiraion_date    TEXT COLLATE "C" NOT NULL,
    acct_reissue_date      TEXT COLLATE "C" NOT NULL,
    acct_curr_cyc_credit   NUMERIC(12,2)    NOT NULL,
    acct_curr_cyc_debit    NUMERIC(12,2)    NOT NULL,
    acct_addr_zip          TEXT COLLATE "C" NOT NULL,
    acct_group_id          TEXT COLLATE "C" NOT NULL,
    CONSTRAINT account_pkey PRIMARY KEY (acct_id),
    CONSTRAINT account_acct_id_check CHECK (acct_id >= 0),
    CONSTRAINT account_acct_active_status_check CHECK (char_length(acct_active_status) = 1),
    CONSTRAINT account_acct_open_date_check CHECK (char_length(acct_open_date) = 10),
    CONSTRAINT account_acct_expiraion_date_check CHECK (char_length(acct_expiraion_date) = 10),
    CONSTRAINT account_acct_reissue_date_check CHECK (char_length(acct_reissue_date) = 10),
    CONSTRAINT account_acct_addr_zip_check CHECK (char_length(acct_addr_zip) = 10),
    CONSTRAINT account_acct_group_id_check CHECK (char_length(acct_group_id) = 10)
);
