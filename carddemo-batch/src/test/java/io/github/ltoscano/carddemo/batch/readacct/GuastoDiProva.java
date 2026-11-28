package io.github.ltoscano.carddemo.batch.readacct;

/**
 * Le righe della tabella degli errori di {@code docs/programmi/CBACT01C.md} (e della specifica di #67), come
 * guasti da provocare sulla sorgente dei conti finta e sui file di uscita di {@link Prove}, con due conti in
 * ingresso. {@code NESSUNO} e' la corsa regolare.
 */
enum GuastoDiProva {
    NESSUNO,
    APERTURA_CONTI,
    LETTURA_PRIMO_CONTO,
    LETTURA_A_META,
    CREAZIONE_OUTFILE,
    CREAZIONE_ARRYFILE,
    CREAZIONE_VBRCFILE,
    SCRITTURA_OUTFILE,
    SCRITTURA_ARRYFILE,
    SCRITTURA_PRIMO_RECORD_VARIABILE,
    SCRITTURA_SECONDO_RECORD_VARIABILE,
    CHIUSURA_CONTI,
    CHIUSURA_OUTFILE,
    CHIUSURA_ARRYFILE,
    CHIUSURA_VBRCFILE,
    /** Fuori dalla tabella: un {@link Error} all'apertura dei conti, che il programma non intercetta. */
    ERRORE_GRAVE_APERTURA;

    /** Prepara il guasto sulla sorgente e sui file. */
    void applica(Prove.Conti conti, Prove.Uscite uscite) {
        switch (this) {
            case NESSUNO -> { }
            case APERTURA_CONTI -> conti.guastoApertura = true;
            case LETTURA_PRIMO_CONTO -> conti.guastoLettura = 1;
            case LETTURA_A_META -> conti.guastoLettura = 2;
            case CREAZIONE_OUTFILE -> uscite.guastoCreazione = "OUTFILE";
            case CREAZIONE_ARRYFILE -> uscite.guastoCreazione = "ARRYFILE";
            case CREAZIONE_VBRCFILE -> uscite.guastoCreazione = "VBRCFILE";
            case SCRITTURA_OUTFILE -> scrittura(uscite, "OUTFILE", 2);
            case SCRITTURA_ARRYFILE -> scrittura(uscite, "ARRYFILE", 1);
            case SCRITTURA_PRIMO_RECORD_VARIABILE -> scrittura(uscite, "VBRCFILE", 1);
            case SCRITTURA_SECONDO_RECORD_VARIABILE -> scrittura(uscite, "VBRCFILE", 2);
            case CHIUSURA_CONTI -> conti.guastoChiusura = true;
            case CHIUSURA_OUTFILE -> uscite.guastoChiusura = "OUTFILE";
            case CHIUSURA_ARRYFILE -> uscite.guastoChiusura = "ARRYFILE";
            case CHIUSURA_VBRCFILE -> uscite.guastoChiusura = "VBRCFILE";
            case ERRORE_GRAVE_APERTURA -> conti.erroreGraveApertura = true;
            default -> throw new IllegalStateException(name());
        }
    }

    private static void scrittura(Prove.Uscite uscite, String dd, int numero) {
        uscite.guastoScritturaDd = dd;
        uscite.guastoScritturaNumero = numero;
    }
}
