# CBACT01C (job READACCT): corrispondenza tra il sorgente COBOL e il Java

Issue #67. Scritto **prima del codice**, come chiede la specifica: per ogni paragrafo di `CBACT01C` e per ogni istruzione che produce un effetto osservabile (`MOVE` verso un'area di uscita, `WRITE`, `DISPLAY`, `CALL`, controllo di uno stato di file) dice riga del sorgente, che cosa fa, dove sta nel Java e se è tradotta o esclusa, con il motivo.

Sorgenti (righe dei file del submodule `legacy/aws-mainframe-modernization-carddemo/`, commit `59cc6c2`): `app/cbl/CBACT01C.cbl` (righe senza prefisso in questo documento), `app/cpy/CVACT01Y.cpy`, `app/cpy/CODATECN.cpy`, `app/asm/COBDATFT.asm`, `app/jcl/READACCT.jcl`. Riferimenti: `docs/legacy-map/golden-readacct.md` (#55), `oracle/routines/cobdatft-casi.md` (#24), contratto del job in `docs/contratti.md` (#65).

## Classi Java

Tutte nel modulo `carddemo-batch`, pacchetto `io.github.ltoscano.carddemo.batch.readacct`. Nessun tipo nuovo in `carddemo-domain`: la codifica dei campi è quella di #54 (`GnuCobolFieldCodec`, `FieldPicture`), riusata così com'è.

| Classe | Che cosa traduce |
| --- | --- |
| `ReadacctJobConfig` | il job `READACCT` (Spring Batch): un passo, che esegue il programma; parametri `OUTFILE`, `ARRYFILE`, `VBRCFILE` (nomi DD del JCL) |
| `Cbact01c` | la `PROCEDURE DIVISION`: un metodo per paragrafo, con il numero del paragrafo nel nome (`p1000AcctfileGetNext`, …) |
| `RecordConto` | i valori di `ACCOUNT-RECORD` (`COPY CVACT01Y`) letti da una riga della tabella `account` |
| `Cvact01y` | il tracciato di `ACCOUNT-RECORD` (posizioni e `PICTURE`), per ricomporre il record di 300 byte |
| `Cobdatft` | la routine assembler `COBDATFT` per la sola combinazione usata (ingresso `2`, uscita `2`) e l'area `CODATECN` (`COPY CODATECN`) |
| `SorgenteConti`, `CursoreConti`, `SorgenteContiJdbc` | il file indicizzato `ACCTFILE` (apertura, lettura sequenziale per chiave, chiusura) sulla tabella `account` di PostgreSQL |
| `ApertureUscite`, `FileUscita`, `ApertureUsciteSuDisco` | i tre file sequenziali di uscita (creazione, scrittura, chiusura) |
| `FineAnomala` | `9999-ABEND-PROGRAM` e la chiamata a `CEE3ABD` |
| `EsitoReadacct` | il codice di uscita del processo (0 a fine regolare, 99 a fine anomala del programma) |
| `UscitaConsole` | lo standard output delle righe dei `DISPLAY` (`SYSOUT`) |
| `ParametriDiAvvio` | la riesecuzione dello stesso comando (sezione "Riesecuzione") |

## JCL e ambiente di esecuzione

| Riga | Che cosa fa | Java | Esito |
| --- | --- | --- | --- |
| `READACCT.jcl:22-28` | passo `PREDEL` (`IEFBR14`, `DISP=(MOD,DELETE,DELETE)`): cancella le tre uscite se esistono | `Cbact01c.predel()`, primo atto del passo, prima di qualunque accesso alla tabella `account` | tradotto. Il repository JDBC di Spring Batch e Flyway accedono al database prima, all'avvio dell'applicazione: sono infrastruttura del nuovo sistema, non letture dei conti |
| `READACCT.jcl:32` | `EXEC PGM=CBACT01C` | job `READACCT`, avviato con `--spring.batch.job.name=READACCT` | tradotto (contratto in `docs/contratti.md`) |
| `READACCT.jcl:35-36` | `ACCTFILE`: il KSDS dei conti | `SorgenteContiJdbc` sulla tabella `account` (#59, #60) | tradotto |
| `READACCT.jcl:37-48` | `OUTFILE`, `ARRYFILE`, `VBRCFILE` con `DISP=(NEW,CATLG,DELETE)`: creati nuovi, conservati a fine regolare, cancellati a fine anomala | parametri del job con lo stesso nome; `ApertureUsciteSuDisco` crea il file con `CREATE_NEW`; `Cbact01c.fineAnomala(...)` cancella i tre file | tradotto |
| `READACCT.jcl:39,43` | `RECFM=FB`, `LRECL=107` e `110` | record fissi senza terminatori | tradotto |
| `READACCT.jcl:47` | `RECFM=VB,LRECL=84` | descrittore di record di 4 byte (RDW) davanti a ogni record: `Cbact01c.rdw(...)` | tradotto (formato fissato da #65) |
| `READACCT.jcl:49-50` | `SYSOUT`, `SYSPRINT` | standard output: solo le righe dei `DISPLAY`; i log vanno sullo standard error | tradotto |

## `ENVIRONMENT DIVISION` e `DATA DIVISION`

| Riga | Elemento | Java | Esito |
| --- | --- | --- | --- |
| 29-33 | `SELECT ACCTFILE-FILE`, `INDEXED`, `ACCESS SEQUENTIAL`, `RECORD KEY FD-ACCT-ID` | `SorgenteContiJdbc.LETTURA`: `select … from account order by acct_id` (ordine crescente della chiave dichiarato nell'interrogazione) | tradotto |
| 33, 38, 43, 48, 91-102 | `FILE STATUS` e le quattro aree di stato | nessuna | **escluso**: il nuovo sistema non ha gli stati di file del COBOL; un errore è un'eccezione Java, classificata per fase (sezione "Errori") |
| 35-48 | `SELECT OUT-FILE`, `ARRY-FILE`, `VBRC-FILE`, sequenziali | `ApertureUscite` / `FileUscita` | tradotto |
| 52-55 | `FD ACCTFILE-FILE`, `FD-ACCTFILE-REC` | `RecordConto` (la `READ … INTO` copia il record in `ACCOUNT-RECORD`) | tradotto |
| 56-69 | `FD OUT-FILE`, `OUT-ACCT-REC` (107 byte) | `Cbact01c.p1300PopulAcctRecord` compone i 107 byte campo per campo | tradotto (tabella del paragrafo 1300) |
| 71-78 | `FD ARRY-FILE`, `ARR-ARRAY-REC` (110 byte, `OCCURS 5`) | `Cbact01c.p1400PopulArrayRecord` sul record inizializzato da `Cbact01c.initializeArrArrayRec` | tradotto |
| 80-85 | `FD VBRC-FILE`, `RECORDING MODE V`, `VARYING 10 TO 80 DEPENDING ON WS-RECD-LEN`, `VBR-REC PIC X(80)` | `Cbact01c.p1550WriteVb1Record`, `p1575WriteVb2Record`: dati di 12 e 39 byte, ciascuno preceduto dal descrittore | tradotto |
| 89 | `COPY CVACT01Y` (`ACCOUNT-RECORD`, `CVACT01Y.cpy:4-17`) | `RecordConto` (valori, uno per campo elementare tranne il `FILLER`) e `Cvact01y` (posizioni, `PICTURE`, 178 spazi del `FILLER`) | tradotto |
| 90 | `COPY CODATECN` (`CODATECN-REC`, `CODATECN.cpy:17-52`) | `Cobdatft` | tradotto per i campi usati: `CODATECN-TYPE` e `CODATECN-OUTTYPE` (fissi a `2`), `CODATECN-INP-DATE` (la data d'ingresso), i primi 10 byte di `CODATECN-0UT-DATE`. **Esclusi** con motivo: le ridefinizioni `CODATECN-1INP`, `-2INP`, `-1OUT`, `-2OUT` (viste diverse degli stessi byte, nessuna letta dal programma); i byte 11-20 di `CODATECN-0UT-DATE` (mai copiati in uscita); `CODATECN-ERROR-MSG` (scritto da `COBDATFT` solo nel ramo d'errore, che con ingresso `2` e uscita `2` non si percorre, e mai copiato in uscita) |
| 104-113 | `IO-STATUS`, `TWO-BYTES-BINARY`, `TWO-BYTES-ALPHA`, `IO-STATUS-04` | nessuna | **escluso**: servono solo a `9910-DISPLAY-IO-STATUS`, escluso (sotto) |
| 115-117 | `APPL-RESULT`, `APPL-AOK`, `APPL-EOF` | flusso di controllo dei metodi (eccezione o fine dei conti) | tradotto come flusso, senza variabile: non produce effetti osservabili |
| 119 | `END-OF-FILE` | ciclo di `Cbact01c.esegui()` finché `CursoreConti.prossimo()` restituisce un conto | tradotto come flusso |
| 120-121 | `ABCODE`, `TIMING` | nessuna | **escluso**: argomenti di `CEE3ABD`; il nuovo sistema termina con un codice di uscita (sezione "Codice di uscita") |
| 122 | `WS-RECD-LEN` | lunghezza dei dati del record variabile (12, 39), da cui il descrittore | tradotto |
| 123-125 | `VBRC-REC1` (12 byte) | array di 12 byte in `p1500PopulVbrcRecord` | tradotto |
| 126-130 | `VBRC-REC2` (39 byte) | array di 39 byte in `p1500PopulVbrcRecord` | tradotto |
| 131-137 | `WS-ACCT-REISSUE-DATE` e la ridefinizione `WS-REISSUE-DATE` | i primi 4 caratteri di `ACCT-REISSUE-DATE` (`WS-ACCT-REISSUE-YYYY`) in `p1500PopulVbrcRecord`; gli altri sottocampi non sono letti dal programma | tradotto per `WS-ACCT-REISSUE-YYYY`; **esclusi** `WS-FILLER-1`, `WS-ACCT-REISSUE-MM`, `WS-FILLER-2`, `WS-ACCT-REISSUE-DD` (mai letti) |

## `PROCEDURE DIVISION`, paragrafo per paragrafo

### Corpo principale (righe 140-160) → `Cbact01c.esegui()`

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 141 | `DISPLAY 'START OF EXECUTION OF PROGRAM CBACT01C'` | `display(START)` dopo `predel()` | tradotto, testo identico |
| 142 | `PERFORM 0000-ACCTFILE-OPEN` | `p0000AcctfileOpen()` | tradotto |
| 143 | `PERFORM 2000-OUTFILE-OPEN` | `p2000OutfileOpen()` | tradotto |
| 144 | `PERFORM 3000-ARRFILE-OPEN` | `p3000ArrfileOpen()` | tradotto |
| 145 | `PERFORM 4000-VBRFILE-OPEN` | `p4000VbrfileOpen()` | tradotto |
| 147-154 | `PERFORM UNTIL END-OF-FILE = 'Y'` … `PERFORM 1000-ACCTFILE-GET-NEXT` | ciclo su `p1000AcctfileGetNext()`, che restituisce il conto letto o nessuno a fine file | tradotto |
| 151 | `DISPLAY ACCOUNT-RECORD` (gruppo di 300 byte), **dopo** tutto il lavoro del conto fatto dentro 1000 | `display(Cvact01y.ricomponi(conto))` dopo il ritorno di `p1000AcctfileGetNext()` | tradotto: una riga con i 300 byte (sezione "Console") |
| 156 | `PERFORM 9000-ACCTFILE-CLOSE` | `p9000AcctfileClose()` | tradotto |
| 158 | `DISPLAY 'END OF EXECUTION OF PROGRAM CBACT01C'` | `display(END)` | tradotto, testo identico |
| 160 | `GOBACK`: fine dell'unità di esecuzione; i tre file di uscita, mai chiusi dal programma, si chiudono implicitamente | `chiudiUscite()` dopo la riga `END OF EXECUTION…`: svuotamento e chiusura dei tre file | tradotto (sezione "Apertura, chiusura, fine") |

### `1000-ACCTFILE-GET-NEXT` (righe 165-198) → `p1000AcctfileGetNext()`

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 166 | `READ ACCTFILE-FILE INTO ACCOUNT-RECORD` | `CursoreConti.prossimo()`: avanza il cursore della lettura ordinata e costruisce `RecordConto` dalla riga | tradotto |
| 167 | `IF ACCTFILE-STATUS = '00'` | `prossimo()` restituisce un conto | tradotto come flusso |
| 168 | `MOVE 0 TO APPL-RESULT` | — | flusso, nessun effetto osservabile |
| 169 | `INITIALIZE ARR-ARRAY-REC` | `initializeArrArrayRec()`: record di 110 byte con `ARR-ACCT-ID` a zeri, ogni `ARR-ACCT-CURR-BAL` a zero con segno (`30`×11 `7B`, `encode` di `0.00` in `S9(10)V9(2)`), ogni `ARR-ACCT-CURR-CYC-DEBIT` a zero `COMP-3` (`00`×6 `0C`), `ARR-FILLER` a spazi | tradotto. Le occorrenze 4 e 5 e `ARR-FILLER` restano così (byte 69-110); i byte 80 e 99 valgono `7B` secondo le regole del linguaggio, non `30` come scrive l'oracle (#55, `correzioni.tsv`) |
| 170 | `PERFORM 1100-DISPLAY-ACCT-RECORD` | `p1100DisplayAcctRecord(conto)` | tradotto |
| 171 | `PERFORM 1300-POPUL-ACCT-RECORD` | `p1300PopulAcctRecord(conto)` | tradotto |
| 172 | `PERFORM 1350-WRITE-ACCT-RECORD` | `p1350WriteAcctRecord(record)` | tradotto |
| 173 | `PERFORM 1400-POPUL-ARRAY-RECORD` | `p1400PopulArrayRecord(conto, record)` | tradotto |
| 174 | `PERFORM 1450-WRITE-ARRY-RECORD` | `p1450WriteArryRecord(record)` | tradotto |
| 175 | `INITIALIZE VBRC-REC1` | `p1500PopulVbrcRecord` crea `VBRC-REC1` nuovo; i suoi due campi sono poi valorizzati per intero (righe 277-279) | tradotto: nessun byte dell'inizializzazione arriva in uscita |
| 176 | `PERFORM 1500-POPUL-VBRC-RECORD` | `p1500PopulVbrcRecord(conto)` | tradotto |
| 177 | `PERFORM 1550-WRITE-VB1-RECORD` | `p1550WriteVb1Record(rec1)` | tradotto |
| 178 | `PERFORM 1575-WRITE-VB2-RECORD` | `p1575WriteVb2Record(rec2)` | tradotto |
| 180-181 | stato `10` → `APPL-RESULT` 16 → `END-OF-FILE = 'Y'` (righe 189-190) | `prossimo()` restituisce nessun conto: fine del ciclo | tradotto |
| 183 | ogni altro stato → `APPL-RESULT` 12 | `prossimo()` solleva un'eccezione | tradotto |
| 192 | `DISPLAY 'ERROR READING ACCOUNT FILE'` | `fineAnomala(FASE_LETTURA, …)` scrive la riga | tradotto, testo identico |
| 193-194 | `MOVE ACCTFILE-STATUS TO IO-STATUS`, `PERFORM 9910-DISPLAY-IO-STATUS` | — | **escluso**: nessuno stato di file (sezione "Errori") |
| 195 | `PERFORM 9999-ABEND-PROGRAM` | `fineAnomala(...)` | tradotto |

### `1100-DISPLAY-ACCT-RECORD` (righe 200-213) → `p1100DisplayAcctRecord(conto)`

Ogni `DISPLAY` è una riga: letterale e poi i byte del campo come sono nel record (sezione "Console").

| Riga | Istruzione | Riga di console prodotta | Esito |
| --- | --- | --- | --- |
| 201 | `DISPLAY 'ACCT-ID                 :' ACCT-ID` | letterale + 11 cifre di `ACCT-ID` (`9(11)`) | tradotto |
| 202 | `DISPLAY 'ACCT-ACTIVE-STATUS      :' ACCT-ACTIVE-STATUS` | letterale + 1 carattere | tradotto |
| 203 | `DISPLAY 'ACCT-CURR-BAL           :' ACCT-CURR-BAL` | letterale + 12 byte del campo `S9(10)V99` (segno sovrapposto all'ultima cifra) | tradotto, forma dichiarata (non confrontata dal test di parità) |
| 204 | `DISPLAY 'ACCT-CREDIT-LIMIT       :' ACCT-CREDIT-LIMIT` | come 203 | tradotto, forma dichiarata |
| 205 | `DISPLAY 'ACCT-CASH-CREDIT-LIMIT  :' ACCT-CASH-CREDIT-LIMIT` | come 203 | tradotto, forma dichiarata |
| 206 | `DISPLAY 'ACCT-OPEN-DATE          :' ACCT-OPEN-DATE` | letterale + 10 caratteri | tradotto |
| 207 | `DISPLAY 'ACCT-EXPIRAION-DATE     :' ACCT-EXPIRAION-DATE` | letterale + 10 caratteri | tradotto |
| 208 | `DISPLAY 'ACCT-REISSUE-DATE       :' ACCT-REISSUE-DATE` | letterale + 10 caratteri | tradotto |
| 209 | `DISPLAY 'ACCT-CURR-CYC-CREDIT    :' ACCT-CURR-CYC-CREDIT` | come 203 | tradotto, forma dichiarata |
| 210 | `DISPLAY 'ACCT-CURR-CYC-DEBIT     :' ACCT-CURR-CYC-DEBIT` | come 203 | tradotto, forma dichiarata |
| 211 | `DISPLAY 'ACCT-GROUP-ID           :' ACCT-GROUP-ID` | letterale + 10 caratteri | tradotto |
| 212 | `DISPLAY '-------------------------------------------------'` | 49 trattini | tradotto |

### `1300-POPUL-ACCT-RECORD` (righe 215-240) → `p1300PopulAcctRecord(conto)`: `OUTFILE`, 107 byte

| Riga | Istruzione | Byte di `OUTFILE` | Java | Esito |
| --- | --- | --- | --- | --- |
| 216 | `MOVE ACCT-ID TO OUT-ACCT-ID` (`9(11)`) | 1-11 | `encode(9(11), acctId)` | tradotto |
| 217 | `MOVE ACCT-ACTIVE-STATUS TO OUT-ACCT-ACTIVE-STATUS` (`X(01)`) | 12 | `encode(X(1), …)` | tradotto (qualunque valore, non solo `Y`) |
| 218 | `MOVE ACCT-CURR-BAL TO OUT-ACCT-CURR-BAL` (`S9(10)V99`) | 13-24 | `encode(S9(10)V9(2), …)` | tradotto |
| 219 | `MOVE ACCT-CREDIT-LIMIT TO OUT-ACCT-CREDIT-LIMIT` | 25-36 | come sopra | tradotto |
| 220 | `MOVE ACCT-CASH-CREDIT-LIMIT TO OUT-ACCT-CASH-CREDIT-LIMIT` | 37-48 | come sopra | tradotto |
| 221 | `MOVE ACCT-OPEN-DATE TO OUT-ACCT-OPEN-DATE` (`X(10)`) | 49-58 | `encode(X(10), …)` | tradotto |
| 222 | `MOVE ACCT-EXPIRAION-DATE TO OUT-ACCT-EXPIRAION-DATE` | 59-68 | come sopra | tradotto |
| 223-224 | `MOVE ACCT-REISSUE-DATE TO CODATECN-INP-DATE WS-REISSUE-DATE` | — | ingresso di `Cobdatft.converti(…)` (i 10 caratteri della data, seguiti da 10 spazi del `MOVE` in un `X(20)`, che `COBDATFT` non legge in questo caso) e, per `WS-ACCT-REISSUE-YYYY`, di `p1500PopulVbrcRecord` | tradotto |
| 225-226 | `MOVE '2' TO CODATECN-TYPE`, `MOVE '2' TO CODATECN-OUTTYPE` | — | la sola combinazione tradotta in `Cobdatft` | tradotto |
| 231 | `CALL 'COBDATFT' USING CODATECN-REC` | — | `Cobdatft.converti(data)`: caratteri 1-4, 6-7 e 9-10 dell'ingresso nei primi 8 byte dell'uscita, senza alcuna validazione (`COBDATFT.asm:46-53`: con ingresso `2` il controllo dei separatori è commentato, righe 47-48; con uscita `2` non si salta all'errore, righe 49-50) | tradotto. Le altre combinazioni di `COBDATFT` (ingresso `1`, tipi diversi da `1` e `2`, ramo `GOTOERR`) **escluse**: il programma non le usa |
| 233 | `MOVE CODATECN-0UT-DATE TO OUT-ACCT-REISSUE-DATE` (10 dei 20 byte) | 69-76 | gli 8 byte scritti da `Cobdatft` | tradotto |
| 233 | (stessa istruzione) | **77-78** | byte `X'00'` | **convenzione del progetto, non comportamento dell'originale** (sezione "Byte che il sorgente non determina", caso a) |
| 235 | `MOVE ACCT-CURR-CYC-CREDIT TO OUT-ACCT-CURR-CYC-CREDIT` | 79-90 | `encode(S9(10)V9(2), …)` | tradotto |
| 236-238 | `IF ACCT-CURR-CYC-DEBIT EQUAL TO ZERO MOVE 2525.00 TO OUT-ACCT-CURR-CYC-DEBIT` (`S9(10)V99 COMP-3`) | 91-97 | `debito.compareTo(ZERO) == 0` → `encode(COMP_3 S9(10)V9(2), new BigDecimal("2525.00"))` = `00 00 00 02 52 50 0C`; costante `CBACT01C.cbl:237` | tradotto |
| 236-238 | (addebito diverso da zero: il `MOVE` è saltato) | **91-97** | sette byte `X'00'`; il programma prosegue | **convenzione del progetto, non comportamento dell'originale** (caso b) |
| 239 | `MOVE ACCT-GROUP-ID TO OUT-ACCT-GROUP-ID` | 98-107 | `encode(X(10), …)` | tradotto |

### `1350-WRITE-ACCT-RECORD` (righe 242-251) → `p1350WriteAcctRecord(record)`

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 243 | `WRITE OUT-ACCT-REC` | `outfile.scrivi(record)` (107 byte) | tradotto |
| 245 | `IF OUTFILE-STATUS NOT = '00' AND NOT = '10'` | eccezione di `scrivi` | tradotto come flusso; lo stato `10` (fine file) non ha corrispondente in scrittura |
| 246 | `DISPLAY 'ACCOUNT FILE WRITE STATUS IS:' OUTFILE-STATUS` | riga `ACCOUNT FILE WRITE STATUS IS:` **senza** lo stato | tradotto il letterale; **escluso** lo stato |
| 247-248 | `MOVE OUTFILE-STATUS TO IO-STATUS`, `PERFORM 9910-DISPLAY-IO-STATUS` | — | **escluso** (sezione "Errori") |
| 249 | `PERFORM 9999-ABEND-PROGRAM` | `fineAnomala(...)` | tradotto |

### `1400-POPUL-ARRAY-RECORD` (righe 253-261) → `p1400PopulArrayRecord(conto, record)`: `ARRYFILE`, 110 byte

| Riga | Istruzione | Byte di `ARRYFILE` | Java | Esito |
| --- | --- | --- | --- | --- |
| 254 | `MOVE ACCT-ID TO ARR-ACCT-ID` | 1-11 | `encode(9(11), …)` | tradotto |
| 255 | `MOVE ACCT-CURR-BAL TO ARR-ACCT-CURR-BAL(1)` | 12-23 | `encode(S9(10)V9(2), …)` | tradotto |
| 256 | `MOVE 1005.00 TO ARR-ACCT-CURR-CYC-DEBIT(1)` | 24-30 | `encode(COMP_3, new BigDecimal("1005.00"))`; costante `CBACT01C.cbl:256` | tradotto |
| 257 | `MOVE ACCT-CURR-BAL TO ARR-ACCT-CURR-BAL(2)` | 31-42 | `encode(S9(10)V9(2), …)` del saldo | tradotto |
| 258 | `MOVE 1525.00 TO ARR-ACCT-CURR-CYC-DEBIT(2)` | 43-49 | `new BigDecimal("1525.00")`; costante `CBACT01C.cbl:258` | tradotto |
| 259 | `MOVE -1025.00 TO ARR-ACCT-CURR-BAL(3)` | 50-61 | `encode(S9(10)V9(2), new BigDecimal("-1025.00"))`; costante `CBACT01C.cbl:259` | tradotto |
| 260 | `MOVE -2500.00 TO ARR-ACCT-CURR-CYC-DEBIT(3)` | 62-68 | `encode(COMP_3, new BigDecimal("-2500.00"))`; costante `CBACT01C.cbl:260` | tradotto |
| 169 | (`INITIALIZE`, nessun `MOVE` successivo) `ARR-ACCT-CURR-BAL(4)`, `(5)` | 69-80, 88-99 | `30`×11 `7B` | tradotto (regole del linguaggio, #55) |
| 169 | (`INITIALIZE`) `ARR-ACCT-CURR-CYC-DEBIT(4)`, `(5)` | 81-87, 100-106 | `00`×6 `0C` | tradotto |
| 169 | (`INITIALIZE`) `ARR-FILLER` (`X(04)`, un nome, non `FILLER`) | 107-110 | 4 spazi | tradotto |

Nessuna aritmetica: le costanti sono scritte come nel sorgente, con la scala della `PICTURE` (`BigDecimal` da stringa), e il solo confronto è quello con zero della riga 236.

### `1450-WRITE-ARRY-RECORD` (righe 263-274) → `p1450WriteArryRecord(record)`

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 264 | `WRITE ARR-ARRAY-REC` | `arryfile.scrivi(record)` (110 byte) | tradotto |
| 266-273 | stato diverso da `00` e `10`: `DISPLAY 'ACCOUNT FILE WRITE STATUS IS:' ARRYFILE-STATUS`, 9910, 9999 | riga `ACCOUNT FILE WRITE STATUS IS:` senza stato, poi `fineAnomala` | tradotto il letterale e l'arresto; **esclusi** stato e 9910 |

### `1500-POPUL-VBRC-RECORD` (righe 276-285) → `p1500PopulVbrcRecord(conto)`

| Riga | Istruzione | Byte | Java | Esito |
| --- | --- | --- | --- | --- |
| 277-278 | `MOVE ACCT-ID TO VB1-ACCT-ID VB2-ACCT-ID` | `VBRC-REC1` 1-11, `VBRC-REC2` 1-11 | `encode(9(11), …)` in entrambi | tradotto |
| 279 | `MOVE ACCT-ACTIVE-STATUS TO VB1-ACCT-ACTIVE-STATUS` | `VBRC-REC1` 12 | `encode(X(1), …)` | tradotto |
| 280 | `MOVE ACCT-CURR-BAL TO VB2-ACCT-CURR-BAL` | `VBRC-REC2` 12-23 | `encode(S9(10)V9(2), …)` | tradotto |
| 281 | `MOVE ACCT-CREDIT-LIMIT TO VB2-ACCT-CREDIT-LIMIT` | `VBRC-REC2` 24-35 | come sopra | tradotto |
| 282 | `MOVE WS-ACCT-REISSUE-YYYY TO VB2-ACCT-REISSUE-YYYY` | `VBRC-REC2` 36-39 | primi 4 caratteri di `ACCT-REISSUE-DATE` (righe 223-224) | tradotto |
| 283 | `DISPLAY 'VBRC-REC1:' VBRC-REC1` | console | letterale + 12 byte | tradotto |
| 284 | `DISPLAY 'VBRC-REC2:' VBRC-REC2` | console | letterale + 39 byte (i due importi con il segno sovrapposto) | tradotto, forma dichiarata |

### `1550-WRITE-VB1-RECORD` (righe 287-300) e `1575-WRITE-VB2-RECORD` (righe 302-315) → `p1550WriteVb1Record`, `p1575WriteVb2Record`

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 288, 303 | `MOVE 12 TO WS-RECD-LEN`, `MOVE 39 TO WS-RECD-LEN` | lunghezza dei dati del record | tradotto |
| 289, 304 | `MOVE VBRC-REC1 TO VBR-REC(1:WS-RECD-LEN)`, `MOVE VBRC-REC2 …` | i 12 o 39 byte del record; i byte di `VBR-REC` oltre la lunghezza non entrano nel record (#55) | tradotto |
| 290, 305 | `WRITE VBR-REC` | `vbrcfile.scrivi(rdw(dati))`: `00 10 00 00` + 12 byte, `00 2B 00 00` + 39 byte (lunghezza compresa del descrittore, byte più significativo per primo; contratto di #65) | tradotto |
| 292-299, 307-314 | stato diverso da `00` e `10`: `DISPLAY 'ACCOUNT FILE WRITE STATUS IS:' VBRCFILE-STATUS`, 9910, 9999 | riga `ACCOUNT FILE WRITE STATUS IS:` senza stato, poi `fineAnomala` | tradotto il letterale e l'arresto; **esclusi** stato e 9910 |

### Apertura e chiusura

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 317-333 | `0000-ACCTFILE-OPEN`: `OPEN INPUT ACCTFILE-FILE`; se lo stato non è `00`: `DISPLAY 'ERROR OPENING ACCTFILE'` (328), 9910, 9999 | `p0000AcctfileOpen()`: `SorgenteConti.apri()` (connessione e interrogazione ordinata); un'eccezione → riga `ERROR OPENING ACCTFILE`, `fineAnomala` | tradotto; **esclusi** stato e 9910 |
| 334-350 | `2000-OUTFILE-OPEN`: `OPEN OUTPUT OUT-FILE`; errore: `DISPLAY 'ERROR OPENING OUTFILE' OUTFILE-STATUS` (345), 9910, 9999 | `p2000OutfileOpen()`: `ApertureUscite.apri("OUTFILE", …)`; un'eccezione → riga `ERROR OPENING OUTFILE` (senza lo stato), `fineAnomala` | tradotto; **esclusi** stato e 9910 |
| 352-368 | `3000-ARRFILE-OPEN`: `OPEN OUTPUT ARRY-FILE`; errore: `DISPLAY 'ERROR OPENING ARRAYFILE' ARRYFILE-STATUS` (363) | `p3000ArrfileOpen()`; riga `ERROR OPENING ARRAYFILE` | tradotto; **esclusi** stato e 9910 |
| 370-386 | `4000-VBRFILE-OPEN`: `OPEN OUTPUT VBRC-FILE`; errore: `DISPLAY 'ERROR OPENING VBRC FILE' VBRCFILE-STATUS` (381) | `p4000VbrfileOpen()`; riga `ERROR OPENING VBRC FILE` | tradotto; **esclusi** stato e 9910 |
| 388-404 | `9000-ACCTFILE-CLOSE`: `CLOSE ACCTFILE-FILE`; errore: `DISPLAY 'ERROR CLOSING ACCOUNT FILE'` (399), 9910, 9999 | `p9000AcctfileClose()`: `CursoreConti.chiudi()`; un'eccezione → riga `ERROR CLOSING ACCOUNT FILE`, `fineAnomala` | tradotto; **esclusi** stato e 9910 |
| 389, 392, 394 | `ADD 8 TO ZERO GIVING APPL-RESULT`, `SUBTRACT APPL-RESULT FROM APPL-RESULT`, `ADD 12 TO ZERO GIVING APPL-RESULT` | — | flusso: aritmetica su un codice interno, nessun effetto osservabile |

### `9999-ABEND-PROGRAM` (righe 406-410) → `Cbact01c.fineAnomala(...)` e `FineAnomala`

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 407 | `DISPLAY 'ABENDING PROGRAM'` | ultima riga di console della fine anomala | tradotto, testo identico |
| 408-409 | `MOVE 0 TO TIMING`, `MOVE 999 TO ABCODE` | — | **escluso**: argomenti di `CEE3ABD` |
| 410 | `CALL 'CEE3ABD' USING ABCODE, TIMING` | il passo termina con `FineAnomala`; `EsitoReadacct` dà il codice di uscita 99; i tre file di uscita sono cancellati (`DISP=(NEW,CATLG,DELETE)`) | tradotto (sezioni "Errori" e "Codice di uscita") |

### `9910-DISPLAY-IO-STATUS` (righe 413-426)

| Riga | Istruzione | Java | Esito |
| --- | --- | --- | --- |
| 413-426 | decodifica dello stato di file e `DISPLAY 'FILE STATUS IS: NNNN' IO-STATUS-04` (420, 424) | nessuna | **escluso**: il nuovo sistema non ha gli stati di file del COBOL, quindi le righe `FILE STATUS IS: NNNN…` non si riproducono (decisione della specifica di #67). Il dettaglio tecnico dell'errore Java va sullo standard error |

## Byte che il sorgente non determina: una sola convenzione

Dove l'originale scrive byte che nessuna sua istruzione determina, il Java scrive il byte convenzionale `X'00'`. **È una convenzione del progetto, non un comportamento dell'originale**: su z/OS quei byte sono imprevedibili, e chi legge il campo non deve scambiarli per dati.

| Caso | File e posizioni | Perché il sorgente non li determina | Java |
| --- | --- | --- | --- |
| a | `OUTFILE`, byte 77-78 di ogni record (ultimi due di `OUT-ACCT-REISSUE-DATE`) | `CODATECN-0UT-DATE` è `X(20)` senza `VALUE` (`CODATECN.cpy:39`); `COBDATFT` ne scrive i primi 8 byte (`COBDATFT.asm:51-53`); il programma ne copia 10 (riga 233). IBM: il valore iniziale senza `VALUE` è imprevedibile. Il test di parità li maschera (`esclusioni.tsv`) | `00 00` |
| b | `OUTFILE`, byte 91-97 (`OUT-ACCT-CURR-CYC-DEBIT`) quando l'addebito di ciclo del conto è diverso da zero | righe 236-238: il `MOVE` è saltato e resta ciò che l'area del record conteneva; IBM non lo definisce (area del record dopo `WRITE`). I dati di esempio non hanno conti in questa condizione | `00`×7. Il programma **prosegue** come l'originale: scrive il record, la tabella, i due record variabili, la riga `DISPLAY ACCOUNT-RECORD`, e passa al conto successivo (decisione delegata della specifica). Sette byte a zero non sono un numero `COMP-3` valido: è voluto |

## Console

Standard output: una riga per ogni `DISPLAY`, nell'ordine dell'originale, terminata da LF; i byte sono quelli dei campi (profilo `oracle-gnucobol` di #54). Nessuna altra riga: banner disattivato, log sullo standard error (`logging.config` del batch).

- **Righe di classe a** (testi e campi senza segno: righe 141, 158, 201, 202, 206-208, 211, 212, 283): identiche al riferimento di #55.
- **Numerici con segno** (righe 203-205, 209, 210 e i due importi dentro `VBRC-REC2`, riga 284): il campo si stampa come sequenza dei suoi 12 byte, con il segno sovrapposto all'ultima cifra e la virgola implicita (per esempio `-1234.57` → `00000012345P`). È la forma documentata da IBM per `DISPSIGN(COMPAT)`, l'opzione predefinita. **Non è confrontata dal test di parità** (GnuCOBOL stampa un'altra forma: `000000123457-`); la verificano i test del modulo `batch`.
- **`DISPLAY` di gruppo** (`VBRC-REC1`, `VBRC-REC2`, `ACCOUNT-RECORD`): i byte del gruppo su una riga sola. `DISPLAY ACCOUNT-RECORD` (riga 151) dà i 300 byte del record ricomposto dai valori della riga con la codifica di #54 e i 178 spazi del `FILLER`. **La suddivisione che z/OS farebbe per un operando più lungo del record del dispositivo non è riprodotta.**

## Ordine degli effetti, per ogni conto

Come nel sorgente (righe 149-151, 170-178, 283-305): le undici righe dei campi e la riga di trattini; scrittura di `OUTFILE`; scrittura di `ARRYFILE`; le righe `VBRC-REC1:` e `VBRC-REC2:`; scrittura dei due record variabili; e solo dopo la riga del `DISPLAY ACCOUNT-RECORD`. Un guasto a metà lascia sulla console esattamente il prefisso corrispondente, seguito dalle righe del ramo d'errore.

## Apertura, chiusura, fine

1. `predel()`: cancella i tre file di uscita se esistono (`READACCT.jcl:22-28`), prima di accedere ai conti.
2. `START OF EXECUTION OF PROGRAM CBACT01C`.
3. `p0000AcctfileOpen()`, poi creazione dei tre file (`p2000`, `p3000`, `p4000`), ciascuno nuovo (`CREATE_NEW`, come `DISP=NEW`).
4. Ciclo dei conti.
5. `p9000AcctfileClose()`, poi `END OF EXECUTION OF PROGRAM CBACT01C`.
6. Solo dopo, svuotamento e chiusura dei tre file (nell'originale chiusi implicitamente alla fine dell'esecuzione: il programma chiude esplicitamente solo `ACCTFILE`).

## Errori

Il nuovo sistema non ha gli stati di file del COBOL: le righe `FILE STATUS IS: NNNN…` di `9910-DISPLAY-IO-STATUS` e i valori di stato **non si riproducono**. Si riproducono il messaggio letterale del ramo e l'arresto. Il dettaglio tecnico dell'errore Java va sullo standard error.

| Fase Java | Ramo del sorgente | Righe sulla console, nell'ordine |
| --- | --- | --- |
| errore nell'aprire l'accesso ai conti (connessione, prima interrogazione) | `0000-ACCTFILE-OPEN` (riga 328) | `ERROR OPENING ACCTFILE`, `ABENDING PROGRAM` |
| errore nell'avanzare la lettura (cursore, lettura e conversione della riga in `RecordConto`) | `1000-ACCTFILE-GET-NEXT` (riga 192) | `ERROR READING ACCOUNT FILE`, `ABENDING PROGRAM` |
| errore nel creare `OUTFILE` / `ARRYFILE` / `VBRCFILE` | `2000`/`3000`/`4000-…-OPEN` (righe 345, 363, 381) | `ERROR OPENING OUTFILE` / `ERROR OPENING ARRAYFILE` / `ERROR OPENING VBRC FILE`, `ABENDING PROGRAM` |
| errore nello scrivere un record | `1350`/`1450`/`1550`/`1575` (righe 246, 268, 294, 309) | `ACCOUNT FILE WRITE STATUS IS:` (senza stato), `ABENDING PROGRAM` |
| errore nel chiudere l'accesso ai conti | `9000-ACCTFILE-CLOSE` (riga 399) | `ERROR CLOSING ACCOUNT FILE`, `ABENDING PROGRAM` |
| errore nello svuotare o chiudere un file di uscita dopo `END OF EXECUTION…` | chiusura implicita (riga 160) | nessuna riga in più |

In tutti i casi: codice di uscita 99 e **nessuno dei tre file di uscita resta**, né parziale né di una corsa precedente (`DISP=(NEW,CATLG,DELETE)`, `READACCT.jcl:37-47`, dopo `PREDEL`). La conversione di una riga in valori del record (`RecordConto`) fa parte della lettura: l'equivalente COBOL è la `READ … INTO` della riga 166.

## Codice di uscita

| Codice | Quando |
| --- | --- |
| 0 | fine regolare (`GOBACK`, riga 160) |
| 99 | fine anomala del programma (`9999-ABEND-PROGRAM`, `CEE3ABD` con `ABCODE` 999): uno solo per tutti i rami della tabella "Errori". È lo stesso codice con cui termina lo stub `CEE3ABD` dell'oracle (`oracle/stubs/CEE3ABD.cbl`) |
| altro (1) | errore di avvio dell'applicazione prima del job (database irraggiungibile all'avvio, migrazione rifiutata, parametri del job mancanti): non è una fine del programma |

## Riesecuzione

Due avvii consecutivi con lo stesso comando riescono entrambi: `ParametriDiAvvio` (la conversione degli argomenti usata dal selettore dei job di Spring Boot) aggiunge a ogni avvio con parametri un parametro identificativo `menb.avvio` con un valore nuovo, quindi ogni avvio è una nuova istanza nel repository di Spring Batch; e `predel()` cancella i file della corsa precedente prima di crearli di nuovo. Nessuna idempotenza in più: il secondo avvio rifà tutto.

Correzione rispetto alla prima versione di questo documento, scritta prima del codice: prevedeva un incrementatore sul job (`RunIdIncrementer`). Alla prima prova, in Spring Batch 6.1 `JobOperator.start` di un job con incrementatore scarta i parametri passati (il job partiva con il solo `run.id`, senza `OUTFILE`, `ARRYFILE`, `VBRCFILE`, e il controllo dei parametri lo rifiutava): da qui `ParametriDiAvvio`.
