# Fixture dai dati di esempio di CardDemo

Documento generato da `./analysis/run.sh data-fixtures` (issue #5): non modificare a mano.

Ogni file di `app/data/ASCII/` e `app/data/EBCDIC/` e' decodificato campo per campo con il codec di #23 (`analysis/data-codec/glue/codec.py`; ASCII con il profilo `oracle-gnucobol`, EBCDIC con `zos-ebcdic`), guidato dal contratto del record (#3) attraverso l'adattatore di #43, senza riparare alcun valore. Le fixture sono in `analysis/data-fixtures/out/` (una riga per record; per campo nome, stato, valore e byte originali), con l'elenco delle anomalie di ogni file e le differenze fra le due codifiche.

## File, record, lunghezze, terminatori

| File | Contratto | Lung. | Byte | Record | Terminatori | Righe (lunghezza:righe) | Provenienza | Anomalie |
| --- | --- | ---: | ---: | ---: | --- | --- | --- | ---: |
| `acctdata.txt` | `CVACT01Y.ACCOUNT-RECORD` | 300 | 15050 | 50 | LF:1-50 | 300:1-50 | nessuno | 0 |
| `carddata.txt` | `CVACT02Y.CARD-RECORD` | 150 | 7550 | 50 | LF:1-50 | 150:1-50 | nessuno | 0 |
| `cardxref.txt` | `CVACT03Y.CARD-XREF-RECORD` | 50 | 1850 | 50 | LF:1-50 | 36:1-50 | nessuno | 50 |
| `custdata.txt` | `CVCUS01Y.CUSTOMER-RECORD` | 500 | 25050 | 50 | LF:1-50 | 500:1-50 | nessuno | 0 |
| `dailytran.txt` | `CVTRA06Y.DALYTRAN-RECORD` | 350 | 105300 | 300 | LF:1-300 | 350:1-300 | nessuno | 0 |
| `discgrp.txt` | `CVTRA02Y.DIS-GROUP-RECORD` | 50 | 2601 | 51 | LF:1-51 | 50:1-51 | nessuno | 0 |
| `tcatbal.txt` | `CVTRA01Y.TRAN-CAT-BAL-RECORD` | 50 | 2599 | 50 | CRLF:1-49,LF:50 | 50:1-50 | nessuno | 1 |
| `trancatg.txt` | `CVTRA04Y.TRAN-CAT-RECORD` | 60 | 1116 | 18 | CRLF:1-18 | 60:1-18 | nessuno | 0 |
| `trantype.txt` | `CVTRA03Y.TRAN-TYPE-RECORD` | 60 | 433 | 7 | CRLF:1-6,LF:7 | 60:1-7 | nessuno | 1 |
| `AWS.M2.CARDDEMO.ACCDATA.PS` | `CVACT01Y.ACCOUNT-RECORD` | 300 | 15000 | 50 | - | - | nessuno | 0 |
| `AWS.M2.CARDDEMO.ACCTDATA.PS` | `CVACT01Y.ACCOUNT-RECORD` | 300 | 15000 | 50 | - | - | carica (`app/jcl/ACCTFILE.jcl:57`) | 0 |
| `AWS.M2.CARDDEMO.CARDDATA.PS` | `CVACT02Y.CARD-RECORD` | 150 | 7500 | 50 | - | - | carica (`app/jcl/CARDFILE.jcl:71`) | 0 |
| `AWS.M2.CARDDEMO.CARDXREF.PS` | `CVACT03Y.CARD-XREF-RECORD` | 50 | 2500 | 50 | - | - | carica (`app/jcl/XREFFILE.jcl:60`) | 0 |
| `AWS.M2.CARDDEMO.CUSTDATA.PS` | `CVCUS01Y.CUSTOMER-RECORD` | 500 | 25000 | 50 | - | - | carica (`app/jcl/CUSTFILE.jcl:67`) | 0 |
| `AWS.M2.CARDDEMO.DALYTRAN.PS` | `CVTRA06Y.DALYTRAN-RECORD` | 350 | 105000 | 300 | - | - | consuma (`app/jcl/POSTTRAN.jcl:31`) | 0 |
| `AWS.M2.CARDDEMO.DALYTRAN.PS.INIT` | `CVTRA05Y.TRAN-RECORD` | 350 | 350 | 1 | - | - | carica (`app/jcl/TRANFILE.jcl:70`) | 3 |
| `AWS.M2.CARDDEMO.DISCGRP.PS` | `CVTRA02Y.DIS-GROUP-RECORD` | 50 | 2550 | 51 | - | - | carica (`app/jcl/DISCGRP.jcl:57`) | 0 |
| `AWS.M2.CARDDEMO.EXPORT.DATA.PS` | `CVEXPORT.EXPORT-RECORD` | 500 | 250000 | 500 | - | - | nessuno | 0 |
| `AWS.M2.CARDDEMO.TCATBALF.PS` | `CVTRA01Y.TRAN-CAT-BAL-RECORD` | 50 | 2500 | 50 | - | - | carica (`app/jcl/TCATBALF.jcl:57`) | 0 |
| `AWS.M2.CARDDEMO.TRANCATG.PS` | `CVTRA04Y.TRAN-CAT-RECORD` | 60 | 1080 | 18 | - | - | carica (`app/jcl/TRANCATG.jcl:57`) | 0 |
| `AWS.M2.CARDDEMO.TRANTYPE.PS` | `CVTRA03Y.TRAN-TYPE-RECORD` | 60 | 420 | 7 | - | - | carica (`app/jcl/TRANTYPE.jcl:57`) | 0 |
| `AWS.M2.CARDDEMO.USRSEC.PS` | `CSUSR01Y.SEC-USER-DATA` | 80 | 800 | 10 | - | - | carica (`app/jcl/DUSRSECJ.jcl:82`) | 0 |

File identici byte per byte (stessa impronta SHA-256): `AWS.M2.CARDDEMO.ACCDATA.PS` = `AWS.M2.CARDDEMO.ACCTDATA.PS`. Sono decodificati e confrontati entrambi, senza deduplicazione.

## Anomalie

| File | Tipo | Quante | Record |
| --- | --- | ---: | --- |
| `cardxref.txt` | riga-corta | 50 | 1-50 |
| `tcatbal.txt` | terminatore-minoritario | 1 | 50 |
| `trantype.txt` | terminatore-minoritario | 1 | 7 |
| `AWS.M2.CARDDEMO.DALYTRAN.PS.INIT` | campo-non-valido | 3 | 1 |

## Differenze fra ASCII ed EBCDIC

I record si abbinano per la chiave dell'inventario; nessuna differenza e' attesa a priori.

| ASCII | EBCDIC | Tipo | Campo | Chiave | ASCII | EBCDIC |
| --- | --- | --- | --- | --- | --- | --- |
| `acctdata.txt` | `AWS.M2.CARDDEMO.ACCDATA.PS` | valore-diverso | ACCT-ADDR-ZIP | `49` | `record 49: valido "A" "0"*9 [41 30*9]` | `record 49: valido "ZEROAPR   " [E9 C5 D9 D6 C1 D7 D9 40 40 40]` |
| `acctdata.txt` | `AWS.M2.CARDDEMO.ACCTDATA.PS` | valore-diverso | ACCT-ADDR-ZIP | `49` | `record 49: valido "A" "0"*9 [41 30*9]` | `record 49: valido "ZEROAPR   " [E9 C5 D9 D6 C1 D7 D9 40 40 40]` |
| `discgrp.txt` | `AWS.M2.CARDDEMO.DISCGRP.PS` | valore-diverso | DIS-INT-RATE | `"DEFAULT   "|"07"|1` | `record 34: valido 0.00 [30*5 7B]` | `record 34: valido 15.00 [F0 F0 F1 F5 F0 C0]` |

Riepilogo per coppia (le differenze `riempimento-uguale` sono i campi delle righe ASCII corte riempiti con spazi, uguali all'EBCDIC; sono elencate nelle fixture `out/confronto-*.tsv`):

- `acctdata.txt` / `AWS.M2.CARDDEMO.ACCDATA.PS`: valore-diverso 1
- `acctdata.txt` / `AWS.M2.CARDDEMO.ACCTDATA.PS`: valore-diverso 1
- `carddata.txt` / `AWS.M2.CARDDEMO.CARDDATA.PS`: nessuna differenza
- `cardxref.txt` / `AWS.M2.CARDDEMO.CARDXREF.PS`: riempimento-uguale 50
- `custdata.txt` / `AWS.M2.CARDDEMO.CUSTDATA.PS`: nessuna differenza
- `dailytran.txt` / `AWS.M2.CARDDEMO.DALYTRAN.PS`: nessuna differenza
- `discgrp.txt` / `AWS.M2.CARDDEMO.DISCGRP.PS`: valore-diverso 1
- `tcatbal.txt` / `AWS.M2.CARDDEMO.TCATBALF.PS`: nessuna differenza
- `trancatg.txt` / `AWS.M2.CARDDEMO.TRANCATG.PS`: nessuna differenza
- `trantype.txt` / `AWS.M2.CARDDEMO.TRANTYPE.PS`: nessuna differenza

## Decisioni di decodifica

- **Riempimento delle righe ASCII corte**: spazi (0x20) a destra fino alla lunghezza del record. Nessun JCL del repository carica i file `.txt` (provenienza `nessuno` verificata), quindi il JCL non determina la regola: e' una scelta dichiarata, applicata in un passo separato (`RIEMPI`). Le fixture distinguono i byte del file da quelli aggiunti (colonne 3 e 4, e l'origine `riempimento` del campo).
- **Terminatori**: si legge ogni riga fino a LF; un CR subito prima di LF e' parte del terminatore (CRLF). I terminatori di ogni riga sono nelle fixture (colonna 2) e nella tabella sopra.
- **EXPORT.DATA.PS**: la vista attiva si sceglie dal tipo di record come `CBIMPORT.cbl` (righe 272-284, `analysis/data-fixtures/viste-export.tsv`); si decodificano i campi comuni e quelli della sola vista attiva. Un tipo non previsto avrebbe solo i campi comuni e un'anomalia. L'area `EXPORT-TIMESTAMP-R` ridefinisce un campo comune, decodificato intero.
- **DALYTRAN.PS.INIT**: decodificato con il contratto del KSDS in cui `TRANFILE.jcl` lo carica (`CVTRA05Y.TRAN-RECORD`); i byte a zero binario restano tali e i campi numerici risultano non validi.
- **Chiavi**: la chiave di abbinamento e' la KEYS del JCL; per il giornaliero (sequenziale) `DALYTRAN-ID` e' una scelta; per l'export la KEYS(4 28) si usa com'e', in byte, anche se taglia due campi.

## Chiavi

| File | Chiave | Definizione | Record | Distinti | Unica |
| --- | --- | --- | ---: | ---: | --- |
| `acctdata.txt` | abbinamento | `ACCT-ID` | 50 | 50 | si |
| `carddata.txt` | abbinamento | `CARD-NUM` | 50 | 50 | si |
| `carddata.txt` | alternativa | `@16+11 CARD-ACCT-ID` | 50 | 50 | si |
| `cardxref.txt` | abbinamento | `XREF-CARD-NUM` | 50 | 50 | si |
| `cardxref.txt` | alternativa | `@25+11 XREF-ACCT-ID` | 50 | 50 | si |
| `custdata.txt` | abbinamento | `CUST-ID` | 50 | 50 | si |
| `dailytran.txt` | abbinamento | `DALYTRAN-ID` | 300 | 300 | si |
| `discgrp.txt` | abbinamento | `DIS-ACCT-GROUP-ID+DIS-TRAN-TYPE-CD+DIS-TRAN-CAT-CD` | 51 | 51 | si |
| `tcatbal.txt` | abbinamento | `TRANCAT-ACCT-ID+TRANCAT-TYPE-CD+TRANCAT-CD` | 50 | 50 | si |
| `trancatg.txt` | abbinamento | `TRAN-TYPE-CD+TRAN-CAT-CD` | 18 | 18 | si |
| `trantype.txt` | abbinamento | `TRAN-TYPE` | 7 | 7 | si |
| `AWS.M2.CARDDEMO.ACCDATA.PS` | abbinamento | `ACCT-ID` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.ACCTDATA.PS` | abbinamento | `ACCT-ID` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.CARDDATA.PS` | abbinamento | `CARD-NUM` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.CARDDATA.PS` | alternativa | `@16+11 CARD-ACCT-ID` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.CARDXREF.PS` | abbinamento | `XREF-CARD-NUM` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.CARDXREF.PS` | alternativa | `@25+11 XREF-ACCT-ID` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.CUSTDATA.PS` | abbinamento | `CUST-ID` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.DALYTRAN.PS` | abbinamento | `DALYTRAN-ID` | 300 | 300 | si |
| `AWS.M2.CARDDEMO.DALYTRAN.PS.INIT` | abbinamento | `TRAN-ID` | 1 | 1 | si |
| `AWS.M2.CARDDEMO.DALYTRAN.PS.INIT` | alternativa | `@304+26 TRAN-PROC-TS` | 1 | 1 | si |
| `AWS.M2.CARDDEMO.DISCGRP.PS` | abbinamento | `DIS-ACCT-GROUP-ID+DIS-TRAN-TYPE-CD+DIS-TRAN-CAT-CD` | 51 | 51 | si |
| `AWS.M2.CARDDEMO.EXPORT.DATA.PS` | abbinamento | `@28+4` | 500 | 500 | si |
| `AWS.M2.CARDDEMO.TCATBALF.PS` | abbinamento | `TRANCAT-ACCT-ID+TRANCAT-TYPE-CD+TRANCAT-CD` | 50 | 50 | si |
| `AWS.M2.CARDDEMO.TRANCATG.PS` | abbinamento | `TRAN-TYPE-CD+TRAN-CAT-CD` | 18 | 18 | si |
| `AWS.M2.CARDDEMO.TRANTYPE.PS` | abbinamento | `TRAN-TYPE` | 7 | 7 | si |
| `AWS.M2.CARDDEMO.USRSEC.PS` | abbinamento | `SEC-USR-ID` | 10 | 10 | si |

## Conteggi

| File | Record dalla dimensione | Righe fisiche | Decodificati | Negli attesi |
| --- | ---: | ---: | ---: | ---: |
| `acctdata.txt` | - | 50 | 50 | 3 |
| `carddata.txt` | - | 50 | 50 | 2 |
| `cardxref.txt` | - | 50 | 50 | 2 |
| `custdata.txt` | - | 50 | 50 | 2 |
| `dailytran.txt` | - | 300 | 300 | 3 |
| `discgrp.txt` | - | 51 | 51 | 3 |
| `tcatbal.txt` | - | 50 | 50 | 2 |
| `trancatg.txt` | - | 18 | 18 | 2 |
| `trantype.txt` | - | 7 | 7 | 2 |
| `AWS.M2.CARDDEMO.ACCDATA.PS` | 50 | - | 50 | 3 |
| `AWS.M2.CARDDEMO.ACCTDATA.PS` | 50 | - | 50 | 3 |
| `AWS.M2.CARDDEMO.CARDDATA.PS` | 50 | - | 50 | 2 |
| `AWS.M2.CARDDEMO.CARDXREF.PS` | 50 | - | 50 | 2 |
| `AWS.M2.CARDDEMO.CUSTDATA.PS` | 50 | - | 50 | 2 |
| `AWS.M2.CARDDEMO.DALYTRAN.PS` | 300 | - | 300 | 3 |
| `AWS.M2.CARDDEMO.DALYTRAN.PS.INIT` | 1 | - | 1 | 1 |
| `AWS.M2.CARDDEMO.DISCGRP.PS` | 51 | - | 51 | 3 |
| `AWS.M2.CARDDEMO.EXPORT.DATA.PS` | 500 | - | 500 | 7 |
| `AWS.M2.CARDDEMO.TCATBALF.PS` | 50 | - | 50 | 2 |
| `AWS.M2.CARDDEMO.TRANCATG.PS` | 18 | - | 18 | 2 |
| `AWS.M2.CARDDEMO.TRANTYPE.PS` | 7 | - | 7 | 2 |
| `AWS.M2.CARDDEMO.USRSEC.PS` | 10 | - | 10 | 2 |

## Limiti

- Il riempimento delle righe ASCII corte e' una scelta, non un fatto del sorgente.
- Le fixture descrivono i byte dei file del repository; il comportamento dei programmi su questi dati (oracle, #9) e il caricamento nei file indicizzati (issue successiva) sono fuori ambito.
- Gli attesi a mano coprono alcuni record per file (primo, ultimo, negativi, anomali, uno per tipo dell'export, i record con differenze ASCII/EBCDIC); gli altri record sono coperti dai controlli d'insieme (totali, chiavi, ricodifica) e dal confronto con le fixture versionate.
