**BOCCIATA**

Ho riprodotto due falsi verdi usando cb2xml reale e lasciando intatto il legacy: un contratto accorciato da 130 a 87 byte e un contratto completamente omesso superano entrambi il `--check` completo. Nei contratti consegnati, i campi che ho verificato manualmente coincidono invece con il sorgente.

Validato HEAD `46bc43d4605c90802fee555d52676c7fcb250e31`. Tutte le mutazioni sono state ripristinate. Nessun commit o push.

Le prove eseguite sono queste; i tempi indicano la durata dei comandi, non della lettura manuale.

| Criterio/prova | Comando eseguito da me | Esito osservato | Durata |
|---|---|---|---:|
| Perimetro | `git diff --name-only origin/main...HEAD`, confronto con elenco e prefissi ammessi | 254 file; elenco identico; tutti nelle due cartelle ammesse | 0,056 s |
| Script presenti ed eseguibili | Verifica di `run.sh`, `check.sh`, `deps` | Tutti presenti, modo 755 | 0,032 s |
| Controllo della PR intatta | `./analysis/run.sh data-contract --check` — timeout 900 s | **0**; 80 XML, 57 contratti; prove negative interne superate | 121,186 s |
| Tutte le analisi | `./analysis/run.sh --all --check` — timeout 1200 s | **0**; manifest, selftest, tools, data-contract | 364,976 s |
| Campi ricalcolati dal sorgente | `python3 <file locale>/manual.py` | 87 campi elementari in otto strutture: nessuna differenza | 0,035 s |
| Censimento indipendente | `python3 -`, enumerazione di `app/cpy` e scansione dei batch | 30 copybook, 49 FD; tutte presenti | 0,049 s |
| Radici delle FD | `python3 -`, confronto delle dichiarazioni `01`/`COPY` con il censimento | Tutte corrispondenti | 0,076 s |
| Confini dei frammenti attuali | `python3 -`, scansione oltre ogni fine dichiarata fino alla radice/sezione seguente | Nessun campo finale omesso nei 50 frammenti consegnati | 0,053 s |
| Dati reali | `python3 -`, primo record tagliato secondo i TSV | Quattro file esaminati; dettagli sotto | 0,035 s |
| Stato finale | `git status --porcelain`, diff normale/staged, diff e stato del submodule | File tracciati ripristinati; legacy pulito; HEAD invariato | 0,278 s |

`git status` **non è letteralmente vuoto**: prima delle prove, dopo entrambi i controlli e alla fine mostra soltanto `?? .validazione/`, già presente all’avvio. Nessuna modifica prodotta dai controlli è rimasta.

Log integrali dei controlli iniziali: data-contract (file locale del Validatore, non conservato), tutte le analisi (file locale del Validatore, non conservato).

Per le sette mutazioni seguenti ho eseguito ogni volta `./analysis/run.sh data-contract --check`, con timeout di 240 s, ripristinando il file dopo ciascuna prova.

| Mutazione mia | Esito osservato | Durata |
|---|---|---:|
| CVCUS01Y: data di nascita da offset 308 a 309 | **1**, differenza dalla rigenerazione | 28,365 s |
| CVTRA06Y: scala dell’importo da 2 a 3 | **1** | 17,223 s |
| CVTRA05Y: segno dell’importo tolto | **1** | 21,262 s |
| CBIMPORT: FILLER interno a offset 26 eliminato; posizioni successive ricompattate; totale 129 | **1** | 35,876 s |
| CARDDATA: chiave primaria allungata da 16 a 17 byte | **1** | 53,276 s |
| XML intermedio COCOM01Y: posizione di `CDEMO-LAST-MAP` aumentata di uno | **1** | 37,290 s |
| `fonti/voci.tsv`: PIC dell’importo CVTRA06Y cambiata coerentemente a scala 3 | **1** | 35,073 s |

Ho poi alterato gli ingressi dichiarativi della rigenerazione, senza sostituire strumenti né falsificarne gli output:

| Prova | Comandi eseguiti | Esito osservato | Durata |
|---|---|---|---:|
| Frammento CBIMPORT `152-160` accorciato a `152-159`; lunghezza della relazione aggiornata a 87 | `./analysis/run.sh data-contract` — timeout 240 s | **0**; generato contratto errato di 87 byte, senza FILLER finale | 54,266 s |
| Controllo del risultato precedente | `./analysis/run.sh data-contract --check` — timeout 360 s | **0: falso verde**, comprese le prove negative interne | 92,396 s |
| `WS-VALIDATION-TRAILER` eliminato da censimento e relazioni | `./analysis/run.sh data-contract` — timeout 240 s | **0**; contratto eliminato, totale ridotto a 56 | 17,551 s |
| Controllo del risultato precedente | `./analysis/run.sh data-contract --check` — timeout 360 s | **0: falso verde**, comprese le prove negative interne | 61,281 s |

Prove riproducibili: script delle sette mutazioni (file locale del Validatore, non conservato), frammento accorciato (file locale del Validatore, non conservato), radice omessa (file locale del Validatore, non conservato). Log dei falsi verdi: frammento (file locale del Validatore, non conservato), radice (file locale del Validatore, non conservato).

Per i calcoli manuali, tutti i percorsi `app/...` sotto riportati sono relativi a `legacy/aws-mainframe-modernization-carddemo/`. La notazione è `campo @offset+byte : PIC`; gli offset sono a base zero. Tutti i campi di queste otto strutture sono **DISPLAY**:

- `X(n)`: segno assente, scala non applicabile.
- `9(n)`: segno assente, scala 0.
- `S9(09)V99`: segno `S`, scala 2; occupa 11 byte, senza byte aggiuntivo per il segno.

| Tracciato e fonte | Calcolo campo per campo dal sorgente | Confronto con contratto |
|---|---|---|
| **CVCUS01Y**, `app/cpy/CVCUS01Y.cpy:4–23` | r5 `CUST-ID @0+9 : 9(09)`<br>r6 `CUST-FIRST-NAME @9+25 : X(25)`<br>r7 `CUST-MIDDLE-NAME @34+25 : X(25)`<br>r8 `CUST-LAST-NAME @59+25 : X(25)`<br>r9 `CUST-ADDR-LINE-1 @84+50 : X(50)`<br>r10 `CUST-ADDR-LINE-2 @134+50 : X(50)`<br>r11 `CUST-ADDR-LINE-3 @184+50 : X(50)`<br>r12 `CUST-ADDR-STATE-CD @234+2 : X(02)`<br>r13 `CUST-ADDR-COUNTRY-CD @236+3 : X(03)`<br>r14 `CUST-ADDR-ZIP @239+10 : X(10)`<br>r15 `CUST-PHONE-NUM-1 @249+15 : X(15)`<br>r16 `CUST-PHONE-NUM-2 @264+15 : X(15)`<br>r17 `CUST-SSN @279+9 : 9(09)`<br>r18 `CUST-GOVT-ISSUED-ID @288+20 : X(20)`<br>r19 `CUST-DOB-YYYY-MM-DD @308+10 : X(10)`<br>r20 `CUST-EFT-ACCOUNT-ID @318+10 : X(10)`<br>r21 `CUST-PRI-CARD-HOLDER-IND @328+1 : X(01)`<br>r22 `CUST-FICO-CREDIT-SCORE @329+3 : 9(03)`<br>r23 `FILLER @332+168 : X(168)` | 19 campi, totale **500**. Nessuna differenza |
| **CVACT02Y**, `app/cpy/CVACT02Y.cpy:4–11` | r5 `CARD-NUM @0+16 : X(16)`<br>r6 `CARD-ACCT-ID @16+11 : 9(11)`<br>r7 `CARD-CVV-CD @27+3 : 9(03)`<br>r8 `CARD-EMBOSSED-NAME @30+50 : X(50)`<br>r9 `CARD-EXPIRAION-DATE @80+10 : X(10)`<br>r10 `CARD-ACTIVE-STATUS @90+1 : X(01)`<br>r11 `FILLER @91+59 : X(59)` | 7 campi, totale **150**. Nessuna differenza; nome `EXPIRAION` conservato |
| **CVTRA05Y**, `app/cpy/CVTRA05Y.cpy:4–18` | r5 `TRAN-ID @0+16 : X(16)`<br>r6 `TRAN-TYPE-CD @16+2 : X(02)`<br>r7 `TRAN-CAT-CD @18+4 : 9(04)`<br>r8 `TRAN-SOURCE @22+10 : X(10)`<br>r9 `TRAN-DESC @32+100 : X(100)`<br>r10 `TRAN-AMT @132+11 : S9(09)V99`<br>r11 `TRAN-MERCHANT-ID @143+9 : 9(09)`<br>r12 `TRAN-MERCHANT-NAME @152+50 : X(50)`<br>r13 `TRAN-MERCHANT-CITY @202+50 : X(50)`<br>r14 `TRAN-MERCHANT-ZIP @252+10 : X(10)`<br>r15 `TRAN-CARD-NUM @262+16 : X(16)`<br>r16 `TRAN-ORIG-TS @278+26 : X(26)`<br>r17 `TRAN-PROC-TS @304+26 : X(26)`<br>r18 `FILLER @330+20 : X(20)` | 14 campi, totale **350**. Nessuna differenza |
| **CVTRA06Y**, `app/cpy/CVTRA06Y.cpy:4–18` | r5 `DALYTRAN-ID @0+16 : X(16)`<br>r6 `DALYTRAN-TYPE-CD @16+2 : X(02)`<br>r7 `DALYTRAN-CAT-CD @18+4 : 9(04)`<br>r8 `DALYTRAN-SOURCE @22+10 : X(10)`<br>r9 `DALYTRAN-DESC @32+100 : X(100)`<br>r10 `DALYTRAN-AMT @132+11 : S9(09)V99`<br>r11 `DALYTRAN-MERCHANT-ID @143+9 : 9(09)`<br>r12 `DALYTRAN-MERCHANT-NAME @152+50 : X(50)`<br>r13 `DALYTRAN-MERCHANT-CITY @202+50 : X(50)`<br>r14 `DALYTRAN-MERCHANT-ZIP @252+10 : X(10)`<br>r15 `DALYTRAN-CARD-NUM @262+16 : X(16)`<br>r16 `DALYTRAN-ORIG-TS @278+26 : X(26)`<br>r17 `DALYTRAN-PROC-TS @304+26 : X(26)`<br>r18 `FILLER @330+20 : X(20)` | 14 campi, totale **350**. Nessuna differenza |
| **CSUSR01Y**, `app/cpy/CSUSR01Y.cpy:17–23` | r18 `SEC-USR-ID @0+8 : X(08)`<br>r19 `SEC-USR-FNAME @8+20 : X(20)`<br>r20 `SEC-USR-LNAME @28+20 : X(20)`<br>r21 `SEC-USR-PWD @48+8 : X(08)`<br>r22 `SEC-USR-TYPE @56+1 : X(01)`<br>r23 `SEC-USR-FILLER @57+23 : X(23)` | 6 campi, totale **80**. Nessuna differenza |
| **COCOM01Y**, `app/cpy/COCOM01Y.cpy:19–44` | r21 `CDEMO-FROM-TRANID @0+4 : X(04)`<br>r22 `CDEMO-FROM-PROGRAM @4+8 : X(08)`<br>r23 `CDEMO-TO-TRANID @12+4 : X(04)`<br>r24 `CDEMO-TO-PROGRAM @16+8 : X(08)`<br>r25 `CDEMO-USER-ID @24+8 : X(08)`<br>r26 `CDEMO-USER-TYPE @32+1 : X(01)`<br>r29 `CDEMO-PGM-CONTEXT @33+1 : 9(01)`<br>r33 `CDEMO-CUST-ID @34+9 : 9(09)`<br>r34 `CDEMO-CUST-FNAME @43+25 : X(25)`<br>r35 `CDEMO-CUST-MNAME @68+25 : X(25)`<br>r36 `CDEMO-CUST-LNAME @93+25 : X(25)`<br>r38 `CDEMO-ACCT-ID @118+11 : 9(11)`<br>r39 `CDEMO-ACCT-STATUS @129+1 : X(01)`<br>r41 `CDEMO-CARD-NUM @130+16 : 9(16)`<br>r43 `CDEMO-LAST-MAP @146+7 : X(7)`<br>r44 `CDEMO-LAST-MAPSET @153+7 : X(7)` | 16 campi, totale **160**. Gruppi: `GENERAL @0+34`, `CUSTOMER @34+84`, `ACCOUNT @118+12`, `CARD @130+16`, `MORE @146+14`. Nessuna differenza |
| **CBTRN03C.WS-DATEPARM-RECORD**, `app/cbl/CBTRN03C.cbl:122–125` | r123 `WS-START-DATE @0+10 : X(10)`<br>r124 `FILLER @10+1 : X(01)`<br>r125 `WS-END-DATE @11+10 : X(10)` | 3 campi, totale **21**. Nessuna differenza |
| **CBIMPORT.WS-ERROR-RECORD**, `app/cbl/CBIMPORT.cbl:152–160` | r153 `ERR-TIMESTAMP @0+26 : X(26)`<br>r154 `FILLER @26+1 : X(01)`<br>r155 `ERR-RECORD-TYPE @27+1 : X(01)`<br>r156 `FILLER @28+1 : X(01)`<br>r157 `ERR-SEQUENCE @29+7 : 9(07)`<br>r158 `FILLER @36+1 : X(01)`<br>r159 `ERR-MESSAGE @37+50 : X(50)`<br>r160 `FILLER @87+43 : X(43)` | 8 campi, totale **130**. Nessuna differenza nel contratto originale |

Ho controllato inoltre tre campi binari/packed di CVEXPORT, senza contarli tra i sei copybook nuovi: `EXPORT-SEQUENCE-NUM` r16, offset 27, COMP di 9 cifre = **4 byte**, senza segno, scala 0; `EXP-ACCT-CURR-BAL` r50, offset 52, COMP-3 di 12 cifre = `ceil(13/2)` = **7 byte**, segno S, scala 2; `EXP-ACCT-CURR-CYC-DEBIT` r57, offset 120, COMP di 12 cifre = **8 byte**, segno S, scala 2. Tutti coincidono.

Ho tagliato **ogni campo elementare** del primo record dei seguenti file. Il log dei tagli (file locale del Validatore, non conservato) contiene offset e valore di ciascun campo.

| File sotto `app/data/ASCII/` | Verifica sul primo record | Differenze/anomalie |
|---|---|---|
| `acctdata.txt`, 300 byte | ID `00000000001`; stato `Y`; date intere a 48, 58, 68; importi nei rispettivi 12 byte; riempimenti finali | Nessun disallineamento. ZIP `A000000000` è anomalo come dato postale, ma compatibile con X(10) |
| `carddata.txt`, 150 byte | Carta 16 byte; conto 11 cifre; CVV `747`; nome `Aniya Von`; scadenza `2023-03-09` a 80; stato `Y` a 90 | Nessuna differenza |
| `custdata.txt`, 500 byte | Nomi e indirizzi separati correttamente; `NC`/`USA`; telefoni interi; nascita `1961-06-08` a 308; indicatore `Y`; FICO `274`; filler finale | Nessun disallineamento. I numerici contengono cifre; i valori sintetici non costituiscono una validazione del dominio |
| `dailytran.txt`, 350 byte | Descrizione e commerciante coerenti; importo a 132; carta a 262; timestamp completo `2022-06-10 19:27:53.000000` a 278; timestamp di elaborazione vuoto | Nessuna differenza |

I caratteri terminali `{` negli importi del conto e `G` nell’importo giornaliero sono overpunch del segno: non sono lettere causate da uno spostamento. Le anomalie dei valori sintetici sopra indicate non rendono errato il contratto e non sono falsi verdi della PR.

Per le chiavi ho confrontato direttamente queste cinque famiglie di file:

| File | DEFINE nei JCL | SELECT/FD e copybook | LISTCAT | Risultato |
|---|---|---|---|---|
| ACCTDATA | `ACCTFILE.jcl:40`, `KEYS(11 0)` | `CBACT01C.cbl:29–33,54`; `CVACT01Y.cpy:5`: `ACCT-ID @0+11` | `LISTCAT.txt:59–60`: 11/0 | Coincide; nessun AIX definito |
| CARDDATA | `CARDFILE.jcl:54`; AIX r85–86: `KEYS(11 16) NONUNIQUEKEY` | `CBEXPORT.cbl:59–62`; `CVACT02Y.cpy:5–6`: carta `0+16`, conto `16+11` | r202–203; AIX r281–285, `AXRKP 16`, `NONUNIQKEY` | Coincide; nessuna SELECT batch alternativa dichiarata |
| CUSTDATA | `CUSTFILE.jcl:50`, `KEYS(9 0)` | `CBCUS01C.cbl:29–39`; `CVCUS01Y.cpy:5`: `CUST-ID @0+9` | r632–633: 9/0 | Coincide; differenza X/9 di CBSTM03B già documentata |
| CARDXREF | `XREFFILE.jcl:43`; AIX r74–75: `KEYS(11,25) NONUNIQUEKEY` | `CBACT04C.cbl:34–38,71–74`; `CVACT03Y.cpy:5–7`: primaria `0+16`, alternativa `25+11` | r403–404; AIX r482,486,488: 11/25 non unico | Posizioni corrette; **discordanza attesa di unicità confermata** |
| TRANSACT | `TRANFILE.jcl:53`; AIX r84–85: `KEYS(26 304) NONUNIQUEKEY` | `CBTRN02C.cbl:34–37`; `CVTRA05Y.cpy:5,17`: primaria `0+16`, timestamp `304+26` | r3593–3594; AIX r3674–3678 | Coincide; nessuna SELECT batch alternativa dichiarata |

Confermata anche la seconda discordanza attesa: `CBEXPORT.jcl:32` usa **offset 28**, mentre `EXPORT-SEQUENCE-NUM` è a **27**, lungo 4 byte (`CVEXPORT.cpy:16`), ed è richiamato dalla SELECT in `CBEXPORT.cbl:65–68`. Non ho trovato altre discordanze di chiave non documentate nei file esaminati.

Il censimento consegnato contiene tutti i 30 copybook, le loro radici e le 49 FD dei 12 programmi che ne hanno; gli altri due batch non hanno FD. Non ho trovato classificazioni palesemente errate nei casi controllati, inclusi i copybook eseguibili, CSUTLDWY senza radice 01 e le righe di report.

Il ricalcolo dalla PIC è indipendente **nell’aritmetica**: `verifica.py:48–69` calcola byte e cifre, anziché ricopiare `storage-length`. Il perimetro del confronto non è però indipendente: per i programmi, cb2xml e l’estrazione di controllo ricevono entrambi lo stesso intervallo del censimento. Il primo rilievo dimostra la conseguenza concreta.

1. **Bloccante — un frammento incompleto produce un contratto errato e passa il controllo.**  
   **Falso verde: sì. Contratto errato/incompleto: sì nella prova.**

   In `docs/legacy-map/data-contract/censimento.tsv:97` ho cambiato soltanto `152-160` in `152-159`; in `relazioni.tsv` ho aggiornato la lunghezza della struttura da 130 a 87. La rigenerazione reale elimina il FILLER `PIC X(43)` presente in `app/cbl/CBIMPORT.cbl:160`. Il `--check` completo passa con codice 0.

   `fonti.py:68–74` ritaglia il frammento; `fonti.py:362–369` ritaglia **lo stesso intervallo** per estrarre le voci di confronto. `verifica.py:197–203` controlla l’inizio e la radice, ma non che la fine comprenda tutti i subordinati dell’01. Nessuno strumento ha restituito dati falsi: è stato alimentato un sottoinsieme incompleto autentico.

   **Correzione richiesta:** ricavare o verificare indipendentemente dal programma completo i confini dell’01 e tutte le sue voci subordinate. Aggiungere una prova negativa che accorci il frammento, rigeneri i derivati coerenti e pretenda il fallimento. Diff osservato (file locale del Validatore, non conservato).

2. **Bloccante — una struttura di composizione può sparire dal censimento senza essere rilevata.**  
   **Falso verde: sì. Contratto incompleto: sì nella prova.**

   Ho eliminato la riga di `WS-VALIDATION-TRAILER` da `censimento.tsv:75` e la sua relazione da `relazioni.tsv:77`, poi rigenerato. Spariscono il relativo XML e il contratto; restano 56 contratti. Il `--check` completo passa con codice 0.

   Il sorgente resta inequivocabile: `app/cbl/CBTRN02C.cbl:180–182` definisce motivo numerico di 4 byte e descrizione di 76; r448 trasferisce questa struttura nel sotto-campo `VALIDATION-TRAILER`; r451 scrive `REJECT-RECORD`. Nel record degli scarti i due campi occupano quindi rispettivamente offset **350, lunghezza 4** e offset **354, lunghezza 76**.

   `fonti.py:197–200` censisce le MOVE soltanto quando la destinazione è direttamente una radice FD. La composizione tramite sotto-campo sfugge al controllo. La limitazione è dichiarata nella descrizione PR, ma lascia scoperto un requisito esplicito della specifica, r26.

   **Correzione richiesta:** verificare dal sorgente completo anche le MOVE di strutture verso sotto-campi dei record successivamente scritti, ricondurle alla radice destinataria e richiedere censimento e contratto della struttura sorgente. Aggiungere questa precisa prova negativa.

3. **Minore — l’estrazione testuale legge il bind mount del legacy anziché il volume prescritto.**  
   **Falso verde osservato: no. Contratto errato/incompleto osservato: no; nessuno dei due.**

   È un rilievo da **lettura del codice**, senza malfunzionamenti osservati: `.validazione/specifica.md:12` richiede il volume Docker sensibile alle maiuscole. Le chiamate a `glue_run` in `analysis/data-contract/lib.sh:46,53` usano invece il montaggio host configurato da `analysis/lib/common.sh:54`. Il volume è usato per cb2xml, non per queste estrazioni.

   **Correzione richiesta:** montare in sola lettura il volume legacy anche nelle chiamate della colla che leggono sorgenti, mantenendo invariati i file comuni fuori perimetro.