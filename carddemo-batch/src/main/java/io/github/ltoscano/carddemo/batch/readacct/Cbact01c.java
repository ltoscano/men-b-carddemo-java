package io.github.ltoscano.carddemo.batch.readacct;

import io.github.ltoscano.carddemo.domain.FieldCategory;
import io.github.ltoscano.carddemo.domain.FieldPicture;
import io.github.ltoscano.carddemo.domain.GnuCobolFieldCodec;
import java.io.IOException;
import java.io.OutputStream;
import java.io.Serial;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Traduzione di {@code CBACT01C} ({@code app/cbl/CBACT01C.cbl}): legge i conti in ordine di chiave e per
 * ognuno scrive un record in {@code OUTFILE}, uno in {@code ARRYFILE} e due in {@code VBRCFILE}, con le righe
 * di console dei {@code DISPLAY}. Un metodo per paragrafo, con il numero del paragrafo nel nome; la
 * corrispondenza riga per riga, le esclusioni e le convenzioni sono in {@code docs/programmi/CBACT01C.md}.
 *
 * <p>Fine anomala ({@code 9999-ABEND-PROGRAM}): righe del ramo d'errore, poi {@link FineAnomala}; i file
 * aperti si chiudono e i tre file di uscita si cancellano ({@code DISP=(NEW,CATLG,DELETE)}). Il dettaglio
 * tecnico dell'errore va nel log (standard error).
 */
public final class Cbact01c {

    private static final Logger LOG = LoggerFactory.getLogger(Cbact01c.class);

    // Letterali dei DISPLAY, con la riga del sorgente.
    static final String START = "START OF EXECUTION OF PROGRAM CBACT01C"; // 141
    static final String END = "END OF EXECUTION OF PROGRAM CBACT01C"; // 158
    static final String ETICHETTA_ACCT_ID = "ACCT-ID                 :"; // 201
    static final String ETICHETTA_ACCT_ACTIVE_STATUS = "ACCT-ACTIVE-STATUS      :"; // 202
    static final String ETICHETTA_ACCT_CURR_BAL = "ACCT-CURR-BAL           :"; // 203
    static final String ETICHETTA_ACCT_CREDIT_LIMIT = "ACCT-CREDIT-LIMIT       :"; // 204
    static final String ETICHETTA_ACCT_CASH_CREDIT_LIMIT = "ACCT-CASH-CREDIT-LIMIT  :"; // 205
    static final String ETICHETTA_ACCT_OPEN_DATE = "ACCT-OPEN-DATE          :"; // 206
    static final String ETICHETTA_ACCT_EXPIRAION_DATE = "ACCT-EXPIRAION-DATE     :"; // 207
    static final String ETICHETTA_ACCT_REISSUE_DATE = "ACCT-REISSUE-DATE       :"; // 208
    static final String ETICHETTA_ACCT_CURR_CYC_CREDIT = "ACCT-CURR-CYC-CREDIT    :"; // 209
    static final String ETICHETTA_ACCT_CURR_CYC_DEBIT = "ACCT-CURR-CYC-DEBIT     :"; // 210
    static final String ETICHETTA_ACCT_GROUP_ID = "ACCT-GROUP-ID           :"; // 211
    static final String TRATTINI = "-------------------------------------------------"; // 212
    static final String ETICHETTA_VBRC_REC1 = "VBRC-REC1:"; // 283
    static final String ETICHETTA_VBRC_REC2 = "VBRC-REC2:"; // 284
    static final String ERRORE_LETTURA = "ERROR READING ACCOUNT FILE"; // 192
    static final String ERRORE_SCRITTURA = "ACCOUNT FILE WRITE STATUS IS:"; // 246, 268, 294, 309 (senza lo stato)
    static final String ERRORE_APERTURA_CONTI = "ERROR OPENING ACCTFILE"; // 328
    static final String ERRORE_APERTURA_OUTFILE = "ERROR OPENING OUTFILE"; // 345 (senza lo stato)
    static final String ERRORE_APERTURA_ARRYFILE = "ERROR OPENING ARRAYFILE"; // 363 (senza lo stato)
    static final String ERRORE_APERTURA_VBRCFILE = "ERROR OPENING VBRC FILE"; // 381 (senza lo stato)
    static final String ERRORE_CHIUSURA_CONTI = "ERROR CLOSING ACCOUNT FILE"; // 399
    static final String ABENDING = "ABENDING PROGRAM"; // 407

    // Fasi della fine anomala (tabella "Errori" di docs/programmi/CBACT01C.md).
    static final String FASE_APERTURA_CONTI = "apertura dell'accesso ai conti";
    static final String FASE_LETTURA = "lettura dei conti";
    static final String FASE_CHIUSURA_CONTI = "chiusura dell'accesso ai conti";
    static final String FASE_CHIUSURA_USCITE = "svuotamento e chiusura dei file di uscita";
    static final String FASE_CONSOLE = "scrittura della console";
    static final String FASE_IMPREVISTA = "errore imprevisto";

    static final String OUTFILE = "OUTFILE";
    static final String ARRYFILE = "ARRYFILE";
    static final String VBRCFILE = "VBRCFILE";

    /** Lunghezze dei record: {@code OUT-ACCT-REC}, {@code ARR-ARRAY-REC}, {@code VBRC-REC1}, {@code VBRC-REC2}. */
    static final int LUNGHEZZA_OUTFILE = 107;
    static final int LUNGHEZZA_ARRYFILE = 110;
    static final int LUNGHEZZA_VBRC_REC1 = 12;
    static final int LUNGHEZZA_VBRC_REC2 = 39;

    /** {@code PIC S9(10)V99 USAGE IS COMP-3}: {@code OUT-ACCT-CURR-CYC-DEBIT}, {@code ARR-ACCT-CURR-CYC-DEBIT}. */
    static final FieldPicture IMPORTO_COMP3 = FieldPicture.of(FieldCategory.COMP_3, "S9(10)V9(2)");
    /** {@code PIC X(04)}: {@code ARR-FILLER}. */
    static final FieldPicture X4 = FieldPicture.of(FieldCategory.ALPHANUMERIC, "X(4)");

    // Costanti del sorgente, scritte come nel sorgente, con la riga.
    static final BigDecimal COSTANTE_2525 = new BigDecimal("2525.00"); // 237
    static final BigDecimal COSTANTE_1005 = new BigDecimal("1005.00"); // 256
    static final BigDecimal COSTANTE_1525 = new BigDecimal("1525.00"); // 258
    static final BigDecimal COSTANTE_MENO_1025 = new BigDecimal("-1025.00"); // 259
    static final BigDecimal COSTANTE_MENO_2500 = new BigDecimal("-2500.00"); // 260

    /**
     * Descrittori di record (RDW) di {@code VBRCFILE}: lunghezza del record compreso il descrittore, byte piu'
     * significativo per primo, poi {@code 00 00} (contratto di #65). {@code WS-RECD-LEN} vale 12 e 39 (righe
     * 288 e 303): 12 + 4 = 16 = {@code 0x10}, 39 + 4 = 43 = {@code 0x2B}.
     */
    private static final byte[] RDW_VBRC_REC1 = {0x00, 0x10, 0x00, 0x00};
    private static final byte[] RDW_VBRC_REC2 = {0x00, 0x2B, 0x00, 0x00};

    /**
     * Byte convenzionale del progetto dove il sorgente non determina il contenuto (byte 77-78 e, con addebito
     * diverso da zero, 91-97 di {@code OUTFILE}): non e' un comportamento dell'originale.
     */
    static final byte NON_DETERMINATO = 0x00;

    private static final byte A_CAPO = 0x0A;

    private final SorgenteConti sorgente;
    private final ApertureUscite aperture;
    private final Path percorsoOutfile;
    private final Path percorsoArryfile;
    private final Path percorsoVbrcfile;
    private final OutputStream console;

    private CursoreConti acctfile;
    private FileUscita outFile;
    private FileUscita arryFile;
    private FileUscita vbrcFile;

    /**
     * @param sorgente l'accesso ai conti ({@code ACCTFILE})
     * @param aperture la creazione dei file di uscita
     * @param outfile percorso di {@code OUTFILE}
     * @param arryfile percorso di {@code ARRYFILE}
     * @param vbrcfile percorso di {@code VBRCFILE}
     * @param console dove vanno le righe dei {@code DISPLAY} (lo standard output), nell'ordine in cui il
     *     programma le scrive; svuotato con {@code flush} alla fine e alla fine anomala, mai chiuso
     */
    public Cbact01c(SorgenteConti sorgente, ApertureUscite aperture, Path outfile, Path arryfile, Path vbrcfile,
            OutputStream console) {
        this.sorgente = Objects.requireNonNull(sorgente, "sorgente");
        this.aperture = Objects.requireNonNull(aperture, "aperture");
        this.percorsoOutfile = Objects.requireNonNull(outfile, OUTFILE);
        this.percorsoArryfile = Objects.requireNonNull(arryfile, ARRYFILE);
        this.percorsoVbrcfile = Objects.requireNonNull(vbrcfile, VBRCFILE);
        this.console = Objects.requireNonNull(console, "console");
    }

    /**
     * Il programma: {@code PREDEL} del JCL, poi la {@code PROCEDURE DIVISION} (righe 140-160), poi la chiusura
     * implicita dei tre file di uscita.
     *
     * @throws FineAnomala alla fine anomala, dopo le righe del ramo d'errore e la cancellazione delle uscite
     */
    public void esegui() {
        try {
            predel();
            display(START);
            p0000AcctfileOpen();
            p2000OutfileOpen();
            p3000ArrfileOpen();
            p4000VbrfileOpen();
            Optional<byte[]> accountRecord = p1000AcctfileGetNext();
            while (accountRecord.isPresent()) {
                display(accountRecord.get()); // 151: DISPLAY ACCOUNT-RECORD
                accountRecord = p1000AcctfileGetNext();
            }
            p9000AcctfileClose();
            display(END);
            svuotaConsole();
            chiudiUscite();
        } catch (FineAnomala e) {
            throw e;
        } catch (ErroreConsole e) {
            throw fineAnomala(FASE_CONSOLE, e.getCause());
        } catch (RuntimeException e) {
            throw fineAnomala(FASE_IMPREVISTA, e);
        }
    }

    /** {@code PREDEL} ({@code READACCT.jcl:22-28}): cancella le tre uscite se esistono. */
    private void predel() {
        cancellaUscite("PREDEL");
    }

    /** 0000-ACCTFILE-OPEN (righe 317-333). */
    private void p0000AcctfileOpen() {
        try {
            acctfile = Objects.requireNonNull(sorgente.apri(), "cursore dei conti");
        } catch (Exception e) {
            throw fineAnomala(FASE_APERTURA_CONTI, e, ERRORE_APERTURA_CONTI);
        }
    }

    /** 2000-OUTFILE-OPEN (righe 334-350). */
    private void p2000OutfileOpen() {
        outFile = apriUscita(OUTFILE, percorsoOutfile, ERRORE_APERTURA_OUTFILE);
    }

    /** 3000-ARRFILE-OPEN (righe 352-368). */
    private void p3000ArrfileOpen() {
        arryFile = apriUscita(ARRYFILE, percorsoArryfile, ERRORE_APERTURA_ARRYFILE);
    }

    /** 4000-VBRFILE-OPEN (righe 370-386). */
    private void p4000VbrfileOpen() {
        vbrcFile = apriUscita(VBRCFILE, percorsoVbrcfile, ERRORE_APERTURA_VBRCFILE);
    }

    private FileUscita apriUscita(String dd, Path percorso, String messaggio) {
        try {
            return Objects.requireNonNull(aperture.apri(dd, percorso), dd);
        } catch (Exception e) {
            throw fineAnomala("creazione di " + dd, e, messaggio);
        }
    }

    /**
     * 1000-ACCTFILE-GET-NEXT (righe 165-198): legge un conto e fa tutto il suo lavoro tranne il
     * {@code DISPLAY ACCOUNT-RECORD}, che il corpo principale fa dopo (riga 151).
     *
     * @return i 300 byte di {@code ACCOUNT-RECORD}, o nessuno a fine file
     */
    private Optional<byte[]> p1000AcctfileGetNext() {
        RecordConto conto;
        byte[] accountRecord;
        try {
            // 166: READ ACCTFILE-FILE INTO ACCOUNT-RECORD
            Optional<RecordConto> letto = acctfile.prossimo();
            if (letto.isEmpty()) {
                return Optional.empty(); // 180-181, 189-190: stato 10, fine file
            }
            conto = letto.get();
            accountRecord = Cvact01y.ricomponi(conto);
        } catch (Exception e) {
            throw fineAnomala(FASE_LETTURA, e, ERRORE_LETTURA); // 192-195
        }
        byte[] arrArrayRec = initializeArrArrayRec(); // 169
        p1100DisplayAcctRecord(accountRecord); // 170
        byte[] outAcctRec = p1300PopulAcctRecord(conto); // 171
        p1350WriteAcctRecord(outAcctRec); // 172
        p1400PopulArrayRecord(conto, arrArrayRec); // 173
        p1450WriteArryRecord(arrArrayRec); // 174
        byte[] vbrcRec1 = new byte[LUNGHEZZA_VBRC_REC1]; // 175: INITIALIZE VBRC-REC1 (poi valorizzato per intero)
        byte[] vbrcRec2 = new byte[LUNGHEZZA_VBRC_REC2];
        p1500PopulVbrcRecord(conto, vbrcRec1, vbrcRec2); // 176
        p1550WriteVb1Record(vbrcRec1); // 177
        p1575WriteVb2Record(vbrcRec2); // 178
        return Optional.of(accountRecord);
    }

    /**
     * {@code INITIALIZE ARR-ARRAY-REC} (riga 169): zeri ai numerici (zero con segno C: {@code 30}x11
     * {@code 7B} nel zonato, {@code 00}x6 {@code 0C} nel {@code COMP-3}), spazi agli alfanumerici
     * ({@code ARR-FILLER} e' un nome, non la parola {@code FILLER}).
     */
    static byte[] initializeArrArrayRec() {
        byte[] r = new byte[LUNGHEZZA_ARRYFILE];
        metti(r, 1, GnuCobolFieldCodec.encode(Cvact01y.CHIAVE, BigDecimal.ZERO));
        for (int occorrenza = 1; occorrenza <= 5; occorrenza++) {
            int base = 12 + 19 * (occorrenza - 1);
            metti(r, base, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, BigDecimal.ZERO));
            metti(r, base + 12, GnuCobolFieldCodec.encode(IMPORTO_COMP3, BigDecimal.ZERO));
        }
        metti(r, 107, GnuCobolFieldCodec.encode(X4, ""));
        return r;
    }

    /** 1100-DISPLAY-ACCT-RECORD (righe 200-213): ogni campo con i suoi byte del record. */
    private void p1100DisplayAcctRecord(byte[] r) {
        display(ETICHETTA_ACCT_ID, Cvact01y.campo(r, Cvact01y.POS_ACCT_ID, Cvact01y.CHIAVE));
        display(ETICHETTA_ACCT_ACTIVE_STATUS, Cvact01y.campo(r, Cvact01y.POS_ACCT_ACTIVE_STATUS, Cvact01y.X1));
        display(ETICHETTA_ACCT_CURR_BAL, Cvact01y.campo(r, Cvact01y.POS_ACCT_CURR_BAL, Cvact01y.IMPORTO));
        display(ETICHETTA_ACCT_CREDIT_LIMIT, Cvact01y.campo(r, Cvact01y.POS_ACCT_CREDIT_LIMIT, Cvact01y.IMPORTO));
        display(ETICHETTA_ACCT_CASH_CREDIT_LIMIT,
                Cvact01y.campo(r, Cvact01y.POS_ACCT_CASH_CREDIT_LIMIT, Cvact01y.IMPORTO));
        display(ETICHETTA_ACCT_OPEN_DATE, Cvact01y.campo(r, Cvact01y.POS_ACCT_OPEN_DATE, Cvact01y.X10));
        display(ETICHETTA_ACCT_EXPIRAION_DATE, Cvact01y.campo(r, Cvact01y.POS_ACCT_EXPIRAION_DATE, Cvact01y.X10));
        display(ETICHETTA_ACCT_REISSUE_DATE, Cvact01y.campo(r, Cvact01y.POS_ACCT_REISSUE_DATE, Cvact01y.X10));
        display(ETICHETTA_ACCT_CURR_CYC_CREDIT,
                Cvact01y.campo(r, Cvact01y.POS_ACCT_CURR_CYC_CREDIT, Cvact01y.IMPORTO));
        display(ETICHETTA_ACCT_CURR_CYC_DEBIT, Cvact01y.campo(r, Cvact01y.POS_ACCT_CURR_CYC_DEBIT, Cvact01y.IMPORTO));
        display(ETICHETTA_ACCT_GROUP_ID, Cvact01y.campo(r, Cvact01y.POS_ACCT_GROUP_ID, Cvact01y.X10));
        display(TRATTINI);
    }

    /** 1300-POPUL-ACCT-RECORD (righe 215-240): {@code OUT-ACCT-REC}, 107 byte. */
    static byte[] p1300PopulAcctRecord(RecordConto c) {
        byte[] r = new byte[LUNGHEZZA_OUTFILE];
        metti(r, 1, GnuCobolFieldCodec.encode(Cvact01y.CHIAVE, c.acctId())); // 216
        metti(r, 12, GnuCobolFieldCodec.encode(Cvact01y.X1, c.acctActiveStatus())); // 217
        metti(r, 13, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCurrBal())); // 218
        metti(r, 25, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCreditLimit())); // 219
        metti(r, 37, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCashCreditLimit())); // 220
        metti(r, 49, GnuCobolFieldCodec.encode(Cvact01y.X10, c.acctOpenDate())); // 221
        metti(r, 59, GnuCobolFieldCodec.encode(Cvact01y.X10, c.acctExpiraionDate())); // 222
        // 223-233: CODATECN-INP-DATE, tipi '2' e '2', CALL 'COBDATFT', MOVE CODATECN-0UT-DATE (byte 77-78
        // convenzionali)
        metti(r, 69, Cobdatft.converti(GnuCobolFieldCodec.encode(Cvact01y.X10, c.acctReissueDate())));
        metti(r, 79, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCurrCycCredit())); // 235
        if (c.acctCurrCycDebit().compareTo(BigDecimal.ZERO) == 0) { // 236
            metti(r, 91, GnuCobolFieldCodec.encode(IMPORTO_COMP3, COSTANTE_2525)); // 237
        } else {
            // MOVE saltato: il sorgente non determina i 7 byte; byte convenzionale, il programma prosegue
            Arrays.fill(r, 90, 97, NON_DETERMINATO);
        }
        metti(r, 98, GnuCobolFieldCodec.encode(Cvact01y.X10, c.acctGroupId())); // 239
        return r;
    }

    /** 1350-WRITE-ACCT-RECORD (righe 242-251). */
    private void p1350WriteAcctRecord(byte[] outAcctRec) {
        scrivi(outFile, OUTFILE, outAcctRec);
    }

    /** 1400-POPUL-ARRAY-RECORD (righe 253-261), sul record inizializzato alla riga 169. */
    static void p1400PopulArrayRecord(RecordConto c, byte[] r) {
        metti(r, 1, GnuCobolFieldCodec.encode(Cvact01y.CHIAVE, c.acctId())); // 254
        metti(r, 12, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCurrBal())); // 255: (1)
        metti(r, 24, GnuCobolFieldCodec.encode(IMPORTO_COMP3, COSTANTE_1005)); // 256: (1)
        metti(r, 31, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCurrBal())); // 257: (2)
        metti(r, 43, GnuCobolFieldCodec.encode(IMPORTO_COMP3, COSTANTE_1525)); // 258: (2)
        metti(r, 50, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, COSTANTE_MENO_1025)); // 259: (3)
        metti(r, 62, GnuCobolFieldCodec.encode(IMPORTO_COMP3, COSTANTE_MENO_2500)); // 260: (3)
    }

    /** 1450-WRITE-ARRY-RECORD (righe 263-274). */
    private void p1450WriteArryRecord(byte[] arrArrayRec) {
        scrivi(arryFile, ARRYFILE, arrArrayRec);
    }

    /** 1500-POPUL-VBRC-RECORD (righe 276-285). */
    private void p1500PopulVbrcRecord(RecordConto c, byte[] vbrcRec1, byte[] vbrcRec2) {
        byte[] chiave = GnuCobolFieldCodec.encode(Cvact01y.CHIAVE, c.acctId());
        metti(vbrcRec1, 1, chiave); // 277: VB1-ACCT-ID
        metti(vbrcRec2, 1, chiave); // 278: VB2-ACCT-ID
        metti(vbrcRec1, 12, GnuCobolFieldCodec.encode(Cvact01y.X1, c.acctActiveStatus())); // 279
        metti(vbrcRec2, 12, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCurrBal())); // 280
        metti(vbrcRec2, 24, GnuCobolFieldCodec.encode(Cvact01y.IMPORTO, c.acctCreditLimit())); // 281
        // 282: WS-ACCT-REISSUE-YYYY, i primi 4 byte di WS-REISSUE-DATE (che ha ricevuto ACCT-REISSUE-DATE, 224)
        byte[] wsReissueDate = GnuCobolFieldCodec.encode(Cvact01y.X10, c.acctReissueDate());
        metti(vbrcRec2, 36, Arrays.copyOf(wsReissueDate, 4));
        display(ETICHETTA_VBRC_REC1, vbrcRec1); // 283
        display(ETICHETTA_VBRC_REC2, vbrcRec2); // 284
    }

    /** 1550-WRITE-VB1-RECORD (righe 287-300): 12 byte, con il descrittore. */
    private void p1550WriteVb1Record(byte[] vbrcRec1) {
        scrivi(vbrcFile, VBRCFILE, conDescrittore(RDW_VBRC_REC1, vbrcRec1, LUNGHEZZA_VBRC_REC1));
    }

    /** 1575-WRITE-VB2-RECORD (righe 302-315): 39 byte, con il descrittore. */
    private void p1575WriteVb2Record(byte[] vbrcRec2) {
        scrivi(vbrcFile, VBRCFILE, conDescrittore(RDW_VBRC_REC2, vbrcRec2, LUNGHEZZA_VBRC_REC2));
    }

    static byte[] conDescrittore(byte[] rdw, byte[] dati, int lunghezza) {
        if (dati.length != lunghezza) {
            throw new IllegalStateException("record variabile di " + dati.length + " byte, attesi " + lunghezza);
        }
        byte[] r = Arrays.copyOf(rdw, rdw.length + dati.length);
        System.arraycopy(dati, 0, r, rdw.length, dati.length);
        return r;
    }

    private void scrivi(FileUscita file, String dd, byte[] record) {
        try {
            file.scrivi(record);
        } catch (Exception e) {
            throw fineAnomala("scrittura di " + dd, e, ERRORE_SCRITTURA);
        }
    }

    /** 9000-ACCTFILE-CLOSE (righe 388-404). */
    private void p9000AcctfileClose() {
        CursoreConti daChiudere = acctfile;
        acctfile = null;
        try {
            daChiudere.chiudi();
        } catch (Exception e) {
            throw fineAnomala(FASE_CHIUSURA_CONTI, e, ERRORE_CHIUSURA_CONTI);
        }
    }

    /**
     * Chiusura implicita dei tre file alla fine dell'esecuzione (il programma chiude solo {@code ACCTFILE}):
     * dopo la riga {@code END OF EXECUTION…}. Un errore non aggiunge righe alla console.
     */
    private void chiudiUscite() {
        Exception primo = null;
        for (FileUscita file : apertiENonChiusi()) {
            try {
                file.chiudi();
            } catch (Exception e) {
                if (primo == null) {
                    primo = e;
                } else {
                    primo.addSuppressed(e);
                }
            }
        }
        outFile = null;
        arryFile = null;
        vbrcFile = null;
        if (primo != null) {
            throw fineAnomala(FASE_CHIUSURA_USCITE, primo);
        }
    }

    private List<FileUscita> apertiENonChiusi() {
        return Arrays.asList(outFile, arryFile, vbrcFile).stream().filter(Objects::nonNull).toList();
    }

    /**
     * 9999-ABEND-PROGRAM (righe 406-410): le righe del ramo d'errore seguite da {@code ABENDING PROGRAM} (nessuna
     * riga se {@code righe} e' vuoto), poi la fine dell'unita' di esecuzione: file chiusi, i tre file di uscita
     * cancellati ({@code DISP=(NEW,CATLG,DELETE)}). Gli errori di questa pulizia vanno nel log.
     *
     * @return l'eccezione da lanciare
     */
    private FineAnomala fineAnomala(String fase, Throwable causa, String... righe) {
        LOG.error("CBACT01C: fine anomala nella fase '{}'", fase, causa);
        if (righe.length > 0) {
            try {
                for (String riga : righe) {
                    display(riga);
                }
                display(ABENDING);
                svuotaConsole();
            } catch (ErroreConsole e) {
                LOG.error("CBACT01C: console non scrivibile durante la fine anomala", e.getCause());
            }
        }
        if (acctfile != null) {
            CursoreConti daChiudere = acctfile;
            acctfile = null;
            try {
                daChiudere.chiudi();
            } catch (Exception e) {
                LOG.error("CBACT01C: chiusura dell'accesso ai conti dopo la fine anomala non riuscita", e);
            }
        }
        for (FileUscita file : apertiENonChiusi()) {
            try {
                file.chiudi();
            } catch (Exception e) {
                LOG.error("CBACT01C: chiusura di un file di uscita dopo la fine anomala non riuscita", e);
            }
        }
        outFile = null;
        arryFile = null;
        vbrcFile = null;
        cancellaUscite("fine anomala");
        return new FineAnomala(fase, causa);
    }

    /** Cancella i tre file di uscita che esistono (non le cartelle); gli errori vanno nel log. */
    private void cancellaUscite(String quando) {
        for (Path percorso : List.of(percorsoOutfile, percorsoArryfile, percorsoVbrcfile)) {
            try {
                if (!Files.isDirectory(percorso, LinkOption.NOFOLLOW_LINKS)) {
                    Files.deleteIfExists(percorso);
                }
            } catch (IOException | RuntimeException e) {
                LOG.error("CBACT01C ({}): cancellazione di {} non riuscita", quando, percorso, e);
            }
        }
    }

    private void display(String letterale) {
        riga(ascii(letterale));
    }

    private void display(String letterale, byte[] campo) {
        riga(ascii(letterale), campo);
    }

    private void display(byte[] gruppo) {
        riga(gruppo);
    }

    /** Una riga di console: le parti nell'ordine, poi LF. */
    private void riga(byte[]... parti) {
        try {
            for (byte[] parte : parti) {
                console.write(parte);
            }
            console.write(A_CAPO);
        } catch (IOException e) {
            throw new ErroreConsole(e);
        }
    }

    private void svuotaConsole() {
        try {
            console.flush();
        } catch (IOException e) {
            throw new ErroreConsole(e);
        }
    }

    private static byte[] ascii(String testo) {
        return testo.getBytes(StandardCharsets.US_ASCII);
    }

    /** Copia {@code campo} in {@code record} dalla posizione {@code posizione} contata da 1, come nei tracciati. */
    private static void metti(byte[] record, int posizione, byte[] campo) {
        System.arraycopy(campo, 0, record, posizione - 1, campo.length);
    }

    /** Errore di scrittura sulla console. */
    private static final class ErroreConsole extends RuntimeException {

        @Serial
        private static final long serialVersionUID = 1L;

        ErroreConsole(IOException causa) {
            super(causa);
        }
    }
}
