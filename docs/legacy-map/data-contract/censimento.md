# Censimento dei tracciati e contratto dati fisico (issue #3)

Questo documento dice quali descrizioni di dati contiene CardDemo (commit `59cc6c2`), quali sono tracciati di file e quali no, e dove trovare per ciascun record il **contratto fisico**: ogni campo con posizione, lunghezza, tipo COBOL, segno, scala, `REDEFINES` e `OCCURS`. È la base della Wave 1 (dati): un record che il Java legge o scrive deve avere qui il suo contratto. La verifica con record di prova e le regole di codifica dei valori (zona, impaccato, binario, segno incorporato) non sono qui: sono l'issue #23.

## Come si riproduce

```
git submodule update --init
./analysis/run.sh data-contract            # rigenera output e documenti generati (circa 10 secondi)
./analysis/run.sh data-contract --check    # rigenera tutto in una cartella temporanea, confronta, verifica, prove negative
```

Serve solo Docker. Lo strumento è cb2xml 1.01.08 (dialetto `Mainframe`), lo stesso adottato in #1 (`docs/legacy-map/strumenti.md`), usato tramite la sua immagine `menb-analysis-cb2xml:1.01.08`. La colla gira nell'immagine Python del banco di prova.

## Che cosa contiene questa cartella

| File | Chi lo scrive | Contenuto |
| --- | --- | --- |
| `censimento.tsv` | a mano | una riga per radice: copybook o programma, tipo (copybook, `FD`, `WORKING-STORAGE`, `LINKAGE`), riga dell'01, righe date a cb2xml, classificazione, contratto, motivo |
| `relazioni.tsv` | a mano | per ogni programma batch, quale struttura viene scritta in (o letta da) quale record di `FD`, con le righe delle istruzioni e le lunghezze calcolate a mano |
| `file.tsv` | a mano | per ogni `DEFINE CLUSTER` dei JCL, il contratto del suo record |
| `assegnazioni.tsv` | a mano | per ogni `SELECT` dei programmi batch, la DD del JCL, il dataset e la DCB osservata, con le righe |
| `discordanze.md` | a mano | le differenze tra le fonti, ciascuna con file e riga |
| `contratti/<contratto>.tsv` | generato | il contratto fisico di ogni radice classificata record di file o stato di conversazione |
| `contratti.tsv`, `contratti.md` | generato | indice dei contratti e vista Markdown di tutti i contratti |
| `composizioni.tsv` | generato | per ogni struttura trasferita con `MOVE` in un record, la posizione di ciascun suo campo nel record di destinazione |
| `chiavi.tsv`, `chiavi.md` | generato | chiavi primarie e alternative di ogni file, dalle quattro fonti, ricondotte ai campi |
| questo file, da "Tabelle generate" in poi | generato | censimento e relazioni con le lunghezze di cb2xml accanto a quelle scritte a mano |

L'output grezzo e intermedio è in `analysis/data-contract/out/`: gli XML e i log di cb2xml (`cb2xml/`), le fonti estratte dal testo (`fonti/`), i tracciati normalizzati (`tracciati.tsv`, `radici.tsv`) e le discordanze rilevate (`discordanze-rilevate.tsv`). Gli attesi scritti a mano per i controlli sono in `analysis/data-contract/expected/`.

## Che cosa si censisce

- **Tutti i 30 copybook di `app/cpy/`**, presi dal manifesto (`analysis/manifest/sources.tsv`), non da un glob. Per ognuno, le radici di livello 01 che contiene: un copybook può averne più d'una (`CVTRA07Y` ne ha sette, `CSLKPCDY` tre) o nessuna (`CSUTLDWY` ha voci di livello 10 e 20 da includere sotto un gruppo del programma).
- **I 14 programmi batch di `app/cbl/`**: i programmi del manifesto senza `EXEC CICS`. Dodici hanno file (49 `FD` in tutto); `COBSWAIT` e `CSUTLDTC` non ne hanno. Per ogni `FD`, il suo 01 (o la `COPY` che lo fornisce). Per ogni istruzione `READ`, `WRITE`, `REWRITE` e per ogni `MOVE` di una struttura nel record di un `FD`, la struttura da cui il record è composto prima della scrittura (`WRITE ... FROM`, `MOVE` verso il record) o in cui è letto (`READ ... INTO`); in `CBSTM03A`, anche lo spostamento dei record letti da `CBSTM03B` (area `WS-M03B-FLDT`) nei tracciati dei copybook. Le strutture di `WORKING-STORAGE` e `LINKAGE` coinvolte sono radici del censimento come gli 01 degli `FD`.
- **I trasferimenti di strutture intere verso i record scritti, anche verso una loro parte**, ricavati dal programma completo (`glue/struttura.py`): ogni `MOVE` di una voce di livello 01 o di un gruppo verso un record che finisce in un file (record di una `WRITE`/`REWRITE`, o struttura di una `WRITE`/`REWRITE ... FROM`) o verso un suo sotto-campo. Nei 12 programmi batch con file sono 14: `VBRC-REC1` e `VBRC-REC2` in `VBR-REC` (CBACT01C), `DALYTRAN-RECORD` e `WS-VALIDATION-TRAILER` nelle due parti di `REJECT-RECORD`, `DB2-FORMAT-TS` in `TRAN-PROC-TS` di `TRAN-RECORD` (CBTRN02C), le nove righe di report in `FD-REPTFILE-REC` (CBTRN03C). Rispetto alla prima consegna si aggiunge una struttura, `DB2-FORMAT-TS`; le altre erano già censite. Per ciascuno il controllo pretende la relazione e la struttura nel censimento; `composizioni.tsv` dà la posizione di ogni campo trasferito nel record (per esempio motivo dello scarto a offset 350 per 4 byte, descrizione a 354 per 76).
- **Non coperto dai trasferimenti** (elencato punto per punto in `analysis/data-contract/out/fonti/non-coperti.tsv` e riassunto in fondo a questo documento): ciò che scrive dentro un record senza trasferire una struttura intera, cioè composizione campo per campo, letterali, riferimenti con posizione nella sorgente, `STRING`, `INITIALIZE`, aritmetica. Per queste istruzioni non si chiede una relazione; il tracciato del record che le riceve ha comunque il suo contratto.
- Fuori: i copybook delle mappe (`app/cpy-bms/`), i moduli opzionali, i programmi online (le loro strutture di file vengono dai copybook, già censiti).

## Come si classifica

| Classificazione | Criterio | Contratto |
| --- | --- | --- |
| `record-di-file` | è il tracciato di un file: 01 di un `FD`, struttura scritta o letta con `FROM`/`INTO`/`MOVE`, o copybook che descrive il record di un file definito nel JCL | sì |
| `stato-di-conversazione` | area passata tra transazioni CICS (`COCOM01Y`, la COMMAREA) | sì |
| `riga-di-report` | riga di stampa o di estratto conto (importi editati, costanti di intestazione), scritta in un file di report | no |
| `area-di-lavoro` | tabelle costanti, aree di parametri, variabili di lavoro, copybook non inclusi da alcun programma | no |
| `non-tracciato` | il copybook contiene istruzioni della `PROCEDURE DIVISION` e nessuna descrizione di dati; cb2xml lo rifiuta (`CSSETATY`, `CSSTRPFY`, `CSUTLDPY`) | no |

Gli 01 "generici" degli `FD` (per esempio `FD-ACCTFILE-REC` con la sola chiave e un'area `PIC X(289)`) hanno il loro contratto, che descrive ciò che il programma vede; il tracciato vero del file è quello della struttura collegata in `relazioni.tsv` e del copybook indicato in `file.tsv`. Esempio della specifica: in `CBACT01C` il file a lunghezza variabile ha l'`FD` `VBR-REC PIC X(80)`, ma i record scritti sono `VBRC-REC1` (12 byte) e `VBRC-REC2` (39 byte), spostati in `VBR-REC(1:WS-RECD-LEN)` dopo `MOVE 12` o `MOVE 39 TO WS-RECD-LEN` (righe 288-290 e 303-305). Tutte e tre le strutture hanno un contratto.

## Come si ottengono posizioni e lunghezze

**Da cb2xml.** Per i copybook cb2xml legge il file del legacy. Per gli 01 descritti dentro un programma si copiano, verbatim, le righe dichiarate nella colonna `frammento` di `censimento.tsv` in un file temporaneo (non versionato) che cb2xml legge come un copybook. Nessun sorgente viene modificato. Le posizioni di cb2xml (da 1) sono portate a base 0; per un gruppo con `OCCURS` cb2xml dà la lunghezza del singolo elemento, e il contratto espande ogni elemento in una riga con il suo indice e l'offset `primo + (indice - 1) × lunghezza dell'elemento`.

**Calcolo a mano, come controllo.** Le tabelle attese (`analysis/data-contract/expected/`) sono state scritte leggendo il copybook e applicando queste regole, non copiando l'output di cb2xml:

- `DISPLAY`: un byte per carattere o cifra; `S` (segno incorporato nell'ultima cifra) e `V` (virgola implicita) non occupano byte; nelle PIC editate ogni simbolo occupa un byte;
- `COMP` / `BINARY`: 2 byte da 1 a 4 cifre, 4 da 5 a 9, 8 da 10 a 18;
- `COMP-3`: cifre / 2 + 1 byte (divisione intera);
- offset di un campo = somma delle lunghezze dei campi precedenti dello stesso gruppo; un'area con `REDEFINES` riparte dall'offset dell'area che ridefinisce e non si somma alla lunghezza del record.

Le stesse regole sono applicate dal controllo a **ogni** voce degli 80 input dati a cb2xml (30 copybook e 50 frammenti di programma, 763 voci gruppi compresi): per ogni voce elementare la lunghezza calcolata dalla PIC coincide con quella di cb2xml, e nomi, livelli, ordine, PIC, `USAGE`, `OCCURS` e `REDEFINES` di cb2xml coincidono con quelli letti dal testo del sorgente. **Non è emersa alcuna divergenza tra cb2xml e il calcolo a mano.**

**Confini delle strutture.** L'intervallo `frammento` di `censimento.tsv` dice quali righe si danno a cb2xml, ma non è la verità su cui si controlla: i confini di ogni radice si ricavano dal sorgente completo (`glue/struttura.py`). Una voce di livello 01 (o 77) comprende tutte le frasi che la seguono fino alla prima che sia un'altra voce 01/77, una `FD`/`SD`, una `COPY`, un'intestazione di sezione o di divisione; la sua ultima riga è l'ultima riga di codice prima di quel confine. Il controllo fallisce se l'intervallo dichiarato non coincide, se cb2xml trova per la radice un numero di voci diverso da quello del sorgente fino al confine (anche per le radici dei copybook) e se la sezione della radice non è quella del suo `tipo`. Le voci lette dal testo per il confronto con cb2xml si prendono anch'esse fino al confine ricavato, non dall'intervallo dichiarato.

**Lettura del legacy.** Tutta l'estrazione testuale e la verifica leggono il legacy dal volume Docker sensibile alle maiuscole (`menb-analysis-legacy-<commit>`), montato in sola lettura, come cb2xml.

## Colonne del contratto

`campo`, `livello`, `tipo` (`gruppo` o `elementare`), `pic` e `usage` come nel sorgente (`DISPLAY` se assente), `segno` (`S` se la PIC inizia con S), `cifre_intere` e `cifre_decimali` (scala) per i numerici non editati, `offset` (base 0) e `lunghezza` in byte, `redefines` (area ridefinita), `area` (la voce con `REDEFINES` che contiene il campo; `-` = record base), `occurs` e `indice` (elemento dell'`OCCURS`), `percorso`. I `FILLER` restano, con nomi, ordine e ampiezze del sorgente: nessuna normalizzazione.

## Record a lunghezza variabile

L'unico file a lunghezza variabile dei programmi batch è `VBRCFILE` di `CBACT01C`: `RECORDING MODE IS V`, `RECORD IS VARYING IN SIZE FROM 10 TO 80 DEPENDING ON WS-RECD-LEN` (righe 80-85). Contenuto: minimo 10 e massimo 80 byte dichiarati, campo da cui dipende `WS-RECD-LEN`; lunghezze effettivamente scritte 12 (`VBRC-REC1`) e 39 (`VBRC-REC2`). Il JCL (`READACCT.jcl` riga 47) dichiara `LRECL=84,RECFM=VB`: è annotato come dato osservato in `discordanze.md`, senza interpretarlo.

## Scelte fatte dove la specifica lasciava margine

- **`UNUSED1Y`** è classificato `area-di-lavoro` e non `record-di-file`: nessun programma lo include e non c'è un file che lo usi, anche se ha la stessa forma di `SEC-USER-DATA`.
- **`CSUTLDWY`** non ha radici di livello 01: il censimento ha una sola riga con radice `-`, classificata `area-di-lavoro`.
- **Le strutture lette con `READ ... INTO`** sono censite insieme a quelle scritte, perché sono il tracciato vero di molti file il cui `FD` è generico.
- **`WS-ERROR-RECORD` di `CBIMPORT`** e il record degli scarti di `CBTRN02C` (`REJECT-RECORD` con `WS-VALIDATION-TRAILER`) sono `record-di-file` (campi fissi in dataset catalogati); le righe di `CVTRA07Y` e dell'estratto conto di `CBSTM03A` sono `riga-di-report`.
- **`AWS.CUSTDATA.CLUSTER`** (`DEFCUST.jcl`), che nessun programma usa, è associato al tracciato cliente sulla base del solo `RECORDSIZE(500 500)` (vedi `file.tsv` e `discordanze.md`).
- **`CBTRN01C`** non è eseguito da alcun JCL: le sue `SELECT` non sono ricondotte a un dataset.
- **`DB2-FORMAT-TS` di `CBTRN02C`** (riga 159, `PIC X(26)`) è `record-di-file`: è spostato intero nel timestamp di elaborazione `TRAN-PROC-TS` del record delle transazioni (riga 438), che è anche la chiave dell'indice alternativo di `TRANSACT`. La sua forma interna è data dalla `01 FILLER REDEFINES DB2-FORMAT-TS` (righe 160-174), composta campo per campo in `Z-GET-DB2-FORMAT-TIMESTAMP` (righe 692-703): `AAAA-MM-GG-hh.mm.ss.cc0000` (anno, `-`, mese, `-`, giorno, `-`, ora, `.`, minuti, `.`, secondi, `.`, centesimi, `0000`). Quella `FILLER` non ha un contratto proprio, perché è una ridefinizione anonima che nessuna istruzione trasferisce: è un limite dichiarato.

## Ingressi scritti a mano e come sono verificati

| Ingresso | Verifica contro il sorgente |
| --- | --- |
| `censimento.tsv`: radici e righe | radici 01 dei copybook uguali a quelle di cb2xml; 01 delle `FD` uguali all'estrazione dal programma; riga dell'01 letta nel sorgente |
| `censimento.tsv`: intervalli dei frammenti, tipo | confini e sezione ricavati dal sorgente completo; numero di voci di cb2xml uguale a quello del sorgente fino al confine |
| `censimento.tsv`: presenza delle strutture di lavoro | ogni `READ`/`WRITE`/`REWRITE` e ogni trasferimento di struttura intera verso un record scritto deve avere relazione e struttura censita |
| `censimento.tsv`: classificazione | **giudizio dichiarato**, con motivo; vincolato solo in parte: `non-tracciato` se e solo se cb2xml non trova dati, record o riga di report se letta o scritta in un file |
| `relazioni.tsv` | righe e nomi letti nel sorgente; lunghezze uguali a cb2xml; byte trasferiti dalla regola dell'`FD` o dalla `MOVE` della lunghezza variabile |
| `assegnazioni.tsv` | righe della DD, del DSN e della DCB lette nel JCL; ogni `SELECT` presente una volta |
| `file.tsv` | ogni `DEFINE CLUSTER` presente; il contratto deve essere quello con cui i programmi assegnati al dataset leggono o scrivono il record (10 dataset su 15); per i 5 senza evidenza nei programmi batch (`AWS.CUSTDATA.CLUSTER`; `USRSEC` KSDS, ESDS e RRDS, usati solo online; `TRXFL`, che CBSTM03B legge in un'area di 1000 byte) restano solo il controllo di lunghezza con `RECORDSIZE` e la chiave attesa |
| `discordanze.md` | ogni differenza rilevata dal confronto automatico delle fonti deve esserci, e nessuna che non lo sia |
| attesi di `analysis/data-contract/expected/` | **scritti a mano** dal copybook; contenuto minimo fissato dai criteri di accettazione |

<!-- Da qui in poi il testo e' generato da analysis/data-contract (contratti.py): non modificarlo a mano. -->

## Tabelle generate

### Copybook di `app/cpy/`: radici trovate da cb2xml e classificazione

| copybook | radice | riga | byte (cb2xml) | classificazione | contratto | motivo |
| --- | --- | --- | --- | --- | --- | --- |
| COADM02Y.cpy | CARDDEMO-ADMIN-MENU-OPTIONS | 19 | 407 | area-di-lavoro | - | tabella costante delle opzioni del menu amministratore (VALUE) esposta con REDEFINES e OCCURS; nessun file la legge o la scrive |
| COCOM01Y.cpy | CARDDEMO-COMMAREA | 19 | 160 | stato-di-conversazione | `COCOM01Y.CARDDEMO-COMMAREA` | COMMAREA passata tra le transazioni CICS (stato pseudo-conversazionale: utente, programma chiamante, contesto ENTER/REENTER) |
| CODATECN.cpy | CODATECN-REC | 17 | 80 | area-di-lavoro | - | area dei parametri di conversione di data passata con CALL a COBDATFT (CBACT01C); non e' un record di file |
| COMEN02Y.cpy | CARDDEMO-MAIN-MENU-OPTIONS | 19 | 554 | area-di-lavoro | - | tabella costante delle opzioni del menu principale (VALUE) esposta con REDEFINES e OCCURS; nessun file la legge o la scrive |
| COSTM01.CPY | TRNX-RECORD | 20 | 350 | record-di-file | `COSTM01.TRNX-RECORD` | tracciato del file TRXFL (chiave carta+transazione, KEYS(32 0) in CREASTMT.JCL) letto da CBSTM03B per CBSTM03A |
| COTTL01Y.cpy | CCDA-SCREEN-TITLE | 17 | 120 | area-di-lavoro | - | costanti dei titoli delle schermate |
| CSDAT01Y.cpy | WS-DATE-TIME | 17 | 58 | area-di-lavoro | - | area di lavoro per data e ora correnti e loro formati |
| CSLKPCDY.cpy | WS-US-PHONE-AREA-CODE-TO-EDIT | 24 | 3 | area-di-lavoro | - | campo di lavoro con tabella di validazione (88 con i prefissi telefonici validi) |
| CSLKPCDY.cpy | US-STATE-CODE-TO-EDIT | 1012 | 2 | area-di-lavoro | - | campo di lavoro con tabella di validazione (88 con i codici di stato validi) |
| CSLKPCDY.cpy | US-STATE-ZIPCODE-TO-EDIT | 1071 | 7 | area-di-lavoro | - | campo di lavoro con tabella di validazione (88 con le combinazioni stato/CAP valide) |
| CSMSG01Y.cpy | CCDA-COMMON-MESSAGES | 17 | 100 | area-di-lavoro | - | costanti dei messaggi comuni |
| CSMSG02Y.cpy | ABEND-DATA | 21 | 134 | area-di-lavoro | - | area di lavoro della routine di abend (codice, programma, motivo, messaggio) |
| CSSETATY.cpy | - | - | - | non-tracciato | - | contiene istruzioni della PROCEDURE DIVISION (IF/MOVE con segnaposto per REPLACING), nessuna descrizione di dati |
| CSSTRPFY.cpy | - | - | - | non-tracciato | - | contiene un paragrafo della PROCEDURE DIVISION (YYYY-STORE-PFKEY: EVALUATE su EIBAID), nessuna descrizione di dati |
| CSUSR01Y.cpy | SEC-USER-DATA | 17 | 80 | record-di-file | `CSUSR01Y.SEC-USER-DATA` | tracciato del file utenti USRSEC (KSDS, KEYS(8,0) RECORDSIZE(80,80) in DUSRSECJ.jcl) letto e scritto dai programmi online |
| CSUTLDPY.cpy | - | - | - | non-tracciato | - | contiene paragrafi della PROCEDURE DIVISION (EDIT-DATE-CCYYMMDD e seguenti), nessuna descrizione di dati |
| CSUTLDWY.cpy | - | - | - | area-di-lavoro | - | nessuna radice di livello 01: voci di livello 10 e 20 da includere sotto un gruppo del programma che lo copia (area di lavoro per la validazione delle date) |
| CUSTREC.cpy | CUSTOMER-RECORD | 4 | 500 | record-di-file | `CUSTREC.CUSTOMER-RECORD` | tracciato cliente (RECLN 500) usato da CBSTM03A per il file CUSTDATA; variante di CVCUS01Y con CUST-DOB-YYYYMMDD e caratteri TAB nelle righe 6-22 |
| CVACT01Y.cpy | ACCOUNT-RECORD | 4 | 300 | record-di-file | `CVACT01Y.ACCOUNT-RECORD` | tracciato del file conti ACCTDATA (KEYS(11 0) RECORDSIZE(300 300) in ACCTFILE.jcl) |
| CVACT02Y.cpy | CARD-RECORD | 4 | 150 | record-di-file | `CVACT02Y.CARD-RECORD` | tracciato del file carte CARDDATA (KEYS(16 0) RECORDSIZE(150 150) in CARDFILE.jcl) |
| CVACT03Y.cpy | CARD-XREF-RECORD | 4 | 50 | record-di-file | `CVACT03Y.CARD-XREF-RECORD` | tracciato del file di riferimento incrociato CARDXREF (KEYS(16 0) RECORDSIZE(50 50) in XREFFILE.jcl) |
| CVCRD01Y.cpy | CC-WORK-AREAS | 1 | 213 | area-di-lavoro | - | area di lavoro dei programmi online (tasto premuto, programma e mappa successivi, messaggi) |
| CVCUS01Y.cpy | CUSTOMER-RECORD | 4 | 500 | record-di-file | `CVCUS01Y.CUSTOMER-RECORD` | tracciato del file clienti CUSTDATA (KEYS(9 0) RECORDSIZE(500 500) in CUSTFILE.jcl) |
| CVEXPORT.cpy | EXPORT-RECORD | 9 | 500 | record-di-file | `CVEXPORT.EXPORT-RECORD` | tracciato a piu' tipi del file di export (RECORDSIZE(500 500) in CBEXPORT.jcl), scritto da CBEXPORT e letto da CBIMPORT |
| CVTRA01Y.cpy | TRAN-CAT-BAL-RECORD | 4 | 50 | record-di-file | `CVTRA01Y.TRAN-CAT-BAL-RECORD` | tracciato del file saldi per categoria TCATBALF (KEYS(17 0) RECORDSIZE(50 50) in TCATBALF.jcl) |
| CVTRA02Y.cpy | DIS-GROUP-RECORD | 4 | 50 | record-di-file | `CVTRA02Y.DIS-GROUP-RECORD` | tracciato del file gruppi di tasso DISCGRP (KEYS(16 0) RECORDSIZE(50 50) in DISCGRP.jcl) |
| CVTRA03Y.cpy | TRAN-TYPE-RECORD | 4 | 60 | record-di-file | `CVTRA03Y.TRAN-TYPE-RECORD` | tracciato del file tipi di transazione TRANTYPE (KEYS(2 0) RECORDSIZE(60 60) in TRANTYPE.jcl) |
| CVTRA04Y.cpy | TRAN-CAT-RECORD | 4 | 60 | record-di-file | `CVTRA04Y.TRAN-CAT-RECORD` | tracciato del file categorie TRANCATG (KEYS(6 0) RECORDSIZE(60 60) in TRANCATG.jcl) |
| CVTRA05Y.cpy | TRAN-RECORD | 4 | 350 | record-di-file | `CVTRA05Y.TRAN-RECORD` | tracciato del file transazioni TRANSACT (KEYS(16 0) RECORDSIZE(350 350) in TRANFILE.jcl) |
| CVTRA06Y.cpy | DALYTRAN-RECORD | 4 | 350 | record-di-file | `CVTRA06Y.DALYTRAN-RECORD` | tracciato del file sequenziale delle transazioni giornaliere DALYTRAN letto da CBTRN01C e CBTRN02C |
| CVTRA07Y.cpy | REPORT-NAME-HEADER | 4 | 115 | riga-di-report | - | intestazione del report giornaliero, spostata in FD-REPTFILE-REC da CBTRN03C |
| CVTRA07Y.cpy | TRANSACTION-DETAIL-REPORT | 15 | 114 | riga-di-report | - | riga di dettaglio del report (importo editato), spostata in FD-REPTFILE-REC da CBTRN03C |
| CVTRA07Y.cpy | TRANSACTION-HEADER-1 | 33 | 114 | riga-di-report | - | riga di intestazione delle colonne del report |
| CVTRA07Y.cpy | TRANSACTION-HEADER-2 | 48 | 133 | riga-di-report | - | riga di separazione del report (133 trattini) |
| CVTRA07Y.cpy | REPORT-PAGE-TOTALS | 50 | 112 | riga-di-report | - | riga dei totali di pagina (importo editato) |
| CVTRA07Y.cpy | REPORT-ACCOUNT-TOTALS | 56 | 112 | riga-di-report | - | riga dei totali di conto (importo editato) |
| CVTRA07Y.cpy | REPORT-GRAND-TOTALS | 62 | 112 | riga-di-report | - | riga del totale generale (importo editato) |
| UNUSED1Y.cpy | UNUSED-DATA | 1 | 80 | area-di-lavoro | - | nessun programma del repository lo include (nessuna COPY UNUSED1Y); stessa forma di SEC-USER-DATA ma senza un file associato |

### Programmi batch: FD e strutture di lavoro

| programma | tipo | radice | riga | righe date a cb2xml | byte (cb2xml) | classificazione | contratto |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CBACT01C.cbl | FD:ACCTFILE-FILE | FD-ACCTFILE-REC | 53 | 53-55 | 300 | record-di-file | `CBACT01C.FD-ACCTFILE-REC` |
| CBACT01C.cbl | FD:OUT-FILE | OUT-ACCT-REC | 57 | 57-69 | 107 | record-di-file | `CBACT01C.OUT-ACCT-REC` |
| CBACT01C.cbl | FD:ARRY-FILE | ARR-ARRAY-REC | 72 | 72-78 | 110 | record-di-file | `CBACT01C.ARR-ARRAY-REC` |
| CBACT01C.cbl | FD:VBRC-FILE | VBR-REC | 85 | 85-85 | 80 | record-di-file | `CBACT01C.VBR-REC` |
| CBACT01C.cbl | WORKING-STORAGE | VBRC-REC1 | 123 | 123-125 | 12 | record-di-file | `CBACT01C.VBRC-REC1` |
| CBACT01C.cbl | WORKING-STORAGE | VBRC-REC2 | 126 | 126-130 | 39 | record-di-file | `CBACT01C.VBRC-REC2` |
| CBACT02C.cbl | FD:CARDFILE-FILE | FD-CARDFILE-REC | 38 | 38-40 | 150 | record-di-file | `CBACT02C.FD-CARDFILE-REC` |
| CBACT03C.cbl | FD:XREFFILE-FILE | FD-XREFFILE-REC | 38 | 38-40 | 50 | record-di-file | `CBACT03C.FD-XREFFILE-REC` |
| CBCUS01C.cbl | FD:CUSTFILE-FILE | FD-CUSTFILE-REC | 38 | 38-40 | 500 | record-di-file | `CBCUS01C.FD-CUSTFILE-REC` |
| CBACT04C.cbl | FD:TCATBAL-FILE | FD-TRAN-CAT-BAL-RECORD | 62 | 62-67 | 50 | record-di-file | `CBACT04C.FD-TRAN-CAT-BAL-RECORD` |
| CBACT04C.cbl | FD:XREF-FILE | FD-XREFFILE-REC | 70 | 70-74 | 50 | record-di-file | `CBACT04C.FD-XREFFILE-REC` |
| CBACT04C.cbl | FD:DISCGRP-FILE | FD-DISCGRP-REC | 77 | 77-82 | 50 | record-di-file | `CBACT04C.FD-DISCGRP-REC` |
| CBACT04C.cbl | FD:ACCOUNT-FILE | FD-ACCTFILE-REC | 85 | 85-87 | 300 | record-di-file | `CBACT04C.FD-ACCTFILE-REC` |
| CBACT04C.cbl | FD:TRANSACT-FILE | FD-TRANFILE-REC | 90 | 90-92 | 350 | record-di-file | `CBACT04C.FD-TRANFILE-REC` |
| CBTRN01C.cbl | FD:DALYTRAN-FILE | FD-TRAN-RECORD | 67 | 67-69 | 350 | record-di-file | `CBTRN01C.FD-TRAN-RECORD` |
| CBTRN01C.cbl | FD:CUSTOMER-FILE | FD-CUSTFILE-REC | 72 | 72-74 | 500 | record-di-file | `CBTRN01C.FD-CUSTFILE-REC` |
| CBTRN01C.cbl | FD:XREF-FILE | FD-XREFFILE-REC | 77 | 77-79 | 50 | record-di-file | `CBTRN01C.FD-XREFFILE-REC` |
| CBTRN01C.cbl | FD:CARD-FILE | FD-CARDFILE-REC | 82 | 82-84 | 150 | record-di-file | `CBTRN01C.FD-CARDFILE-REC` |
| CBTRN01C.cbl | FD:ACCOUNT-FILE | FD-ACCTFILE-REC | 87 | 87-89 | 300 | record-di-file | `CBTRN01C.FD-ACCTFILE-REC` |
| CBTRN01C.cbl | FD:TRANSACT-FILE | FD-TRANFILE-REC | 92 | 92-94 | 350 | record-di-file | `CBTRN01C.FD-TRANFILE-REC` |
| CBTRN02C.cbl | FD:DALYTRAN-FILE | FD-TRAN-RECORD | 67 | 67-69 | 350 | record-di-file | `CBTRN02C.FD-TRAN-RECORD` |
| CBTRN02C.cbl | FD:TRANSACT-FILE | FD-TRANFILE-REC | 72 | 72-74 | 350 | record-di-file | `CBTRN02C.FD-TRANFILE-REC` |
| CBTRN02C.cbl | FD:XREF-FILE | FD-XREFFILE-REC | 77 | 77-79 | 50 | record-di-file | `CBTRN02C.FD-XREFFILE-REC` |
| CBTRN02C.cbl | FD:DALYREJS-FILE | FD-REJS-RECORD | 82 | 82-84 | 430 | record-di-file | `CBTRN02C.FD-REJS-RECORD` |
| CBTRN02C.cbl | FD:ACCOUNT-FILE | FD-ACCTFILE-REC | 87 | 87-89 | 300 | record-di-file | `CBTRN02C.FD-ACCTFILE-REC` |
| CBTRN02C.cbl | FD:TCATBAL-FILE | FD-TRAN-CAT-BAL-RECORD | 92 | 92-97 | 50 | record-di-file | `CBTRN02C.FD-TRAN-CAT-BAL-RECORD` |
| CBTRN02C.cbl | WORKING-STORAGE | DB2-FORMAT-TS | 159 | 159-159 | 26 | record-di-file | `CBTRN02C.DB2-FORMAT-TS` |
| CBTRN02C.cbl | WORKING-STORAGE | REJECT-RECORD | 176 | 176-178 | 430 | record-di-file | `CBTRN02C.REJECT-RECORD` |
| CBTRN02C.cbl | WORKING-STORAGE | WS-VALIDATION-TRAILER | 180 | 180-182 | 80 | record-di-file | `CBTRN02C.WS-VALIDATION-TRAILER` |
| CBTRN03C.cbl | FD:TRANSACT-FILE | FD-TRANFILE-REC | 62 | 62-65 | 350 | record-di-file | `CBTRN03C.FD-TRANFILE-REC` |
| CBTRN03C.cbl | FD:XREF-FILE | FD-CARDXREF-REC | 68 | 68-70 | 50 | record-di-file | `CBTRN03C.FD-CARDXREF-REC` |
| CBTRN03C.cbl | FD:TRANTYPE-FILE | FD-TRANTYPE-REC | 73 | 73-75 | 60 | record-di-file | `CBTRN03C.FD-TRANTYPE-REC` |
| CBTRN03C.cbl | FD:TRANCATG-FILE | FD-TRAN-CAT-RECORD | 78 | 78-82 | 60 | record-di-file | `CBTRN03C.FD-TRAN-CAT-RECORD` |
| CBTRN03C.cbl | FD:REPORT-FILE | FD-REPTFILE-REC | 85 | 85-85 | 133 | riga-di-report | - |
| CBTRN03C.cbl | FD:DATE-PARMS-FILE | FD-DATEPARM-REC | 88 | 88-88 | 80 | record-di-file | `CBTRN03C.FD-DATEPARM-REC` |
| CBTRN03C.cbl | WORKING-STORAGE | WS-DATEPARM-RECORD | 122 | 122-125 | 21 | record-di-file | `CBTRN03C.WS-DATEPARM-RECORD` |
| CBTRN03C.cbl | WORKING-STORAGE | WS-REPORT-VARS | 127 | 127-137 | 190 | area-di-lavoro | - |
| CBEXPORT.cbl | FD:CUSTOMER-INPUT | CUSTOMER-RECORD | 75 | COPY CVCUS01Y | 500 | record-di-file | `CVCUS01Y.CUSTOMER-RECORD` |
| CBEXPORT.cbl | FD:ACCOUNT-INPUT | ACCOUNT-RECORD | 78 | COPY CVACT01Y | 300 | record-di-file | `CVACT01Y.ACCOUNT-RECORD` |
| CBEXPORT.cbl | FD:XREF-INPUT | CARD-XREF-RECORD | 81 | COPY CVACT03Y | 50 | record-di-file | `CVACT03Y.CARD-XREF-RECORD` |
| CBEXPORT.cbl | FD:TRANSACTION-INPUT | TRAN-RECORD | 84 | COPY CVTRA05Y | 350 | record-di-file | `CVTRA05Y.TRAN-RECORD` |
| CBEXPORT.cbl | FD:CARD-INPUT | CARD-RECORD | 87 | COPY CVACT02Y | 150 | record-di-file | `CVACT02Y.CARD-RECORD` |
| CBEXPORT.cbl | FD:EXPORT-OUTPUT | EXPORT-OUTPUT-RECORD | 92 | 92-92 | 500 | record-di-file | `CBEXPORT.EXPORT-OUTPUT-RECORD` |
| CBIMPORT.cbl | FD:EXPORT-INPUT | EXPORT-INPUT-RECORD | 79 | 79-79 | 500 | record-di-file | `CBIMPORT.EXPORT-INPUT-RECORD` |
| CBIMPORT.cbl | FD:CUSTOMER-OUTPUT | CUSTOMER-RECORD | 84 | COPY CVCUS01Y | 500 | record-di-file | `CVCUS01Y.CUSTOMER-RECORD` |
| CBIMPORT.cbl | FD:ACCOUNT-OUTPUT | ACCOUNT-RECORD | 89 | COPY CVACT01Y | 300 | record-di-file | `CVACT01Y.ACCOUNT-RECORD` |
| CBIMPORT.cbl | FD:XREF-OUTPUT | CARD-XREF-RECORD | 94 | COPY CVACT03Y | 50 | record-di-file | `CVACT03Y.CARD-XREF-RECORD` |
| CBIMPORT.cbl | FD:TRANSACTION-OUTPUT | TRAN-RECORD | 99 | COPY CVTRA05Y | 350 | record-di-file | `CVTRA05Y.TRAN-RECORD` |
| CBIMPORT.cbl | FD:CARD-OUTPUT | CARD-RECORD | 104 | COPY CVACT02Y | 150 | record-di-file | `CVACT02Y.CARD-RECORD` |
| CBIMPORT.cbl | FD:ERROR-OUTPUT | ERROR-OUTPUT-RECORD | 109 | 109-109 | 132 | record-di-file | `CBIMPORT.ERROR-OUTPUT-RECORD` |
| CBIMPORT.cbl | WORKING-STORAGE | WS-ERROR-RECORD | 152 | 152-160 | 130 | record-di-file | `CBIMPORT.WS-ERROR-RECORD` |
| CBSTM03A.CBL | FD:STMT-FILE | FD-STMTFILE-REC | 45 | 45-45 | 80 | riga-di-report | - |
| CBSTM03A.CBL | FD:HTML-FILE | FD-HTMLFILE-REC | 47 | 47-47 | 100 | riga-di-report | - |
| CBSTM03A.CBL | WORKING-STORAGE | WS-M03B-AREA | 71 | 71-83 | 1040 | area-di-lavoro | - |
| CBSTM03A.CBL | WORKING-STORAGE | STATEMENT-LINES | 85 | 85-146 | 1360 | riga-di-report | - |
| CBSTM03A.CBL | WORKING-STORAGE | HTML-LINES | 148 | 148-223 | 535 | riga-di-report | - |
| CBSTM03B.CBL | FD:TRNX-FILE | FD-TRNXFILE-REC | 59 | 59-63 | 350 | record-di-file | `CBSTM03B.FD-TRNXFILE-REC` |
| CBSTM03B.CBL | FD:XREF-FILE | FD-XREFFILE-REC | 66 | 66-68 | 50 | record-di-file | `CBSTM03B.FD-XREFFILE-REC` |
| CBSTM03B.CBL | FD:CUST-FILE | FD-CUSTFILE-REC | 71 | 71-73 | 500 | record-di-file | `CBSTM03B.FD-CUSTFILE-REC` |
| CBSTM03B.CBL | FD:ACCT-FILE | FD-ACCTFILE-REC | 76 | 76-78 | 300 | record-di-file | `CBSTM03B.FD-ACCTFILE-REC` |
| CBSTM03B.CBL | LINKAGE | LK-M03B-AREA | 100 | 100-112 | 1040 | area-di-lavoro | - |

### Relazioni struttura → record dell'FD

Lunghezze scritte a mano in `relazioni.tsv` (colonne `a mano`) e lette da cb2xml (colonne `cb2xml`).

| programma | verbo | righe | da | a | byte da (a mano / cb2xml) | byte a (a mano / cb2xml) | trasferiti | fonte | nota |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CBACT01C.cbl | READ-INTO | 166 | CBACT01C.FD-ACCTFILE-REC | CVACT01Y.ACCOUNT-RECORD | 300 / 300 | 300 / 300 | 300 | FD | - |
| CBACT01C.cbl | WRITE | 243 | CBACT01C.OUT-ACCT-REC | CBACT01C.OUT-ACCT-REC | 107 / 107 | 107 / 107 | 107 | FD | record composto campo per campo da ACCOUNT-RECORD; ACCT-CURR-CYC-DEBIT diventa COMP-3 (7 byte) |
| CBACT01C.cbl | WRITE | 264 | CBACT01C.ARR-ARRAY-REC | CBACT01C.ARR-ARRAY-REC | 110 / 110 | 110 / 110 | 110 | FD | - |
| CBACT01C.cbl | MOVE | 289 | CBACT01C.VBRC-REC1 | CBACT01C.VBR-REC | 12 / 12 | 80 / 80 | 12 | riga:288 | MOVE VBRC-REC1 TO VBR-REC(1:WS-RECD-LEN) |
| CBACT01C.cbl | WRITE | 290 | CBACT01C.VBR-REC | CBACT01C.VBR-REC | 80 / 80 | 80 / 80 | 12 | riga:288 | record variabile: scritti 12 byte (WS-RECD-LEN) |
| CBACT01C.cbl | MOVE | 304 | CBACT01C.VBRC-REC2 | CBACT01C.VBR-REC | 39 / 39 | 80 / 80 | 39 | riga:303 | MOVE VBRC-REC2 TO VBR-REC(1:WS-RECD-LEN) |
| CBACT01C.cbl | WRITE | 305 | CBACT01C.VBR-REC | CBACT01C.VBR-REC | 80 / 80 | 80 / 80 | 39 | riga:303 | record variabile: scritti 39 byte (WS-RECD-LEN) |
| CBACT02C.cbl | READ-INTO | 93 | CBACT02C.FD-CARDFILE-REC | CVACT02Y.CARD-RECORD | 150 / 150 | 150 / 150 | 150 | FD | - |
| CBACT03C.cbl | READ-INTO | 93 | CBACT03C.FD-XREFFILE-REC | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBCUS01C.cbl | READ-INTO | 93 | CBCUS01C.FD-CUSTFILE-REC | CVCUS01Y.CUSTOMER-RECORD | 500 / 500 | 500 / 500 | 500 | FD | - |
| CBACT04C.cbl | READ-INTO | 326 | CBACT04C.FD-TRAN-CAT-BAL-RECORD | CVTRA01Y.TRAN-CAT-BAL-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBACT04C.cbl | REWRITE-FROM | 356 | CVACT01Y.ACCOUNT-RECORD | CBACT04C.FD-ACCTFILE-REC | 300 / 300 | 300 / 300 | 300 | FD | - |
| CBACT04C.cbl | READ-INTO | 373 | CBACT04C.FD-ACCTFILE-REC | CVACT01Y.ACCOUNT-RECORD | 300 / 300 | 300 / 300 | 300 | FD | - |
| CBACT04C.cbl | READ-INTO | 394 | CBACT04C.FD-XREFFILE-REC | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | lettura per chiave alternativa (KEY IS FD-XREF-ACCT-ID, riga 395) |
| CBACT04C.cbl | READ-INTO | 416, 444 | CBACT04C.FD-DISCGRP-REC | CVTRA02Y.DIS-GROUP-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBACT04C.cbl | WRITE-FROM | 500 | CVTRA05Y.TRAN-RECORD | CBACT04C.FD-TRANFILE-REC | 350 / 350 | 350 / 350 | 350 | FD | - |
| CBEXPORT.cbl | READ | 260 | CVCUS01Y.CUSTOMER-RECORD | CVCUS01Y.CUSTOMER-RECORD | 500 / 500 | 500 / 500 | 500 | FD | FD con COPY CVCUS01Y |
| CBEXPORT.cbl | READ | 329 | CVACT01Y.ACCOUNT-RECORD | CVACT01Y.ACCOUNT-RECORD | 300 / 300 | 300 / 300 | 300 | FD | FD con COPY CVACT01Y |
| CBEXPORT.cbl | READ | 393 | CVACT03Y.CARD-XREF-RECORD | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | FD con COPY CVACT03Y |
| CBEXPORT.cbl | READ | 448 | CVTRA05Y.TRAN-RECORD | CVTRA05Y.TRAN-RECORD | 350 / 350 | 350 / 350 | 350 | FD | FD con COPY CVTRA05Y |
| CBEXPORT.cbl | READ | 513 | CVACT02Y.CARD-RECORD | CVACT02Y.CARD-RECORD | 150 / 150 | 150 / 150 | 150 | FD | FD con COPY CVACT02Y |
| CBEXPORT.cbl | WRITE-FROM | 301, 364, 419, 484, 542 | CVEXPORT.EXPORT-RECORD | CBEXPORT.EXPORT-OUTPUT-RECORD | 500 / 500 | 500 / 500 | 500 | FD | il record dell'FD e' PIC X(500): i campi veri sono quelli di CVEXPORT |
| CBIMPORT.cbl | READ-INTO | 261 | CBIMPORT.EXPORT-INPUT-RECORD | CVEXPORT.EXPORT-RECORD | 500 / 500 | 500 / 500 | 500 | FD | - |
| CBIMPORT.cbl | WRITE | 312 | CVCUS01Y.CUSTOMER-RECORD | CVCUS01Y.CUSTOMER-RECORD | 500 / 500 | 500 / 500 | 500 | FD | FD con COPY CVCUS01Y |
| CBIMPORT.cbl | WRITE | 341 | CVACT01Y.ACCOUNT-RECORD | CVACT01Y.ACCOUNT-RECORD | 300 / 300 | 300 / 300 | 300 | FD | FD con COPY CVACT01Y |
| CBIMPORT.cbl | WRITE | 361 | CVACT03Y.CARD-XREF-RECORD | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | FD con COPY CVACT03Y |
| CBIMPORT.cbl | WRITE | 391 | CVTRA05Y.TRAN-RECORD | CVTRA05Y.TRAN-RECORD | 350 / 350 | 350 / 350 | 350 | FD | FD con COPY CVTRA05Y |
| CBIMPORT.cbl | WRITE | 414 | CVACT02Y.CARD-RECORD | CVACT02Y.CARD-RECORD | 150 / 150 | 150 / 150 | 150 | FD | FD con COPY CVACT02Y |
| CBIMPORT.cbl | WRITE-FROM | 439 | CBIMPORT.WS-ERROR-RECORD | CBIMPORT.ERROR-OUTPUT-RECORD | 130 / 130 | 132 / 132 | 132 | FD | struttura di 130 byte in un record di 132: gli ultimi 2 byte sono riempiti di spazi dalla MOVE implicita |
| CBSTM03A.CBL | MOVE | 364 | CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT | CVACT03Y.CARD-XREF-RECORD | 1000 / 1000 | 50 / 50 | 50 | destinazione | record di XREFFILE letto da CBSTM03B (riga 165) e restituito in WS-M03B-FLDT |
| CBSTM03A.CBL | MOVE | 388 | CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT | CUSTREC.CUSTOMER-RECORD | 1000 / 1000 | 500 / 500 | 500 | destinazione | record di CUSTFILE letto da CBSTM03B (riga 190) |
| CBSTM03A.CBL | MOVE | 412 | CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT | CVACT01Y.ACCOUNT-RECORD | 1000 / 1000 | 300 / 300 | 300 | destinazione | record di ACCTFILE letto da CBSTM03B (riga 215) |
| CBSTM03A.CBL | MOVE | 756, 839 | CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT | COSTM01.TRNX-RECORD | 1000 / 1000 | 350 / 350 | 350 | destinazione | record di TRNXFILE letto da CBSTM03B (riga 141) |
| CBSTM03A.CBL | WRITE-FROM | 460 | CBSTM03A.STATEMENT-LINES:ST-LINE0 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 488 | CBSTM03A.STATEMENT-LINES:ST-LINE1 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 489 | CBSTM03A.STATEMENT-LINES:ST-LINE2 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 490 | CBSTM03A.STATEMENT-LINES:ST-LINE3 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 491 | CBSTM03A.STATEMENT-LINES:ST-LINE4 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 492, 494 | CBSTM03A.STATEMENT-LINES:ST-LINE5 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 493 | CBSTM03A.STATEMENT-LINES:ST-LINE6 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 495 | CBSTM03A.STATEMENT-LINES:ST-LINE7 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 496 | CBSTM03A.STATEMENT-LINES:ST-LINE8 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 497 | CBSTM03A.STATEMENT-LINES:ST-LINE9 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 498 | CBSTM03A.STATEMENT-LINES:ST-LINE10 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 499 | CBSTM03A.STATEMENT-LINES:ST-LINE11 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 435, 500, 502 | CBSTM03A.STATEMENT-LINES:ST-LINE12 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 501 | CBSTM03A.STATEMENT-LINES:ST-LINE13 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 679 | CBSTM03A.STATEMENT-LINES:ST-LINE14 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 436 | CBSTM03A.STATEMENT-LINES:ST-LINE14A | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 437 | CBSTM03A.STATEMENT-LINES:ST-LINE15 | CBSTM03A.FD-STMTFILE-REC | 80 / 80 | 80 / 80 | 80 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 440, 442, 444, 446, 448, 450, 452, 454, 509, 511, 513, 515, 517, 519, 521, 523, 525, 527, 532, 534, 536, 538, 540, 542, 544, 546, 548, 550, 552, 595, 597, 599, 601, 603, 605, 607, 609, 611, 635, 637, 639, 641, 643, 645, 647, 649, 651, 653, 655, 657, 659, 661, 663, 665, 667, 669, 682, 685, 694, 697, 706, 709, 718, 721 | CBSTM03A.HTML-LINES:HTML-FIXED-LN | CBSTM03A.FD-HTMLFILE-REC | 100 / 100 | 100 / 100 | 100 | FD | il contenuto e' il valore dell'88 impostato con SET subito prima |
| CBSTM03A.CBL | WRITE-FROM | 530 | CBSTM03A.HTML-LINES:HTML-L11 | CBSTM03A.FD-HTMLFILE-REC | 59 / 59 | 100 / 100 | 100 | FD | struttura di 59 byte in un record di 100: il resto e' riempito di spazi |
| CBSTM03A.CBL | WRITE | 568 | CBSTM03A.FD-HTMLFILE-REC | CBSTM03A.FD-HTMLFILE-REC | 100 / 100 | 100 / 100 | 100 | FD | record composto con STRING ... INTO FD-HTMLFILE-REC (righe 562-567) |
| CBSTM03A.CBL | WRITE-FROM | 576, 584, 592 | CBSTM03A.HTML-LINES:HTML-ADDR-LN | CBSTM03A.FD-HTMLFILE-REC | 100 / 100 | 100 / 100 | 100 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 619, 626, 633 | CBSTM03A.HTML-LINES:HTML-BSIC-LN | CBSTM03A.FD-HTMLFILE-REC | 100 / 100 | 100 / 100 | 100 | FD | - |
| CBSTM03A.CBL | WRITE-FROM | 692, 704, 716 | CBSTM03A.HTML-LINES:HTML-TRAN-LN | CBSTM03A.FD-HTMLFILE-REC | 100 / 100 | 100 / 100 | 100 | FD | - |
| CBSTM03B.CBL | READ-INTO | 141 | CBSTM03B.FD-TRNXFILE-REC | CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT | 350 / 350 | 1000 / 1000 | 350 | FD | CBSTM03A sposta poi LK-M03B-FLDT in TRNX-RECORD (COSTM01), righe 756 e 839 |
| CBSTM03B.CBL | READ-INTO | 165 | CBSTM03B.FD-XREFFILE-REC | CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT | 50 / 50 | 1000 / 1000 | 50 | FD | CBSTM03A lo sposta poi in CARD-XREF-RECORD (CVACT03Y), riga 364 |
| CBSTM03B.CBL | READ-INTO | 190 | CBSTM03B.FD-CUSTFILE-REC | CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT | 500 / 500 | 1000 / 1000 | 500 | FD | CBSTM03A lo sposta poi in CUSTOMER-RECORD (CUSTREC), riga 388 |
| CBSTM03B.CBL | READ-INTO | 215 | CBSTM03B.FD-ACCTFILE-REC | CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT | 300 / 300 | 1000 / 1000 | 300 | FD | CBSTM03A lo sposta poi in ACCOUNT-RECORD (CVACT01Y), riga 412 |
| CBTRN01C.cbl | READ-INTO | 203 | CBTRN01C.FD-TRAN-RECORD | CVTRA06Y.DALYTRAN-RECORD | 350 / 350 | 350 / 350 | 350 | FD | - |
| CBTRN01C.cbl | READ-INTO | 229 | CBTRN01C.FD-XREFFILE-REC | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBTRN01C.cbl | READ-INTO | 243 | CBTRN01C.FD-ACCTFILE-REC | CVACT01Y.ACCOUNT-RECORD | 300 / 300 | 300 / 300 | 300 | FD | - |
| CBTRN02C.cbl | READ-INTO | 346 | CBTRN02C.FD-TRAN-RECORD | CVTRA06Y.DALYTRAN-RECORD | 350 / 350 | 350 / 350 | 350 | FD | - |
| CBTRN02C.cbl | READ-INTO | 383 | CBTRN02C.FD-XREFFILE-REC | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBTRN02C.cbl | READ-INTO | 395 | CBTRN02C.FD-ACCTFILE-REC | CVACT01Y.ACCOUNT-RECORD | 300 / 300 | 300 / 300 | 300 | FD | - |
| CBTRN02C.cbl | MOVE | 438 | CBTRN02C.DB2-FORMAT-TS | CVTRA05Y.TRAN-RECORD:TRAN-PROC-TS | 26 / 26 | 26 / 26 | 26 | destinazione | timestamp di elaborazione nel record delle transazioni, scritto alla riga 564 |
| CBTRN02C.cbl | MOVE | 447 | CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD:REJECT-TRAN-DATA | 350 / 350 | 350 / 350 | 350 | destinazione | prima parte del record degli scarti |
| CBTRN02C.cbl | MOVE | 448 | CBTRN02C.WS-VALIDATION-TRAILER | CBTRN02C.REJECT-RECORD:VALIDATION-TRAILER | 80 / 80 | 80 / 80 | 80 | destinazione | seconda parte del record degli scarti |
| CBTRN02C.cbl | WRITE-FROM | 451 | CBTRN02C.REJECT-RECORD | CBTRN02C.FD-REJS-RECORD | 430 / 430 | 430 / 430 | 430 | FD | - |
| CBTRN02C.cbl | READ-INTO | 474 | CBTRN02C.FD-TRAN-CAT-BAL-RECORD | CVTRA01Y.TRAN-CAT-BAL-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBTRN02C.cbl | WRITE-FROM | 510 | CVTRA01Y.TRAN-CAT-BAL-RECORD | CBTRN02C.FD-TRAN-CAT-BAL-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBTRN02C.cbl | REWRITE-FROM | 528 | CVTRA01Y.TRAN-CAT-BAL-RECORD | CBTRN02C.FD-TRAN-CAT-BAL-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBTRN02C.cbl | REWRITE-FROM | 554 | CVACT01Y.ACCOUNT-RECORD | CBTRN02C.FD-ACCTFILE-REC | 300 / 300 | 300 / 300 | 300 | FD | - |
| CBTRN02C.cbl | WRITE-FROM | 564 | CVTRA05Y.TRAN-RECORD | CBTRN02C.FD-TRANFILE-REC | 350 / 350 | 350 / 350 | 350 | FD | - |
| CBTRN03C.cbl | READ-INTO | 221 | CBTRN03C.FD-DATEPARM-REC | CBTRN03C.WS-DATEPARM-RECORD | 80 / 80 | 21 / 21 | 80 | FD | record di 80 byte letto in una struttura di 21: la MOVE implicita tronca a 21 |
| CBTRN03C.cbl | READ-INTO | 249 | CBTRN03C.FD-TRANFILE-REC | CVTRA05Y.TRAN-RECORD | 350 / 350 | 350 / 350 | 350 | FD | - |
| CBTRN03C.cbl | MOVE | 295 | CVTRA07Y.REPORT-PAGE-TOTALS | CBTRN03C.FD-REPTFILE-REC | 112 / 112 | 133 / 133 | 133 | destinazione | riga di 112 byte in un record di 133: il resto e' riempito di spazi |
| CBTRN03C.cbl | MOVE | 300, 312, 337 | CVTRA07Y.TRANSACTION-HEADER-2 | CBTRN03C.FD-REPTFILE-REC | 133 / 133 | 133 / 133 | 133 | destinazione | - |
| CBTRN03C.cbl | MOVE | 308 | CVTRA07Y.REPORT-ACCOUNT-TOTALS | CBTRN03C.FD-REPTFILE-REC | 112 / 112 | 133 / 133 | 133 | destinazione | riga di 112 byte in un record di 133 |
| CBTRN03C.cbl | MOVE | 320 | CVTRA07Y.REPORT-GRAND-TOTALS | CBTRN03C.FD-REPTFILE-REC | 112 / 112 | 133 / 133 | 133 | destinazione | riga di 112 byte in un record di 133 |
| CBTRN03C.cbl | MOVE | 325 | CVTRA07Y.REPORT-NAME-HEADER | CBTRN03C.FD-REPTFILE-REC | 115 / 115 | 133 / 133 | 133 | destinazione | riga di 115 byte in un record di 133 |
| CBTRN03C.cbl | MOVE | 329 | CBTRN03C.WS-REPORT-VARS:WS-BLANK-LINE | CBTRN03C.FD-REPTFILE-REC | 133 / 133 | 133 / 133 | 133 | destinazione | - |
| CBTRN03C.cbl | MOVE | 333 | CVTRA07Y.TRANSACTION-HEADER-1 | CBTRN03C.FD-REPTFILE-REC | 114 / 114 | 133 / 133 | 133 | destinazione | riga di 114 byte in un record di 133 |
| CBTRN03C.cbl | MOVE | 371 | CVTRA07Y.TRANSACTION-DETAIL-REPORT | CBTRN03C.FD-REPTFILE-REC | 114 / 114 | 133 / 133 | 133 | destinazione | riga di 114 byte in un record di 133 |
| CBTRN03C.cbl | WRITE | 345 | CBTRN03C.FD-REPTFILE-REC | CBTRN03C.FD-REPTFILE-REC | 133 / 133 | 133 / 133 | 133 | FD | unica WRITE del report (paragrafo 1111-WRITE-REPORT-REC) |
| CBTRN03C.cbl | READ-INTO | 485 | CBTRN03C.FD-CARDXREF-REC | CVACT03Y.CARD-XREF-RECORD | 50 / 50 | 50 / 50 | 50 | FD | - |
| CBTRN03C.cbl | READ-INTO | 495 | CBTRN03C.FD-TRANTYPE-REC | CVTRA03Y.TRAN-TYPE-RECORD | 60 / 60 | 60 / 60 | 60 | FD | - |
| CBTRN03C.cbl | READ-INTO | 505 | CBTRN03C.FD-TRAN-CAT-RECORD | CVTRA04Y.TRAN-CAT-RECORD | 60 / 60 | 60 / 60 | 60 | FD | - |

### Trasferimenti di strutture intere verso i record scritti (ricavati dal sorgente)

Ogni `MOVE` di una voce di livello 01 o di un gruppo verso un record che finisce in un file (record di una `WRITE`/`REWRITE` o struttura di una `WRITE`/`REWRITE ... FROM`) o verso una sua parte. Il controllo pretende per ciascuno una relazione in `relazioni.tsv` e la struttura sorgente nel censimento.

| programma | riga | struttura | destinazione | record |
| --- | --- | --- | --- | --- |
| CBACT01C.cbl | 289 | VBRC-REC1 | VBR-REC (con posizione) | VBR-REC |
| CBACT01C.cbl | 304 | VBRC-REC2 | VBR-REC (con posizione) | VBR-REC |
| CBTRN02C.cbl | 438 | DB2-FORMAT-TS | TRAN-PROC-TS | TRAN-RECORD |
| CBTRN02C.cbl | 447 | DALYTRAN-RECORD | REJECT-TRAN-DATA | REJECT-RECORD |
| CBTRN02C.cbl | 448 | WS-VALIDATION-TRAILER | VALIDATION-TRAILER | REJECT-RECORD |
| CBTRN03C.cbl | 295 | REPORT-PAGE-TOTALS | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 300 | TRANSACTION-HEADER-2 | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 308 | REPORT-ACCOUNT-TOTALS | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 312 | TRANSACTION-HEADER-2 | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 320 | REPORT-GRAND-TOTALS | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 325 | REPORT-NAME-HEADER | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 333 | TRANSACTION-HEADER-1 | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 337 | TRANSACTION-HEADER-2 | FD-REPTFILE-REC | FD-REPTFILE-REC |
| CBTRN03C.cbl | 371 | TRANSACTION-DETAIL-REPORT | FD-REPTFILE-REC | FD-REPTFILE-REC |

### Posizione nel record dei campi delle strutture trasferite

Da `composizioni.tsv`: offset (base 0) del campo nel record di destinazione = offset della parte di destinazione + offset del campo nella struttura, entrambi da cb2xml.

| struttura | record | parte del record | campo | indice | offset nel record | byte |
| --- | --- | --- | --- | --- | --- | --- |
| CBACT01C.VBRC-REC1 | CBACT01C.VBR-REC | - | VB1-ACCT-ID | - | 0 | 11 |
| CBACT01C.VBRC-REC1 | CBACT01C.VBR-REC | - | VB1-ACCT-ACTIVE-STATUS | - | 11 | 1 |
| CBACT01C.VBRC-REC2 | CBACT01C.VBR-REC | - | VB2-ACCT-ID | - | 0 | 11 |
| CBACT01C.VBRC-REC2 | CBACT01C.VBR-REC | - | VB2-ACCT-CURR-BAL | - | 11 | 12 |
| CBACT01C.VBRC-REC2 | CBACT01C.VBR-REC | - | VB2-ACCT-CREDIT-LIMIT | - | 23 | 12 |
| CBACT01C.VBRC-REC2 | CBACT01C.VBR-REC | - | VB2-ACCT-REISSUE-YYYY | - | 35 | 4 |
| CBTRN02C.DB2-FORMAT-TS | CVTRA05Y.TRAN-RECORD | TRAN-PROC-TS | DB2-FORMAT-TS | - | 304 | 26 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-ID | - | 0 | 16 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-TYPE-CD | - | 16 | 2 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-CAT-CD | - | 18 | 4 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-SOURCE | - | 22 | 10 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-DESC | - | 32 | 100 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-AMT | - | 132 | 11 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-MERCHANT-ID | - | 143 | 9 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-MERCHANT-NAME | - | 152 | 50 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-MERCHANT-CITY | - | 202 | 50 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-MERCHANT-ZIP | - | 252 | 10 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-CARD-NUM | - | 262 | 16 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-ORIG-TS | - | 278 | 26 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | DALYTRAN-PROC-TS | - | 304 | 26 |
| CVTRA06Y.DALYTRAN-RECORD | CBTRN02C.REJECT-RECORD | REJECT-TRAN-DATA | FILLER | - | 330 | 20 |
| CBTRN02C.WS-VALIDATION-TRAILER | CBTRN02C.REJECT-RECORD | VALIDATION-TRAILER | WS-VALIDATION-FAIL-REASON | - | 350 | 4 |
| CBTRN02C.WS-VALIDATION-TRAILER | CBTRN02C.REJECT-RECORD | VALIDATION-TRAILER | WS-VALIDATION-FAIL-REASON-DESC | - | 354 | 76 |

### Scritture nei record non coperte dai trasferimenti di strutture

Istruzioni che scrivono dentro un record che finisce in un file senza trasferire una struttura intera: composizione campo per campo, letterali, riferimenti con posizione, `STRING`, `INITIALIZE`, aritmetica. Non sono ricondotte a relazioni: l'elenco completo (240 punti) e' in `analysis/data-contract/out/fonti/non-coperti.tsv`.

| programma | record | tipo | quante | righe |
| --- | --- | --- | --- | --- |
| CBACT01C.cbl | ARR-ARRAY-REC | INITIALIZE | 1 | 169 |
| CBACT01C.cbl | ARR-ARRAY-REC | MOVE di un campo (composizione campo per campo) | 3 | 254, 255, 257 |
| CBACT01C.cbl | ARR-ARRAY-REC | MOVE di un letterale o di un'espressione | 4 | 256, 258, 259, 260 |
| CBACT01C.cbl | OUT-ACCT-REC | MOVE di un campo (composizione campo per campo) | 10 | 216, 217, 218, 219, 220, 221, 222, 233, 235, 239 |
| CBACT01C.cbl | OUT-ACCT-REC | MOVE di un letterale o di un'espressione | 1 | 237 |
| CBACT04C.cbl | ACCOUNT-RECORD | MOVE di un letterale o di un'espressione | 2 | 353, 354 |
| CBACT04C.cbl | ACCOUNT-RECORD | aritmetica (ADD) | 1 | 352 |
| CBACT04C.cbl | ACCOUNT-RECORD | aritmetica (COMPUTE) | 1 | 464 |
| CBACT04C.cbl | FD-ACCTFILE-REC | MOVE di un campo (composizione campo per campo) | 1 | 202 |
| CBACT04C.cbl | FD-TRANFILE-REC | aritmetica (COMPUTE) | 1 | 464 |
| CBACT04C.cbl | TRAN-RECORD | aritmetica (COMPUTE) | 14 | 464, 464, 464, 464, 464, 464, 464, 464, 464, 464, 464, 464, 464, 464 |
| CBEXPORT.cbl | EXPORT-RECORD | INITIALIZE | 5 | 271, 340, 404, 459, 524 |
| CBEXPORT.cbl | EXPORT-RECORD | MOVE di un campo (composizione campo per campo) | 62 | 275, 277, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 344, 346, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 408, 410, 415, 416, 417, 463, 465, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 528, 530, 535, 536, 537, 538, 539, 540 |
| CBEXPORT.cbl | EXPORT-RECORD | MOVE di un letterale o di un'espressione | 15 | 274, 278, 279, 343, 347, 348, 407, 411, 412, 462, 466, 467, 527, 531, 532 |
| CBIMPORT.cbl | ACCOUNT-RECORD | INITIALIZE | 1 | 325 |
| CBIMPORT.cbl | ACCOUNT-RECORD | MOVE di un campo (composizione campo per campo) | 12 | 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339 |
| CBIMPORT.cbl | CARD-RECORD | INITIALIZE | 1 | 404 |
| CBIMPORT.cbl | CARD-RECORD | MOVE di un campo (composizione campo per campo) | 6 | 407, 408, 409, 410, 411, 412 |
| CBIMPORT.cbl | CARD-XREF-RECORD | INITIALIZE | 1 | 354 |
| CBIMPORT.cbl | CARD-XREF-RECORD | MOVE di un campo (composizione campo per campo) | 3 | 357, 358, 359 |
| CBIMPORT.cbl | CUSTOMER-RECORD | INITIALIZE | 1 | 290 |
| CBIMPORT.cbl | CUSTOMER-RECORD | MOVE con riferimento a posizione nella sorgente | 5 | 297, 298, 299, 303, 304 |
| CBIMPORT.cbl | CUSTOMER-RECORD | MOVE di un campo (composizione campo per campo) | 13 | 293, 294, 295, 296, 300, 301, 302, 305, 306, 307, 308, 309, 310 |
| CBIMPORT.cbl | TRAN-RECORD | INITIALIZE | 1 | 374 |
| CBIMPORT.cbl | TRAN-RECORD | MOVE di un campo (composizione campo per campo) | 13 | 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389 |
| CBIMPORT.cbl | WS-ERROR-RECORD | MOVE di un campo (composizione campo per campo) | 2 | 430, 431 |
| CBIMPORT.cbl | WS-ERROR-RECORD | MOVE di un letterale o di un'espressione | 2 | 429, 432 |
| CBSTM03A.CBL | FD-HTMLFILE-REC | MOVE di un letterale o di un'espressione | 1 | 561 |
| CBSTM03A.CBL | FD-HTMLFILE-REC | STRING | 1 | 562 |
| CBSTM03A.CBL | HTML-ADDR-LN | MOVE di un letterale o di un'espressione | 3 | 569, 577, 585 |
| CBSTM03A.CBL | HTML-ADDR-LN | STRING | 3 | 570, 578, 586 |
| CBSTM03A.CBL | HTML-BSIC-LN | MOVE di un letterale o di un'espressione | 3 | 613, 620, 627 |
| CBSTM03A.CBL | HTML-BSIC-LN | STRING | 3 | 614, 621, 628 |
| CBSTM03A.CBL | HTML-L11 | MOVE di un campo (composizione campo per campo) | 1 | 529 |
| CBSTM03A.CBL | HTML-TRAN-LN | MOVE di un letterale o di un'espressione | 3 | 686, 698, 710 |
| CBSTM03A.CBL | HTML-TRAN-LN | STRING | 3 | 687, 699, 711 |
| CBSTM03A.CBL | ST-LINE1 | STRING | 1 | 462 |
| CBSTM03A.CBL | ST-LINE14 | MOVE di un campo (composizione campo per campo) | 3 | 676, 677, 678 |
| CBSTM03A.CBL | ST-LINE14A | MOVE di un campo (composizione campo per campo) | 1 | 434 |
| CBSTM03A.CBL | ST-LINE2 | MOVE di un campo (composizione campo per campo) | 1 | 470 |
| CBSTM03A.CBL | ST-LINE3 | MOVE di un campo (composizione campo per campo) | 1 | 471 |
| CBSTM03A.CBL | ST-LINE4 | STRING | 1 | 472 |
| CBSTM03A.CBL | ST-LINE7 | MOVE di un campo (composizione campo per campo) | 1 | 483 |
| CBSTM03A.CBL | ST-LINE8 | MOVE di un campo (composizione campo per campo) | 1 | 484 |
| CBSTM03A.CBL | ST-LINE9 | MOVE di un campo (composizione campo per campo) | 1 | 485 |
| CBTRN02C.cbl | ACCOUNT-RECORD | aritmetica (ADD) | 3 | 547, 549, 551 |
| CBTRN02C.cbl | FD-ACCTFILE-REC | MOVE di un campo (composizione campo per campo) | 1 | 394 |
| CBTRN02C.cbl | FD-TRAN-CAT-BAL-RECORD | MOVE di un campo (composizione campo per campo) | 3 | 469, 470, 471 |
| CBTRN02C.cbl | TRAN-CAT-BAL-RECORD | INITIALIZE | 1 | 504 |
| CBTRN02C.cbl | TRAN-CAT-BAL-RECORD | MOVE di un campo (composizione campo per campo) | 3 | 505, 506, 507 |
| CBTRN02C.cbl | TRAN-CAT-BAL-RECORD | aritmetica (ADD) | 2 | 508, 527 |
| CBTRN02C.cbl | TRAN-RECORD | MOVE di un campo (composizione campo per campo) | 12 | 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436 |
| CBTRN03C.cbl | FD-REPTFILE-REC | MOVE di un campo (composizione campo per campo) | 1 | 329 |
