# Inventario dei comandi EXEC CICS di CardDemo

Generato da `./analysis/run.sh inventory-cics` (issue #22): non modificare a mano. Controlli: `./analysis/run.sh inventory-cics --check`. Il grafo e' `docs/legacy-map/graph-cics.json` (formato in `graph-cics.schema.json`); fa riferimento ai nodi di `graph.json` (#2) per identificativo e non lo modifica.

## Strumento di estrazione

Prima di scrivere un estrattore si e' verificato se ProLeap (gia' adottato in #1 per le COPY) espone i blocchi `EXEC CICS ... END-EXEC` con riga e testo. Il parser del suo preprocessore ha la regola e i token che servono (output di `CicsLister --regole` sull'immagine costruita):

| voce | nome | stato |
| --- | --- | --- |
| regola | `execCicsStatement` | presente |
| token | `EXEC` | presente |
| token | `CICS` | presente |
| token | `END_EXEC` | presente |

Sul file di prova `analysis/inventory-cics/fixtures/legacy/app/cbl/FIXCICS.cbl` la colla `CicsLister` (che usa solo classi di ProLeap) restituisce 34 blocchi con riga di `EXEC`, riga di `END-EXEC`, colonna e testo: la riga 53 (blocco commentato, `*` in colonna 7) non compare; la riga 54 (`*>` seguito da un blocco) non compare; la riga 55 (blocco dentro un letterale) non compare; la riga 68 ha 2 blocchi (colonne 12, 42); 3 blocchi occupano piu' righe. Quindi ProLeap si usa: nessun riconoscitore di blocchi scritto in proprio. La colla scrive il testo tra `CICS` e `END-EXEC`; comando e opzioni li ricava `glue/extract.py` con la regola dichiarata in testa al file. Il controllo indipendente (`crosscheck.sh`, awk) riconta i blocchi riga per riga.

Limite trovato: il preprocessore di ProLeap non conosce `EXEC DLI` (IMS). Al primo errore di sintassi la sua regola iniziale termina e, con il recupero standard di ANTLR, tutti i blocchi successivi del file andrebbero persi. La colla scarta il solo token in errore e riprende l'analisi dal token successivo (nessuna regola della grammatica cambia); errori e riprese sono dichiarati in ogni risposta. File in cui e' successo:

| file | errori di sintassi | riga del primo | riprese | blocchi dopo il primo errore (persi senza ripresa) |
| --- | ---: | ---: | ---: | ---: |
| app/app-authorization-ims-db2-mq/cbl/CBPAUP0C.cbl | 10 | 223 | 5 | 0 |
| app/app-authorization-ims-db2-mq/cbl/COPAUA0C.cbl | 16 | 293 | 8 | 10 |
| app/app-authorization-ims-db2-mq/cbl/COPAUS0C.cbl | 12 | 461 | 6 | 8 |
| app/app-authorization-ims-db2-mq/cbl/COPAUS1C.cbl | 14 | 439 | 7 | 2 |

Totale dei blocchi che senza la ripresa sarebbero stati persi: 20.

## Totali

- blocchi `EXEC CICS`: **240** in **25** file (25 programmi, 0 copybook);
- modulo `app-authorization-ims-db2-mq`: 33 blocchi;
- modulo `app-transaction-type-db2`: 24 blocchi;
- modulo `app-vsam-mq`: 9 blocchi;
- modulo `base`: 174 blocchi;
- file analizzati (programmi e copybook del manifesto): 106;
- comandi sui file: 58, con nome di file costante 58, letterale 0, non risolto 0;
- `RETURN` con `TRANSID`: 24, costante 24, letterale 0, non risolto 0;
- operandi di bersaglio: 211; letterali 70, costanti 103, non risolti 38; archi 173; nodi nuovi 52.

## Comandi trovati

Elenco prodotto dall'estrazione, non scritto a mano.

| comando | categoria | blocchi |
| --- | --- | ---: |
| `ASKTIME` | altro | 5 |
| `ASSIGN` | altro | 2 |
| `FORMATTIME` | altro | 5 |
| `HANDLE ABEND` | altro | 10 |
| `HANDLE CONDITION` | altro | 1 |
| `INQUIRE PROGRAM` | altro | 1 |
| `RETRIEVE` | altro | 3 |
| `SEND` | altro | 5 |
| `WRITEQ TD` | coda | 2 |
| `DELETE` | file | 1 |
| `ENDBR` | file | 6 |
| `READ` | file | 27 |
| `READNEXT` | file | 4 |
| `READPREV` | file | 6 |
| `REWRITE` | file | 5 |
| `STARTBR` | file | 6 |
| `WRITE` | file | 3 |
| `RECEIVE MAP` | mappe | 21 |
| `SEND MAP` | mappe | 26 |
| `SEND TEXT` | mappe | 9 |
| `ABEND` | transazione | 5 |
| `SYNCPOINT` | transazione | 14 |
| `SYNCPOINT ROLLBACK` | transazione | 2 |
| `LINK` | trasferimento | 1 |
| `RETURN` | trasferimento | 38 |
| `XCTL` | trasferimento | 32 |

## Per programma

Per ogni programma con blocchi propri o ereditati da un copybook (archi COPY di `graph.json`). Un blocco che sta in un copybook e' un'occorrenza del copybook: qui e' ripetuto sotto ogni programma che lo include.

### `COPAUA0C` (app/app-authorization-ims-db2-mq/cbl/COPAUA0C.cbl)

- Trasferimenti:
  - riga 226: `RETURN`: nessun bersaglio
  - riga 1021: `RETURN`: nessun bersaglio
- File:
  - riga 477: `READ` lettura: FILE `cics-file:CCXREF` (costante)
  - riga 525: `READ` lettura: FILE `cics-file:ACCTDAT` (costante)
  - riga 573: `READ` lettura: FILE `cics-file:CUSTDAT` (costante)
- Code:
  - riga 1001: `WRITEQ TD` TD: QUEUE `cics-queue:TD/CSSL` (letterale)
- `SYNCPOINT`, rollback e `ABEND`: righe 334 (`SYNCPOINT`)

### `COPAUS0C` (app/app-authorization-ims-db2-mq/cbl/COPAUS0C.cbl)

- Trasferimenti:
  - riga 254: `RETURN`: TRANSID `transaction:CPVS` (costante)
  - riga 322: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 674: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 695: `SEND MAP`: MAP `cics-map:COPAU00/COPAU0A` (letterale); MAPSET `cics-mapset:COPAU00` (letterale)
  - riga 703: `SEND MAP`: MAP `cics-map:COPAU00/COPAU0A` (letterale); MAPSET `cics-mapset:COPAU00` (letterale)
  - riga 715: `RECEIVE MAP`: MAP `cics-map:COPAU00/COPAU0A` (letterale); MAPSET `cics-mapset:COPAU00` (letterale)
- File:
  - riga 818: `READ` lettura: FILE `cics-file:CXACAIX` (costante)
  - riga 869: `READ` lettura: FILE `cics-file:ACCTDAT` (costante)
  - riga 920: `READ` lettura: FILE `cics-file:CUSTDAT` (costante)
- `SYNCPOINT`, rollback e `ABEND`: righe 686 (`SYNCPOINT`)

### `COPAUS1C` (app/app-authorization-ims-db2-mq/cbl/COPAUS1C.cbl)

- Trasferimenti:
  - riga 202: `RETURN`: TRANSID `transaction:CPVD` (costante)
  - riga 248: `LINK`: PROGRAM `program:COPAUS2C` (costante)
  - riga 367: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 381: `SEND MAP`: MAP `cics-map:COPAU01/COPAU1A` (letterale); MAPSET `cics-mapset:COPAU01` (letterale)
  - riga 389: `SEND MAP`: MAP `cics-map:COPAU01/COPAU1A` (letterale); MAPSET `cics-mapset:COPAU01` (letterale)
  - riga 400: `RECEIVE MAP`: MAP `cics-map:COPAU01/COPAU1A` (letterale); MAPSET `cics-mapset:COPAU01` (letterale)
- `SYNCPOINT`, rollback e `ABEND`: righe 558 (`SYNCPOINT`), 566 (`SYNCPOINT ROLLBACK`)

### `COPAUS2C` (app/app-authorization-ims-db2-mq/cbl/COPAUS2C.cbl)

- Trasferimenti:
  - riga 218: `RETURN`: nessun bersaglio

### `COTRTLIC` (app/app-transaction-type-db2/cbl/COTRTLIC.cbl)

- Trasferimenti:
  - riga 620: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 648: `XCTL`: PROGRAM `program:COTRTUPC` (costante)
  - riga 910: `RETURN`: TRANSID `transaction:CTLI` (costante)
  - riga 2074: `RETURN`: nessun bersaglio
  - riga 2093: `RETURN`: nessun bersaglio
- Mappe:
  - riga 931: `RECEIVE MAP`: MAP `cics-map:COTRTLI/CTRTLIA` (costante); MAPSET `cics-mapset:COTRTLI` (costante)
  - riga 1588: `SEND MAP`: MAP `cics-map:COTRTLI/CTRTLIA` (costante); MAPSET `cics-mapset:COTRTLI` (costante)
  - riga 2067: `SEND TEXT`: nessun bersaglio
  - riga 2086: `SEND TEXT`: nessun bersaglio
- `SYNCPOINT`, rollback e `ABEND`: righe 616 (`SYNCPOINT`), 1856 (`SYNCPOINT`), 1909 (`SYNCPOINT`)

### `COTRTUPC` (app/app-transaction-type-db2/cbl/COTRTUPC.cbl)

- Trasferimenti:
  - riga 457: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 567: `RETURN`: TRANSID `transaction:CTTU` (costante)
- Mappe:
  - riga 642: `RECEIVE MAP`: MAP `cics-map:COTRTUP/CTRTUPA` (costante); MAPSET `cics-mapset:COTRTUP` (costante)
  - riga 1433: `SEND MAP`: MAP `CCARD-NEXT-MAP` non risolto (senza-value-letterale); MAPSET `CCARD-NEXT-MAPSET` non risolto (senza-value-letterale)
- `SYNCPOINT`, rollback e `ABEND`: righe 453 (`SYNCPOINT`), 1557 (`SYNCPOINT`), 1606 (`SYNCPOINT`), 1637 (`SYNCPOINT`), 1695 (`ABEND`)

### `COACCT01` (app/app-vsam-mq/cbl/COACCT01.cbl)

- Trasferimenti:
  - riga 549: `RETURN`: nessun bersaglio
- File:
  - riga 396: `READ` lettura: FILE `cics-file:ACCTDAT` (costante)
- `SYNCPOINT`, rollback e `ABEND`: righe 326 (`SYNCPOINT`)

### `CODATE01` (app/app-vsam-mq/cbl/CODATE01.cbl)

- Trasferimenti:
  - riga 453: `RETURN`: nessun bersaglio
- `SYNCPOINT`, rollback e `ABEND`: righe 275 (`SYNCPOINT`)

### `COACTUPC` (app/cbl/COACTUPC.cbl)

- Trasferimenti:
  - riga 956: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 1015: `RETURN`: TRANSID `transaction:CAUP` (costante)
- Mappe:
  - riga 1040: `RECEIVE MAP`: MAP `cics-map:COACTUP/CACTUPA` (costante); MAPSET `cics-mapset:COACTUP` (costante)
  - riga 3594: `SEND MAP`: MAP `CCARD-NEXT-MAP` non risolto (senza-value-letterale); MAPSET `CCARD-NEXT-MAPSET` non risolto (senza-value-letterale)
- File:
  - riga 3654: `READ` lettura: FILE `cics-file:CXACAIX` (costante)
  - riga 3703: `READ` lettura: FILE `cics-file:ACCTDAT` (costante)
  - riga 3753: `READ` lettura: FILE `cics-file:CUSTDAT` (costante)
  - riga 3894: `READ` lettura-update: FILE `cics-file:ACCTDAT` (costante)
  - riga 3921: `READ` lettura-update: FILE `cics-file:CUSTDAT` (costante)
  - riga 4065: `REWRITE` riscrittura: FILE `cics-file:ACCTDAT` (costante)
  - riga 4085: `REWRITE` riscrittura: FILE `cics-file:CUSTDAT` (costante)
- `SYNCPOINT`, rollback e `ABEND`: righe 952 (`SYNCPOINT`), 4099 (`SYNCPOINT ROLLBACK`), 4222 (`ABEND`)

### `COACTVWC` (app/cbl/COACTVWC.cbl)

- Trasferimenti:
  - riga 349: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 402: `RETURN`: TRANSID `transaction:CAVW` (costante)
  - riga 885: `RETURN`: nessun bersaglio
  - riga 904: `RETURN`: nessun bersaglio
- Mappe:
  - riga 583: `SEND MAP`: MAP `CCARD-NEXT-MAP` non risolto (senza-value-letterale); MAPSET `CCARD-NEXT-MAPSET` non risolto (senza-value-letterale)
  - riga 611: `RECEIVE MAP`: MAP `cics-map:COACTVW/CACTVWA` (costante); MAPSET `cics-mapset:COACTVW` (costante)
  - riga 878: `SEND TEXT`: nessun bersaglio
  - riga 897: `SEND TEXT`: nessun bersaglio
- File:
  - riga 727: `READ` lettura: FILE `cics-file:CXACAIX` (costante)
  - riga 776: `READ` lettura: FILE `cics-file:ACCTDAT` (costante)
  - riga 826: `READ` lettura: FILE `cics-file:CUSTDAT` (costante)
- `SYNCPOINT`, rollback e `ABEND`: righe 934 (`ABEND`)

### `COADM01C` (app/cbl/COADM01C.cbl)

- Trasferimenti:
  - riga 111: `RETURN`: TRANSID `transaction:CA00` (costante)
  - riga 145: `XCTL`: PROGRAM `CDEMO-ADMIN-OPT-PGMNAME(WS-OPTION)` non risolto (espressione)
  - riga 168: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 280: `RETURN`: TRANSID `transaction:CA00` (costante)
- Mappe:
  - riga 182: `SEND MAP`: MAP `cics-map:COADM01/COADM1A` (letterale); MAPSET `cics-mapset:COADM01` (letterale)
  - riga 194: `RECEIVE MAP`: MAP `cics-map:COADM01/COADM1A` (letterale); MAPSET `cics-mapset:COADM01` (letterale)

### `COBIL00C` (app/cbl/COBIL00C.cbl)

- Trasferimenti:
  - riga 146: `RETURN`: TRANSID `transaction:CB00` (costante)
  - riga 281: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 295: `SEND MAP`: MAP `cics-map:COBIL00/COBIL0A` (letterale); MAPSET `cics-mapset:COBIL00` (letterale)
  - riga 308: `RECEIVE MAP`: MAP `cics-map:COBIL00/COBIL0A` (letterale); MAPSET `cics-mapset:COBIL00` (letterale)
- File:
  - riga 345: `READ` lettura-update: FILE `cics-file:ACCTDAT` (costante)
  - riga 379: `REWRITE` riscrittura: FILE `cics-file:ACCTDAT` (costante)
  - riga 410: `READ` lettura: FILE `cics-file:CXACAIX` (costante)
  - riga 443: `STARTBR` scorrimento-inizio: FILE `cics-file:TRANSACT` (costante)
  - riga 474: `READPREV` scorrimento-indietro: FILE `cics-file:TRANSACT` (costante)
  - riga 503: `ENDBR` scorrimento-fine: FILE `cics-file:TRANSACT` (costante)
  - riga 512: `WRITE` scrittura: FILE `cics-file:TRANSACT` (costante)

### `COCRDLIC` (app/cbl/COCRDLIC.cbl)

- Trasferimenti:
  - riga 402: `XCTL`: PROGRAM `program:COMEN01C` (costante)
  - riga 538: `XCTL`: PROGRAM `CCARD-NEXT-PROG` non risolto (senza-value-letterale)
  - riga 566: `XCTL`: PROGRAM `CCARD-NEXT-PROG` non risolto (senza-value-letterale)
  - riga 615: `RETURN`: TRANSID `transaction:CCLI` (costante)
  - riga 1430: `RETURN`: nessun bersaglio
  - riga 1449: `RETURN`: nessun bersaglio
- Mappe:
  - riga 939: `SEND MAP`: MAP `cics-map:COCRDLI/CCRDLIA` (costante); MAPSET `cics-mapset:COCRDLI` (costante)
  - riga 963: `RECEIVE MAP`: MAP `cics-map:COCRDLI/CCRDLIA` (costante); MAPSET `cics-mapset:COCRDLI` (costante)
  - riga 1423: `SEND TEXT`: nessun bersaglio
  - riga 1442: `SEND TEXT`: nessun bersaglio
- File:
  - riga 1129: `STARTBR` scorrimento-inizio: FILE `cics-file:CARDDAT` (costante)
  - riga 1146: `READNEXT` scorrimento-avanti: FILE `cics-file:CARDDAT` (costante)
  - riga 1197: `READNEXT` scorrimento-avanti: FILE `cics-file:CARDDAT` (costante)
  - riga 1258: `ENDBR` scorrimento-fine: FILE `cics-file:CARDDAT` (costante)
  - riga 1273: `STARTBR` scorrimento-inizio: FILE `cics-file:CARDDAT` (costante)
  - riga 1294: `READPREV` scorrimento-indietro: FILE `cics-file:CARDDAT` (costante)
  - riga 1322: `READPREV` scorrimento-indietro: FILE `cics-file:CARDDAT` (costante)
  - riga 1375: `ENDBR` scorrimento-fine: FILE `cics-file:CARDDAT` (costante)

### `COCRDSLC` (app/cbl/COCRDSLC.cbl)

- Trasferimenti:
  - riga 331: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 402: `RETURN`: TRANSID `transaction:CCDL` (costante)
  - riga 828: `RETURN`: nessun bersaglio
  - riga 846: `RETURN`: nessun bersaglio
- Mappe:
  - riga 569: `SEND MAP`: MAP `CCARD-NEXT-MAP` non risolto (senza-value-letterale); MAPSET `CCARD-NEXT-MAPSET` non risolto (senza-value-letterale)
  - riga 597: `RECEIVE MAP`: MAP `cics-map:COCRDSL/CCRDSLA` (costante); MAPSET `cics-mapset:COCRDSL` (costante)
  - riga 821: `SEND TEXT`: nessun bersaglio
  - riga 839: `SEND TEXT`: nessun bersaglio
- File:
  - riga 742: `READ` lettura: FILE `cics-file:CARDDAT` (costante)
  - riga 783: `READ` lettura: FILE `cics-file:CARDAIX` (costante)
- `SYNCPOINT`, rollback e `ABEND`: righe 875 (`ABEND`)

### `COCRDUPC` (app/cbl/COCRDUPC.cbl)

- Trasferimenti:
  - riga 473: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 554: `RETURN`: TRANSID `transaction:CCUP` (costante)
- Mappe:
  - riga 579: `RECEIVE MAP`: MAP `cics-map:COCRDUP/CCRDUPA` (costante); MAPSET `cics-mapset:COCRDUP` (costante)
  - riga 1329: `SEND MAP`: MAP `CCARD-NEXT-MAP` non risolto (senza-value-letterale); MAPSET `CCARD-NEXT-MAPSET` non risolto (senza-value-letterale)
- File:
  - riga 1382: `READ` lettura: FILE `cics-file:CARDDAT` (costante)
  - riga 1427: `READ` lettura-update: FILE `cics-file:CARDDAT` (costante)
  - riga 1477: `REWRITE` riscrittura: FILE `cics-file:CARDDAT` (costante)
- `SYNCPOINT`, rollback e `ABEND`: righe 469 (`SYNCPOINT`), 1550 (`ABEND`)

### `COMEN01C` (app/cbl/COMEN01C.cbl)

- Trasferimenti:
  - riga 107: `RETURN`: TRANSID `transaction:CM00` (costante)
  - riga 156: `XCTL`: PROGRAM `CDEMO-MENU-OPT-PGMNAME(WS-OPTION)` non risolto (espressione)
  - riga 184: `XCTL`: PROGRAM `CDEMO-MENU-OPT-PGMNAME(WS-OPTION)` non risolto (espressione)
  - riga 201: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 215: `SEND MAP`: MAP `cics-map:COMEN01/COMEN1A` (letterale); MAPSET `cics-mapset:COMEN01` (letterale)
  - riga 227: `RECEIVE MAP`: MAP `cics-map:COMEN01/COMEN1A` (letterale); MAPSET `cics-mapset:COMEN01` (letterale)

### `CORPT00C` (app/cbl/CORPT00C.cbl)

- Trasferimenti:
  - riga 199: `RETURN`: TRANSID `transaction:CR00` (costante)
  - riga 548: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 587: `RETURN`: TRANSID `transaction:CR00` (costante)
- Mappe:
  - riga 563: `SEND MAP`: MAP `cics-map:CORPT00/CORPT0A` (letterale); MAPSET `cics-mapset:CORPT00` (letterale)
  - riga 571: `SEND MAP`: MAP `cics-map:CORPT00/CORPT0A` (letterale); MAPSET `cics-mapset:CORPT00` (letterale)
  - riga 598: `RECEIVE MAP`: MAP `cics-map:CORPT00/CORPT0A` (letterale); MAPSET `cics-mapset:CORPT00` (letterale)
- Code:
  - riga 517: `WRITEQ TD` TD: QUEUE `cics-queue:TD/JOBS` (letterale)

### `COSGN00C` (app/cbl/COSGN00C.cbl)

- Trasferimenti:
  - riga 98: `RETURN`: TRANSID `transaction:CC00` (costante)
  - riga 171: `RETURN`: nessun bersaglio
  - riga 231: `XCTL`: PROGRAM `program:COADM01C` (letterale)
  - riga 236: `XCTL`: PROGRAM `program:COMEN01C` (letterale)
- Mappe:
  - riga 110: `RECEIVE MAP`: MAP `cics-map:COSGN00/COSGN0A` (letterale); MAPSET `cics-mapset:COSGN00` (letterale)
  - riga 151: `SEND MAP`: MAP `cics-map:COSGN00/COSGN0A` (letterale); MAPSET `cics-mapset:COSGN00` (letterale)
  - riga 164: `SEND TEXT`: nessun bersaglio
- File:
  - riga 211: `READ` lettura: FILE `cics-file:USRSEC` (costante)

### `COTRN00C` (app/cbl/COTRN00C.cbl)

- Trasferimenti:
  - riga 138: `RETURN`: TRANSID `transaction:CT00` (costante)
  - riga 192: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 518: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 534: `SEND MAP`: MAP `cics-map:COTRN00/COTRN0A` (letterale); MAPSET `cics-mapset:COTRN00` (letterale)
  - riga 542: `SEND MAP`: MAP `cics-map:COTRN00/COTRN0A` (letterale); MAPSET `cics-mapset:COTRN00` (letterale)
  - riga 556: `RECEIVE MAP`: MAP `cics-map:COTRN00/COTRN0A` (letterale); MAPSET `cics-mapset:COTRN00` (letterale)
- File:
  - riga 593: `STARTBR` scorrimento-inizio: FILE `cics-file:TRANSACT` (costante)
  - riga 626: `READNEXT` scorrimento-avanti: FILE `cics-file:TRANSACT` (costante)
  - riga 660: `READPREV` scorrimento-indietro: FILE `cics-file:TRANSACT` (costante)
  - riga 694: `ENDBR` scorrimento-fine: FILE `cics-file:TRANSACT` (costante)

### `COTRN01C` (app/cbl/COTRN01C.cbl)

- Trasferimenti:
  - riga 136: `RETURN`: TRANSID `transaction:CT01` (costante)
  - riga 205: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 219: `SEND MAP`: MAP `cics-map:COTRN01/COTRN1A` (letterale); MAPSET `cics-mapset:COTRN01` (letterale)
  - riga 232: `RECEIVE MAP`: MAP `cics-map:COTRN01/COTRN1A` (letterale); MAPSET `cics-mapset:COTRN01` (letterale)
- File:
  - riga 269: `READ` lettura-update: FILE `cics-file:TRANSACT` (costante)

### `COTRN02C` (app/cbl/COTRN02C.cbl)

- Trasferimenti:
  - riga 156: `RETURN`: TRANSID `transaction:CT02` (costante)
  - riga 508: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 530: `RETURN`: TRANSID `transaction:CT02` (costante)
- Mappe:
  - riga 522: `SEND MAP`: MAP `cics-map:COTRN02/COTRN2A` (letterale); MAPSET `cics-mapset:COTRN02` (letterale)
  - riga 541: `RECEIVE MAP`: MAP `cics-map:COTRN02/COTRN2A` (letterale); MAPSET `cics-mapset:COTRN02` (letterale)
- File:
  - riga 578: `READ` lettura: FILE `cics-file:CXACAIX` (costante)
  - riga 611: `READ` lettura: FILE `cics-file:CCXREF` (costante)
  - riga 644: `STARTBR` scorrimento-inizio: FILE `cics-file:TRANSACT` (costante)
  - riga 675: `READPREV` scorrimento-indietro: FILE `cics-file:TRANSACT` (costante)
  - riga 704: `ENDBR` scorrimento-fine: FILE `cics-file:TRANSACT` (costante)
  - riga 713: `WRITE` scrittura: FILE `cics-file:TRANSACT` (costante)

### `COUSR00C` (app/cbl/COUSR00C.cbl)

- Trasferimenti:
  - riga 141: `RETURN`: TRANSID `transaction:CU00` (costante)
  - riga 196: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 206: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
  - riga 514: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 529: `SEND MAP`: MAP `cics-map:COUSR00/COUSR0A` (letterale); MAPSET `cics-mapset:COUSR00` (letterale)
  - riga 537: `SEND MAP`: MAP `cics-map:COUSR00/COUSR0A` (letterale); MAPSET `cics-mapset:COUSR00` (letterale)
  - riga 551: `RECEIVE MAP`: MAP `cics-map:COUSR00/COUSR0A` (letterale); MAPSET `cics-mapset:COUSR00` (letterale)
- File:
  - riga 588: `STARTBR` scorrimento-inizio: FILE `cics-file:USRSEC` (costante)
  - riga 621: `READNEXT` scorrimento-avanti: FILE `cics-file:USRSEC` (costante)
  - riga 655: `READPREV` scorrimento-indietro: FILE `cics-file:USRSEC` (costante)
  - riga 689: `ENDBR` scorrimento-fine: FILE `cics-file:USRSEC` (costante)

### `COUSR01C` (app/cbl/COUSR01C.cbl)

- Trasferimenti:
  - riga 107: `RETURN`: TRANSID `transaction:CU01` (costante)
  - riga 175: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 190: `SEND MAP`: MAP `cics-map:COUSR01/COUSR1A` (letterale); MAPSET `cics-mapset:COUSR01` (letterale)
  - riga 203: `RECEIVE MAP`: MAP `cics-map:COUSR01/COUSR1A` (letterale); MAPSET `cics-mapset:COUSR01` (letterale)
- File:
  - riga 240: `WRITE` scrittura: FILE `cics-file:USRSEC` (costante)

### `COUSR02C` (app/cbl/COUSR02C.cbl)

- Trasferimenti:
  - riga 135: `RETURN`: TRANSID `transaction:CU02` (costante)
  - riga 258: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 272: `SEND MAP`: MAP `cics-map:COUSR02/COUSR2A` (letterale); MAPSET `cics-mapset:COUSR02` (letterale)
  - riga 285: `RECEIVE MAP`: MAP `cics-map:COUSR02/COUSR2A` (letterale); MAPSET `cics-mapset:COUSR02` (letterale)
- File:
  - riga 322: `READ` lettura-update: FILE `cics-file:USRSEC` (costante)
  - riga 360: `REWRITE` riscrittura: FILE `cics-file:USRSEC` (costante)

### `COUSR03C` (app/cbl/COUSR03C.cbl)

- Trasferimenti:
  - riga 134: `RETURN`: TRANSID `transaction:CU03` (costante)
  - riga 205: `XCTL`: PROGRAM `CDEMO-TO-PROGRAM` non risolto (senza-value-letterale)
- Mappe:
  - riga 219: `SEND MAP`: MAP `cics-map:COUSR03/COUSR3A` (letterale); MAPSET `cics-mapset:COUSR03` (letterale)
  - riga 232: `RECEIVE MAP`: MAP `cics-map:COUSR03/COUSR3A` (letterale); MAPSET `cics-mapset:COUSR03` (letterale)
- File:
  - riga 269: `READ` lettura-update: FILE `cics-file:USRSEC` (costante)
  - riga 307: `DELETE` cancellazione: FILE `cics-file:USRSEC` (costante)

## Bersagli non risolti

Registrati con l'operando, mai omessi e mai indovinati: la risoluzione delle variabili e' la issue #46.

| file | riga | comando | ruolo | operando | motivo |
| --- | ---: | --- | --- | --- | --- |
| app/app-authorization-ims-db2-mq/cbl/COPAUS0C.cbl | 322 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/app-authorization-ims-db2-mq/cbl/COPAUS0C.cbl | 674 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/app-authorization-ims-db2-mq/cbl/COPAUS1C.cbl | 367 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/app-transaction-type-db2/cbl/COTRTLIC.cbl | 620 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/app-transaction-type-db2/cbl/COTRTUPC.cbl | 457 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/app-transaction-type-db2/cbl/COTRTUPC.cbl | 1433 | `SEND MAP` | MAP | `CCARD-NEXT-MAP` | senza-value-letterale |
| app/app-transaction-type-db2/cbl/COTRTUPC.cbl | 1433 | `SEND MAP` | MAPSET | `CCARD-NEXT-MAPSET` | senza-value-letterale |
| app/cbl/COACTUPC.cbl | 956 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COACTUPC.cbl | 3594 | `SEND MAP` | MAP | `CCARD-NEXT-MAP` | senza-value-letterale |
| app/cbl/COACTUPC.cbl | 3594 | `SEND MAP` | MAPSET | `CCARD-NEXT-MAPSET` | senza-value-letterale |
| app/cbl/COACTVWC.cbl | 349 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COACTVWC.cbl | 583 | `SEND MAP` | MAP | `CCARD-NEXT-MAP` | senza-value-letterale |
| app/cbl/COACTVWC.cbl | 583 | `SEND MAP` | MAPSET | `CCARD-NEXT-MAPSET` | senza-value-letterale |
| app/cbl/COADM01C.cbl | 145 | `XCTL` | PROGRAM | `CDEMO-ADMIN-OPT-PGMNAME(WS-OPTION)` | espressione |
| app/cbl/COADM01C.cbl | 168 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COBIL00C.cbl | 281 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COCRDLIC.cbl | 538 | `XCTL` | PROGRAM | `CCARD-NEXT-PROG` | senza-value-letterale |
| app/cbl/COCRDLIC.cbl | 566 | `XCTL` | PROGRAM | `CCARD-NEXT-PROG` | senza-value-letterale |
| app/cbl/COCRDSLC.cbl | 331 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COCRDSLC.cbl | 569 | `SEND MAP` | MAP | `CCARD-NEXT-MAP` | senza-value-letterale |
| app/cbl/COCRDSLC.cbl | 569 | `SEND MAP` | MAPSET | `CCARD-NEXT-MAPSET` | senza-value-letterale |
| app/cbl/COCRDUPC.cbl | 473 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COCRDUPC.cbl | 1329 | `SEND MAP` | MAP | `CCARD-NEXT-MAP` | senza-value-letterale |
| app/cbl/COCRDUPC.cbl | 1329 | `SEND MAP` | MAPSET | `CCARD-NEXT-MAPSET` | senza-value-letterale |
| app/cbl/COMEN01C.cbl | 156 | `XCTL` | PROGRAM | `CDEMO-MENU-OPT-PGMNAME(WS-OPTION)` | espressione |
| app/cbl/COMEN01C.cbl | 184 | `XCTL` | PROGRAM | `CDEMO-MENU-OPT-PGMNAME(WS-OPTION)` | espressione |
| app/cbl/COMEN01C.cbl | 201 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/CORPT00C.cbl | 548 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COTRN00C.cbl | 192 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COTRN00C.cbl | 518 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COTRN01C.cbl | 205 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COTRN02C.cbl | 508 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COUSR00C.cbl | 196 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COUSR00C.cbl | 206 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COUSR00C.cbl | 514 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COUSR01C.cbl | 175 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COUSR02C.cbl | 258 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |
| app/cbl/COUSR03C.cbl | 205 | `XCTL` | PROGRAM | `CDEMO-TO-PROGRAM` | senza-value-letterale |

## Letterale, costante, variabile

Regola applicata a ogni operando di bersaglio (`glue/resolve.py`, ricontrollata con un'implementazione separata in `glue/verify.py`):

- **letterale**: l'operando e' un solo letterale alfanumerico tra apici; nome = contenuto senza gli spazi finali.
- **costante**: l'operando e' un solo nome di dato e, nel programma espanso con i suoi copybook (archi COPY di #2, `REPLACING` applicato come sostituzione di testo): il blocco non sta in un copybook; nessuna COPY non risolta puo' definirlo (i copybook di sistema `DFH*` e `CMQ*`, assenti dal repository, definiscono solo nomi `DFH*` e `MQ*`); il nome e' definito una sola volta (livelli 01-49 e 77); sta in `WORKING-STORAGE` o `LOCAL-STORAGE`; ne' lui ne' un suo gruppo hanno `OCCURS`; ha `VALUE` con un letterale alfanumerico; nessuna istruzione lo modifica. Nome = contenuto del letterale senza gli spazi finali; l'occorrenza cita file e riga del letterale della `VALUE`.
- **modifica**: un'occorrenza, nella `PROCEDURE DIVISION` espansa, di un nome collegato (il dato, i suoi gruppi, i suoi subordinati, chi ridefinisce o e' ridefinito da uno di questi con i suoi subordinati, i livelli 88 e 66 relativi) fuori da questi contesti di sola lettura: argomento intero di `PROGRAM`, `TRANSID`, `MAP`, `MAPSET`, `FILE`, `DATASET`, `QUEUE`, `QNAME` in un `EXEC CICS`; mittente di una `MOVE` (prima di `TO`); dopo `IF`, `EVALUATE`, `WHEN`, `UNTIL`, `DISPLAY` fino al verbo successivo. Tutto il resto conta come modifica (`INITIALIZE`, `SET`, `CALL ... USING`, `STRING`, `COMPUTE`, ogni altra opzione di `EXEC CICS`, ogni `EXEC SQL` o `EXEC DLI`, ...): sovrastima voluta.
- **non risolto**: ogni altro caso; il motivo e' il primo che vale nell'ordine: `in-copybook`, `espressione`, `valore-vuoto`, `copy-non-risolta`, `non-definito`, `definito-piu-volte`, `fuori-working-storage`, `occurs`, `senza-value-letterale`, `modificato`, `mapset-assente`, `mapset-non-risolto`, `tipo-coda-assente`. Una mappa e' risolta solo se lo sono la mappa e il suo mapset; una coda solo se `TD` o `TS` e' scritto nel comando.

## Limiti

- Si registra che un comando ha `RESP`, `NOHANDLE` o un `HANDLE`, non che cosa comporta (fuori ambito).
- I bersagli in variabile (tabelle di menu, campi della COMMAREA, dati valorizzati con `MOVE`), l'arco online -> batch di `CORPT00C` e le voci di menu verso i moduli opzionali sono nella issue #46.
- Nessun collegamento fra file CICS (`cics-file:`) e dataset dei JCL, ne' fra mapset e sorgenti BMS.
- La regola di modifica e' una sovrastima: un dato letto in un contesto non elencato (per esempio in una `STRING`) risulta modificato e resta non risolto. Non produce mai una costante falsa, puo' produrre un non risolto in piu'.
- Le righe di continuazione (`-` in colonna 7) non sono gestite dalla colla di risoluzione; nel legacy compaiono solo in `CBSTM03A`, che non ha blocchi `EXEC CICS`. Il preprocessore di ProLeap le unisce alla riga precedente: un blocco dopo una continuazione avrebbe la riga sbagliata, e il confronto con il conteggio indipendente lo segnalerebbe.
- Un `EXEC` e il suo `CICS` su due righe diverse non sono riconosciuti da ProLeap (`NEWLINE` e' un token della regola); nel legacy non accade, e il conteggio indipendente li conterebbe, facendo fallire il controllo.
