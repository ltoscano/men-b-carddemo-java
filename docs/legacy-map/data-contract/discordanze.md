# Discordanze tra le fonti dei tracciati e delle chiavi (issue #3)

Questo documento registra dove le fonti di CardDemo (commit `59cc6c2`) non dicono la stessa cosa su un file: `DEFINE` nei JCL di `app/jcl/`, `app/catlg/LISTCAT.txt`, `SELECT` e `FD` dei programmi batch di `app/cbl/`, copybook di `app/cpy/`. Le discordanze **si registrano e non si correggono**: il sorgente legacy resta com'è, e chi migra decide che cosa preservare.

## Come si trovano

Nessuna voce di questo documento nasce da una lettura a occhio soltanto. `./analysis/run.sh data-contract` estrae le quattro fonti (cb2xml per i tracciati, estrazione testuale dichiarata per `DEFINE`, `LISTCAT`, `SELECT` e `FD`), riconduce ogni chiave ai campi che occupa e confronta le fonti a coppie. Ogni differenza trovata riceve un identificativo stabile, che compare qui tra apici inversi; l'elenco completo è in `analysis/data-contract/out/discordanze-rilevate.tsv` e nella vista generata `chiavi.md`. Il controllo (`./analysis/run.sh data-contract --check`) fallisce se una differenza rilevata manca da questo documento, se le due discordanze chieste dalla specifica non sono rilevate o non sono scritte qui, e se qui se ne cita una che il confronto non trova.

Le differenze sono di due categorie:

- **discordanza**: due fonti descrivono in modo diverso la stessa cosa (posizione o unicità di una chiave, presenza di un campo, di una DD);
- **osservazione**: dato che differisce tra piattaforme o tra struttura e record e che la specifica chiede di annotare senza interpretarlo (lunghezza della DCB, lunghezze diverse in una `MOVE`, programma senza JCL, `REDEFINES` più lunghe).

Le posizioni sono a base 0. In `KEYS(lunghezza offset)` di IDCAMS l'offset è contato da zero: lo confermano, nello stesso repository, le altre tre `DEFINE ALTERNATEINDEX` (per esempio `KEYS(11,25)` in `XREFFILE.jcl` riga 74 indica `XREF-ACCT-ID`, che nel copybook `CVACT03Y` inizia dopo 16 + 9 = 25 byte) e il `LISTCAT`, il cui `AXRKP` coincide con l'offset della `DEFINE` per tutti e tre gli indici alternativi catalogati (righe 283, 486, 3676).

## Le due discordanze chieste dalla specifica

### 1. Indice alternativo di `XREFFILE`: non unico nel JCL, unico nel programma

`chiave-unicita:AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX:CBACT04C`

| Fonte | Dove | Che cosa dice |
| --- | --- | --- |
| JCL | `app/jcl/XREFFILE.jcl` righe 72-75 | `DEFINE ALTERNATEINDEX (NAME(AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX) RELATE(AWS.M2.CARDDEMO.CARDXREF.VSAM.KSDS) KEYS(11,25) NONUNIQUEKEY` |
| Catalogo | `app/catlg/LISTCAT.txt` righe 472-488 | componente `AWS.M2.CARDDEMO.CARDXREF.VSAM.AIX.DATA`: `KEYLEN 11`, `AXRKP 25`, `NONUNIQKEY` |
| Programma | `app/cbl/CBACT04C.cbl` righe 34-39 | `SELECT XREF-FILE ... ALTERNATE RECORD KEY IS FD-XREF-ACCT-ID`, **senza** `WITH DUPLICATES` |
| FD | `app/cbl/CBACT04C.cbl` riga 73 | `FD-XREF-ACCT-ID PIC 9(11)` a offset 25 (dopo `FD-XREF-CARD-NUM` 16 e `FD-XREF-CUST-NUM` 9) |
| Copybook | `app/cpy/CVACT03Y.cpy` riga 7 | `XREF-ACCT-ID PIC 9(11)`, offset 25 |

La posizione coincide in tutte le fonti (offset 25, 11 byte, campo `XREF-ACCT-ID`); differisce l'unicità. Il JCL e il catalogo ammettono più carte per lo stesso conto; il programma dichiara la chiave alternativa unica e la usa in lettura diretta (`READ XREF-FILE INTO CARD-XREF-RECORD KEY IS FD-XREF-ACCT-ID`, righe 394-395). Il passo che esegue `CBACT04C` assegna il percorso dell'indice alla DD `XREFFIL1` (`app/jcl/INTCALC.jcl` righe 31-32). Che cosa restituisca la lettura quando più record condividono il conto dipende dal runtime e non è verificato qui.

### 2. Chiave del file di export: `KEYS(4 28)` nel JCL, campo a offset 27 in `WORKING-STORAGE`

`chiave-allineamento:AWS.M2.CARDDEMO.EXPORT.DATA:app/jcl/CBEXPORT.jcl:30`
`chiave-fuori-dal-record:CBEXPORT.EXPORT-OUTPUT`
`chiave-posizione:AWS.M2.CARDDEMO.EXPORT.DATA:primaria:CBEXPORT:EXPORT-SEQUENCE-NUM`

| Fonte | Dove | Che cosa dice |
| --- | --- | --- |
| JCL | `app/jcl/CBEXPORT.jcl` righe 30-33 | `DEFINE CLUSTER (NAME(AWS.M2.CARDDEMO.EXPORT.DATA) INDEXED KEYS(4 28) RECORDSIZE(500 500)`: chiave nei byte 28-31 |
| Programma | `app/cbl/CBEXPORT.cbl` righe 65-69 | `SELECT EXPORT-OUTPUT ... ORGANIZATION IS INDEXED ... RECORD KEY IS EXPORT-SEQUENCE-NUM` |
| FD | `app/cbl/CBEXPORT.cbl` righe 89-92 | `FD EXPORT-OUTPUT RECORDING MODE IS F RECORD CONTAINS 500 CHARACTERS`, `01 EXPORT-OUTPUT-RECORD PIC X(500)`: la chiave **non è un campo del record dell'FD** |
| Copybook | `app/cpy/CVEXPORT.cpy` riga 16, copiato in `WORKING-STORAGE` (`CBEXPORT.cbl` riga 96) | `EXPORT-SEQUENCE-NUM PIC 9(9) COMP`: offset 1 + 26 = **27**, 4 byte (byte 27-30) |

I byte 28-31 della `DEFINE` coprono gli ultimi tre byte di `EXPORT-SEQUENCE-NUM` e il primo di `EXPORT-BRANCH-ID`. Se l'offset della `DEFINE` fosse contato da 1 le due fonti coinciderebbero; nel resto del repository però è contato da 0 (vedi sopra). Il record viene scritto con `WRITE EXPORT-OUTPUT-RECORD FROM EXPORT-RECORD` (righe 301, 364, 419, 484, 542), quindi i dati veri del file sono quelli di `CVEXPORT`. Lo stesso accade in lettura in `CBIMPORT`:

`chiave-fuori-dal-record:CBIMPORT.EXPORT-INPUT`
`chiave-posizione:AWS.M2.CARDDEMO.EXPORT.DATA:primaria:CBIMPORT:EXPORT-SEQUENCE-NUM`

(`app/cbl/CBIMPORT.cbl` righe 37-41 `RECORD KEY IS EXPORT-SEQUENCE-NUM`, riga 79 `01 EXPORT-INPUT-RECORD PIC X(500)`, riga 113 `COPY CVEXPORT` in `WORKING-STORAGE`). Per questo motivo GnuCOBOL rifiuta entrambi i programmi così come sono (esito di #1, `docs/legacy-map/strumenti.md`); se lo accetti il compilatore IBM non è verificato. Il commento di `CVEXPORT.cpy` (riga 4) parla di "sequential export file", mentre JCL e programmi lo definiscono indicizzato.

## Altre discordanze

### Chiave del cluster `AWS.CUSTDATA.CLUSTER`: 10 byte su un campo di 9

`chiave-allineamento:AWS.CUSTDATA.CLUSTER:app/jcl/DEFCUST.jcl:35`

`app/jcl/DEFCUST.jcl` righe 35-38 definisce `AWS.CUSTDATA.CLUSTER` con `KEYS(10 0) RECORDSIZE(500 500)`. Il tracciato cliente (`CVCUS01Y.cpy` riga 5, `CUST-ID PIC 9(09)`) ha la chiave di 9 byte, ed è di 9 byte anche la `DEFINE` del file clienti usato dai programmi (`app/jcl/CUSTFILE.jcl` riga 50, `KEYS(9 0)` per `AWS.M2.CARDDEMO.CUSTDATA.VSAM.KSDS`, confermata dal `LISTCAT` riga 632). Nessun programma batch usa `AWS.CUSTDATA.CLUSTER`: l'associazione al tracciato `CVCUS01Y` in `file.tsv` è un'ipotesi basata su `RECORDSIZE(500 500)` ed è dichiarata come tale.

### Chiave cliente alfanumerica in `CBSTM03B`

`chiave-tipo:AWS.M2.CARDDEMO.CUSTDATA.VSAM.KSDS:CBSTM03B:FD-CUST-ID`

`app/cbl/CBSTM03B.CBL` riga 72 dichiara `FD-CUST-ID PIC X(09)`, chiave del file clienti (`SELECT CUST-FILE ... RECORD KEY IS FD-CUST-ID`, righe 43-47); il tracciato del file (`CVCUS01Y.cpy` riga 5, e `CUSTREC.cpy` riga 5 usato da `CBSTM03A`) ha `CUST-ID PIC 9(09)`. Posizione e lunghezza coincidono (offset 0, 9 byte); cambia la classe del campo (alfanumerico contro numerico). Gli altri programmi che leggono lo stesso file usano `PIC 9(09)` (`CBCUS01C.cbl` riga 39, `CBTRN01C.cbl` riga 73).

### DD mancante per `CARD-OUTPUT` in `CBIMPORT`

`dd-assente:CBIMPORT.CARD-OUTPUT`

`app/cbl/CBIMPORT.cbl` riga 63 assegna `CARD-OUTPUT` a `CARDOUT`; il passo `STEP01` di `app/jcl/CBIMPORT.jcl` ha le DD `EXPFILE`, `CUSTOUT`, `ACCTOUT`, `XREFOUT`, `TRNXOUT`, `ERROUT` (righe 28-60) e nessuna `CARDOUT`.

## Osservazioni

### Lunghezza della DCB del file variabile di `CBACT01C`

`lrecl:CBACT01C.VBRC-FILE`

`app/jcl/READACCT.jcl` riga 47 dichiara per `VBRCFILE` `LRECL=84,RECFM=VB`; l'FD (`app/cbl/CBACT01C.cbl` righe 80-85) dichiara `RECORDING MODE IS V`, `RECORD IS VARYING IN SIZE FROM 10 TO 80 DEPENDING ON WS-RECD-LEN` e `01 VBR-REC PIC X(80)`. Il contratto descrive il contenuto del record (al massimo 80 byte; scritti 12 byte da `VBRC-REC1` e 39 da `VBRC-REC2`); la differenza di 4 byte con la DCB si annota senza interpretarla.

### Programma batch senza JCL

`nessun-jcl:CBTRN01C.ACCOUNT-FILE`, `nessun-jcl:CBTRN01C.CARD-FILE`, `nessun-jcl:CBTRN01C.CUSTOMER-FILE`, `nessun-jcl:CBTRN01C.DALYTRAN-FILE`, `nessun-jcl:CBTRN01C.TRANSACT-FILE`, `nessun-jcl:CBTRN01C.XREF-FILE`

Nessun JCL di `app/jcl/` esegue `CBTRN01C` (nessun `PGM=CBTRN01C`): i suoi sei file non sono ricondotti a un dataset e le sue chiavi si confrontano solo con l'FD. I nomi delle DD (`ACCTFILE`, `CARDFILE`, `CUSTFILE`, `DALYTRAN`, `TRANFILE`, `XREFFILE`) sono gli stessi usati da altri job, ma la corrispondenza non è dimostrata dal repository.

### Strutture e record di lunghezza diversa

La `MOVE` implicita di `WRITE ... FROM` e `READ ... INTO`, e la `MOVE` esplicita, riempiono di spazi o troncano. Sono comportamenti da preservare nella migrazione, quindi si elencano:

| Identificativo | Programma e righe | Da | A |
| --- | --- | --- | --- |
| `lunghezze-diverse:CBACT01C:CBACT01C.VBRC-REC1->CBACT01C.VBR-REC` | `CBACT01C` 289 | 12 | 80 (si sposta in `VBR-REC(1:12)`) |
| `lunghezze-diverse:CBACT01C:CBACT01C.VBRC-REC2->CBACT01C.VBR-REC` | `CBACT01C` 304 | 39 | 80 (si sposta in `VBR-REC(1:39)`) |
| `lunghezze-diverse:CBIMPORT:CBIMPORT.WS-ERROR-RECORD->CBIMPORT.ERROR-OUTPUT-RECORD` | `CBIMPORT` 439 | 130 | 132 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.HTML-LINES:HTML-L11->CBSTM03A.FD-HTMLFILE-REC` | `CBSTM03A` 530 | 59 | 100 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->CVACT03Y.CARD-XREF-RECORD` | `CBSTM03A` 364 | 1000 | 50 (troncamento dell'area di scambio) |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->CUSTREC.CUSTOMER-RECORD` | `CBSTM03A` 388 | 1000 | 500 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->CVACT01Y.ACCOUNT-RECORD` | `CBSTM03A` 412 | 1000 | 300 |
| `lunghezze-diverse:CBSTM03A:CBSTM03A.WS-M03B-AREA:WS-M03B-FLDT->COSTM01.TRNX-RECORD` | `CBSTM03A` 756, 839 | 1000 | 350 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-TRNXFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | `CBSTM03B` 141 | 350 | 1000 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-XREFFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | `CBSTM03B` 165 | 50 | 1000 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-CUSTFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | `CBSTM03B` 190 | 500 | 1000 |
| `lunghezze-diverse:CBSTM03B:CBSTM03B.FD-ACCTFILE-REC->CBSTM03B.LK-M03B-AREA:LK-M03B-FLDT` | `CBSTM03B` 215 | 300 | 1000 |
| `lunghezze-diverse:CBTRN03C:CBTRN03C.FD-DATEPARM-REC->CBTRN03C.WS-DATEPARM-RECORD` | `CBTRN03C` 221 | 80 | 21 (troncamento) |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-PAGE-TOTALS->CBTRN03C.FD-REPTFILE-REC` | `CBTRN03C` 295 | 112 | 133 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-ACCOUNT-TOTALS->CBTRN03C.FD-REPTFILE-REC` | `CBTRN03C` 308 | 112 | 133 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-GRAND-TOTALS->CBTRN03C.FD-REPTFILE-REC` | `CBTRN03C` 320 | 112 | 133 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.REPORT-NAME-HEADER->CBTRN03C.FD-REPTFILE-REC` | `CBTRN03C` 325 | 115 | 133 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.TRANSACTION-HEADER-1->CBTRN03C.FD-REPTFILE-REC` | `CBTRN03C` 333 | 114 | 133 |
| `lunghezze-diverse:CBTRN03C:CVTRA07Y.TRANSACTION-DETAIL-REPORT->CBTRN03C.FD-REPTFILE-REC` | `CBTRN03C` 371 | 114 | 133 |

### `REDEFINES` più lunghe dell'area ridefinita

`ridefinizione-estesa:COADM02Y:CDEMO-ADMIN-OPTIONS`, `ridefinizione-estesa:COMEN02Y:CDEMO-MENU-OPTIONS`

Nelle due tabelle dei menu la vista con `OCCURS` è più lunga dei dati che ridefinisce: in `app/cpy/COADM02Y.cpy` `CDEMO-ADMIN-OPT OCCURS 9 TIMES` (righe 55-59, 9 × 45 = 405 byte) ridefinisce sei opzioni (righe 24-53, 6 × 45 = 270 byte); in `app/cpy/COMEN02Y.cpy` `CDEMO-MENU-OPT OCCURS 12 TIMES` (righe 93-98, 12 × 46 = 552 byte) ne ridefinisce undici (righe 23-90, 11 × 46 = 506 byte). cb2xml porta le radici a 407 e 554 byte. Sono aree di lavoro, non record di file: non hanno contratto. Come le tratti il compilatore IBM non è verificato.

### Altri dati osservati, senza identificativo

- `LISTCAT.txt` (estratto del 1° settembre 2022) cataloga 13 componenti `DATA`: per tutti, `KEYLEN`, `RKP`, `AXRKP`, `AVGLRECL`, `MAXLRECL` e `NONUNIQKEY` coincidono con le `DEFINE` dei JCL (nessuna discordanza di tipo `catalogo`). Non contiene `AWS.M2.CARDDEMO.EXPORT.DATA`, `AWS.M2.CARDDEMO.TRXFL.VSAM.KSDS`, le copie ESDS e RRDS di `USRSEC` né `AWS.CUSTDATA.CLUSTER`.
- `AWS.M2.CARDDEMO.TRANSACT.VSAM.KSDS` è definito due volte (`TRANFILE.jcl` riga 49, `TRANBKP.jcl` riga 54) e il suo indice alternativo due volte (`TRANFILE.jcl` riga 82, `TRANIDX.jcl` riga 25), con gli stessi attributi (nessuna discordanza `define-multiple`).
- `app/cpy/CUSTREC.cpy` ha caratteri TAB nelle righe 6-22; cb2xml lo legge e ne ricava lo stesso tracciato di `CVCUS01Y` (500 byte), con un solo nome diverso (`CUST-DOB-YYYYMMDD` invece di `CUST-DOB-YYYY-MM-DD`). GnuCOBOL invece lo rifiuta (esito di #1).
- `app/jcl/CREASTMT.JCL` riga 90 contiene, dopo `SPACE=(CYL,(1,1),RLSE),`, il testo residuo `00,RECFM=FB), ATA.VSAM.KSDS`.
