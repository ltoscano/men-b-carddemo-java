# Inventario strutturale e grafo delle dipendenze statiche (Wave 0A, issue #2)

Questo documento riassume `docs/legacy-map/graph.json` (formato fissato da `graph.schema.json`) e registra le anomalie trovate. **Il grafo non e' completo**: la sezione "Categorie non ancora mappate" dice cosa manca. Tutto cio' che segue e' scritto da `analysis/inventory/` e si rigenera con un comando; non e' stato modificato a mano.

## Come si rigenera

Sull'host servono Git e Docker (piu' bash e le utility POSIX). Il sorgente si legge dal volume Docker sensibile alle maiuscole di #1.

```
git submodule update --init
./analysis/run.sh inventory           # rigenera analysis/inventory/out/, graph.json e questo file
./analysis/run.sh inventory --check   # rigenera in una cartella temporanea, confronta con il versionato, conteggi indipendenti, attesi a mano, prove negative
./analysis/run.sh --all --check       # tutte le analisi
```

## Contenuto del grafo

| Tipo di nodo | Nodi |
| --- | --- |
| asm | 2 |
| copybook | 62 |
| dataset | 97 |
| external | 17 |
| jcl-job | 46 |
| jcl-step | 123 |
| proc | 2 |
| program | 44 |
| transaction | 25 |
| utility | 10 |

| Tipo di arco | Archi | Occorrenze |
| --- | --- | --- |
| CALL | 32 | 62 |
| COPY | 306 | 346 |
| JOB_DD | 2 | 3 |
| JOB_PASSO | 119 | 119 |
| PASSO_DD | 423 | 497 |
| PASSO_ESEGUE | 123 | 123 |
| PROC_PASSO | 4 | 4 |
| TRANSAZIONE_PROGRAMMA | 25 | 25 |

Un arco e' una terna (tipo, da, a); ogni occorrenza porta file e riga (e, secondo il tipo, sostituzioni `REPLACING`, `PARM`, nome della DD, `DISP`, generazione GDG, fonte). Due `COPY` dello stesso copybook con `REPLACING` diversi sono due occorrenze.

## Strumenti e colla

Gli strumenti sono quelli adottati in #1 (`docs/legacy-map/strumenti.md`). La colla elencata qui lavora su nomi gia' trovati da uno strumento o su parole chiave a formato fisso; non e' un parser.

| Archi | Strumento | Colla scritta in questa issue |
| --- | --- | --- |
| `COPY` (programmi e copybook) | ProLeap (colla Java di #1), un file per volta | nessuna: riga e sostituzioni sono quelle di ProLeap |
| `CALL` statiche | cobol-migration-toolkit (nomi, una scansione per cartella di programmi) | **localizzatore di occorrenze** (`glue/locate_calls.py`): per ogni nome gia' trovato dallo strumento cerca nel sorgente le istruzioni `CALL 'NOME'` (area di codice colonne 8-72, commenti esclusi, letterale anche a capo); ogni occorrenza ha la sua riga |
| Transazione → programma | nessuno strumento | **estrazione testuale** (`glue/csd.py`): `DEFINE TRANSACTION(X)` e la prima clausola `PROGRAM(Y)` prima del `DEFINE` successivo, nei quattro file `csd` del manifesto |
| JCL, livello A | mapa, un file per volta | procedure di `app/proc/` presentate a mapa in copie temporanee senza estensione (il nome che mapa cerca), identiche byte per byte agli originali e verificate; non versionate |
| JCL, livello B | nessuno strumento | **estrattore di schede** (`glue/cards.py`): righe `//nome EXEC` e `//nome DD` e continuazioni (operando che termina con virgola, commenti `//*` in mezzo, colonne 1-72, dati in linea esclusi); ricava `PGM=`/`PROC=`, `PARM=`, `DSN=`, `DISP=`, `SYSOUT=`, `*`, `DUMMY` cosi' come scritti. Non risolve simboli, non espande procedure, non valuta condizioni |
| JCL, `PARM=` e riga di `EXEC`/DD | mapa non li riporta | l'estrattore di schede, per tutti i file (anche al livello A) |

**Livelli JCL.** Un file `jcl` e' al livello A se l'output di mapa coincide con il conteggio indipendente e con le schede: stesso numero di `EXEC`, stesso numero di DD per ogni passo, stessi nomi di passo, programma e DD (una DD senza nome eredita quello della precedente, come in mapa), nessuna DD a livello di job. Altrimenti e' al livello B. Ogni passo e ogni DD dichiara la `fonte` (`mapa` o `schede`). Un fallimento di mapa non diventa un valore atteso: l'elenco dei file al livello B e' in `analysis/inventory/expected/livello_b.tsv` con la causa, e `--check` fallisce se l'elenco cambia.

**Forma sorgente e forma risolta.** Per ogni DD si registrano, quando esistono, `dsn_sorgente` e `disp_sorgente` (testo del sorgente, simboli come scritti) e `dsn_risolto` e `disp_effettivo` (da mapa, che risolve i simboli e riempie i valori impliciti: `SHR` diventa `SHR/KEEP/KEEP`; per le DD senza DSN, `SYSOUT=*`, `*`, `DUMMY`, in cui il sorgente non ha `DISP`, mapa inventa `NEW/DELETE/DELETE` e `disp_effettivo` non si registra). Al livello B esiste solo la forma del sorgente. Il nodo `dataset` usa il nome risolto se c'e', altrimenti quello del sorgente (con i simboli, marcato `simbolico`). `(+1)`/`(0)`/`(-1)` e' la generazione GDG (`gdg`, `generazione`); `(NOME)` e' il membro. `SYSOUT`, dati in linea, `DUMMY` sono nodi pseudo (`dataset:~SYSOUT`, `~INSTREAM`, `~DUMMY`).

**DD a livello di job.** `JOBLIB` e ogni DD prima del primo passo sono archi `JOB_DD` dal job, con `livello: job`, mai attribuiti a un passo.

**Procedure.** Una `proc` ha i suoi passi (`PROC_PASSO`), ricavati con l'estrattore di schede; un passo `EXEC PROC=` punta al nodo `proc`.

**Risoluzione dei `COPY`.** Il nome si cerca tra i file `copybook` del manifesto (maiuscole ignorate, estensione tolta; i nomi sono unici). Un nome senza file e' un nodo `external` (per esempio `DFHAID`).

**Scelte dove la specifica lasciava margine.** I quattro file CSD del manifesto sono tutti letti (anche quelli dei moduli opzionali); i job dei moduli opzionali sono nel grafo; un `PGM=` che non e' un programma o un modulo assembler del repository e' un nodo `utility`; un nome di passo ripetuto o assente si distingue con `#n` (ordinale); i passi di una procedura si chiamano `proc.NOME/PASSO` perche' un job e una procedura possono avere lo stesso nome (`TRANREPT`).

## Copertura dei JCL

46 file `jcl`: 42 al livello A, 4 al livello B. Totale sul sorgente (conteggio indipendente): 119 `EXEC` e 480 DD; nel grafo i passi sono 119 e le DD 480.

### File passati al livello B (mapa non coincide con il sorgente)

| File | EXEC sorgente | DD sorgente | EXEC mapa | DD mapa | Motivo del confronto | Causa (letta nel sorgente e nel log) |
| --- | --- | --- | --- | --- | --- | --- |
| `app/app-transaction-type-db2/jcl/CREADB21.jcl` | 5 | 30 | 5 | 27 | DD: mapa 27, sorgente 30 | mapa riporta 27 DD su 30: non riporta le 3 DD a livello di job (JOBLIB e due concatenate, righe 32-34); avvisi sul dataset &CODER..M2.CARDDEMO.CNTL |
| `app/app-transaction-type-db2/jcl/TRANEXTR.jcl` | 5 | 28 | 0 | 0 | passi: mapa 0, sorgente 5 | mapa riporta il job senza passi e senza avvisi; prima del primo EXEC il file ha //   SET HLQ=AWS.M2.CARDDEMO (riga 25) |
| `app/jcl/TRANREPT.jcl` | 3 | 16 | 2 | 4 | passi: mapa 2, sorgente 3 | mapa riporta 2 passi su 3 e 4 DD su 16; il sorgente ha due passi con lo stesso nome STEP05R (righe 23 e 37) |
| `app/jcl/TXT2PDF1.JCL` | 1 | 6 | 0 | 0 | passi: mapa 0, sorgente 1 | errore di analisi di mapa alla riga 25 (PARM=('')): nessun job nell output |

### Tutti i file jcl

| File | EXEC | DD | Livello |
| --- | --- | --- | --- |
| `app/app-authorization-ims-db2-mq/jcl/CBPAUP0J.jcl` | 1 | 17 | A |
| `app/app-authorization-ims-db2-mq/jcl/DBPAUTP0.jcl` | 2 | 19 | A |
| `app/app-authorization-ims-db2-mq/jcl/LOADPADB.JCL` | 1 | 14 | A |
| `app/app-authorization-ims-db2-mq/jcl/UNLDGSAM.JCL` | 1 | 16 | A |
| `app/app-authorization-ims-db2-mq/jcl/UNLDPADB.JCL` | 2 | 21 | A |
| `app/app-transaction-type-db2/jcl/CREADB21.jcl` | 5 | 30 | B |
| `app/app-transaction-type-db2/jcl/MNTTRDB2.jcl` | 1 | 7 | A |
| `app/app-transaction-type-db2/jcl/TRANEXTR.jcl` | 5 | 28 | B |
| `app/jcl/ACCTFILE.jcl` | 3 | 8 | A |
| `app/jcl/CARDFILE.jcl` | 8 | 20 | A |
| `app/jcl/CBADMCDJ.jcl` | 1 | 5 | A |
| `app/jcl/CBEXPORT.jcl` | 2 | 11 | A |
| `app/jcl/CBIMPORT.jcl` | 1 | 9 | A |
| `app/jcl/CLOSEFIL.jcl` | 1 | 3 | A |
| `app/jcl/COMBTRAN.jcl` | 2 | 10 | A |
| `app/jcl/CREASTMT.JCL` | 5 | 22 | A |
| `app/jcl/CUSTFILE.jcl` | 5 | 14 | A |
| `app/jcl/DALYREJS.jcl` | 1 | 2 | A |
| `app/jcl/DEFCUST.jcl` | 2 | 4 | A |
| `app/jcl/DEFGDGB.jcl` | 1 | 2 | A |
| `app/jcl/DEFGDGD.jcl` | 6 | 18 | A |
| `app/jcl/DISCGRP.jcl` | 3 | 8 | A |
| `app/jcl/DUSRSECJ.jcl` | 4 | 12 | A |
| `app/jcl/ESDSRRDS.jcl` | 6 | 19 | A |
| `app/jcl/FTPJCL.JCL` | 1 | 1 | A |
| `app/jcl/INTCALC.jcl` | 1 | 9 | A |
| `app/jcl/INTRDRJ1.JCL` | 2 | 8 | A |
| `app/jcl/INTRDRJ2.JCL` | 1 | 4 | A |
| `app/jcl/OPENFIL.jcl` | 1 | 3 | A |
| `app/jcl/POSTTRAN.jcl` | 1 | 9 | A |
| `app/jcl/PRTCATBL.jcl` | 3 | 8 | A |
| `app/jcl/READACCT.jcl` | 2 | 10 | A |
| `app/jcl/READCARD.jcl` | 1 | 4 | A |
| `app/jcl/READCUST.jcl` | 1 | 4 | A |
| `app/jcl/READXREF.jcl` | 1 | 4 | A |
| `app/jcl/REPTFILE.jcl` | 1 | 2 | A |
| `app/jcl/TCATBALF.jcl` | 3 | 8 | A |
| `app/jcl/TRANBKP.jcl` | 3 | 6 | A |
| `app/jcl/TRANCATG.jcl` | 3 | 8 | A |
| `app/jcl/TRANFILE.jcl` | 8 | 20 | A |
| `app/jcl/TRANIDX.jcl` | 3 | 6 | A |
| `app/jcl/TRANREPT.jcl` | 3 | 16 | B |
| `app/jcl/TRANTYPE.jcl` | 3 | 8 | A |
| `app/jcl/TXT2PDF1.JCL` | 1 | 6 | B |
| `app/jcl/WAITSTEP.jcl` | 1 | 3 | A |
| `app/jcl/XREFFILE.jcl` | 6 | 14 | A |

## Anomalie

### Programmi senza job ne' transazione che li esegua

9 programmi. Quelli con una colonna "chiamato da" sono sottoprogrammi: non li esegue un job o una transazione, li chiama un altro programma.

| Programma | Modulo | Chiamato (CALL) da |
| --- | --- | --- |
| `CBPAUP0C` | app-authorization-ims-db2-mq | - |
| `CBSTM03B` | base | `CBSTM03A` |
| `CBTRN01C` | base | - |
| `COBTUPDT` | app-transaction-type-db2 | - |
| `COPAUS2C` | app-authorization-ims-db2-mq | - |
| `CSUTLDTC` | base | `CORPT00C`, `COTRN02C` |
| `DBUNLDGS` | app-authorization-ims-db2-mq | - |
| `PAUDBLOD` | app-authorization-ims-db2-mq | - |
| `PAUDBUNL` | app-authorization-ims-db2-mq | - |

### Copybook mai copiati

3 copybook.

| Copybook | Modulo |
| --- | --- |
| `CSDB2RPY` | app-transaction-type-db2 |
| `CSDB2RWY` | app-transaction-type-db2 |
| `UNUSED1Y` | base |

### COPY non risolte (nessun copybook con quel nome nel manifesto)

| Copybook | Occorrenze | Programmi |
| --- | --- | --- |
| `CMQGMOV` | 3 | COACCT01, CODATE01, COPAUA0C |
| `CMQMDV` | 4 | COACCT01, CODATE01, COPAUA0C |
| `CMQODV` | 4 | COACCT01, CODATE01, COPAUA0C |
| `CMQPMOV` | 3 | COACCT01, CODATE01, COPAUA0C |
| `CMQTML` | 3 | COACCT01, CODATE01, COPAUA0C |
| `CMQV` | 3 | COACCT01, CODATE01, COPAUA0C |
| `DFHAID` | 21 | COACTUPC, COACTVWC, COADM01C, COBIL00C, COCRDLIC, COCRDSLC, COCRDUPC, COMEN01C, COPAUS0C, COPAUS1C, CORPT00C, COSGN00C, COTRN00C, COTRN01C, COTRN02C, COTRTLIC, COTRTUPC, COUSR00C, COUSR01C, COUSR02C, COUSR03C |
| `DFHBMSCA` | 21 | COACTUPC, COACTVWC, COADM01C, COBIL00C, COCRDLIC, COCRDSLC, COCRDUPC, COMEN01C, COPAUS0C, COPAUS1C, CORPT00C, COSGN00C, COTRN00C, COTRN01C, COTRN02C, COTRTLIC, COTRTUPC, COUSR00C, COUSR01C, COUSR02C, COUSR03C |

### Bersagli `external` (non presenti nel repository)

| Nome | Archi entranti | Occorrenze |
| --- | --- | --- |
| `CBLTDLI` | CALL (3) | 9 |
| `CEE3ABD` | CALL (11) | 11 |
| `CEEDAYS` | CALL (1) | 1 |
| `CMQGMOV` | COPY (3) | 3 |
| `CMQMDV` | COPY (3) | 4 |
| `CMQODV` | COPY (3) | 4 |
| `CMQPMOV` | COPY (3) | 3 |
| `CMQTML` | COPY (3) | 3 |
| `CMQV` | COPY (3) | 3 |
| `COCRDSEC` | TRANSAZIONE_PROGRAMMA (1) | 1 |
| `DFHAID` | COPY (21) | 21 |
| `DFHBMSCA` | COPY (21) | 21 |
| `MQCLOSE` | CALL (3) | 7 |
| `MQGET` | CALL (3) | 3 |
| `MQOPEN` | CALL (3) | 7 |
| `MQPUT` | CALL (2) | 4 |
| `MQPUT1` | CALL (1) | 1 |

### Copybook che contengono istruzioni eseguibili

Individuati dal primo termine di ogni riga di codice (colonne 8-72, commenti esclusi, dopo `ELSE`/`WHEN`/`THEN` il termine successivo) tra: `ACCEPT`, `ADD`, `CALL`, `CLOSE`, `COMPUTE`, `CONTINUE`, `DISPLAY`, `DIVIDE`, `EVALUATE`, `EXEC`, `EXIT`, `GO`, `GOBACK`, `IF`, `INITIALIZE`, `INSPECT`, `MOVE`, `MULTIPLY`, `OPEN`, `PERFORM`, `READ`, `REWRITE`, `SET`, `STOP`, `STRING`, `SUBTRACT`, `UNSTRING`, `WRITE`. E' una ricerca per parola chiave, non un'analisi: non dice se il copybook e' usato nella `PROCEDURE DIVISION`.

| Copybook | Righe con istruzioni | Prima riga | Verbi |
| --- | --- | --- | --- |
| `app/app-transaction-type-db2/cpy/CSDB2RPY.cpy` | 18 | 23 | CALL, COMPUTE, CONTINUE, EVALUATE, EXEC, EXIT, IF, MOVE, PERFORM, SET, STRING |
| `app/cpy/CSSETATY.cpy` | 4 | 18 | IF, MOVE |
| `app/cpy/CSSTRPFY.cpy` | 30 | 21 | EVALUATE, EXIT, SET |
| `app/cpy/CSUTLDPY.cpy` | 135 | 19 | CALL, COMPUTE, CONTINUE, DIVIDE, EXIT, GO, IF, INITIALIZE, MOVE, SET, STRING |

### File del manifesto di tipo sorgente senza nodo nel grafo

Nessuno per i tipi `cobol`, `copybook`, `jcl`, `proc`, `asm`, `csd`.

Tipi di file sorgente che non hanno nodi perche' fuori ambito (vedi sotto): bms (21), ctl (8), dcl (3), ddl (6), ims (8), macro (2), scheduler (2).

### CALL non letterali e letterali non riportati dallo strumento

CALL con operando non letterale: 0. CALL con letterale che cobol-migration-toolkit non aveva riportato: 0.

### Passi senza nome unico, DD a livello di job, DD concatenate

Passi il cui nome si ripete o manca nel sorgente (distinti con `#n`): `jcl-step:DEFCUST/STEP05#1`, `jcl-step:DEFCUST/STEP05#2`, `jcl-step:TRANREPT/STEP05R#1`, `jcl-step:TRANREPT/STEP05R#2`.


DD a livello di job (prima del primo passo; `JOBLIB` e DD concatenate):

| Job | File | Riga | DD |
| --- | --- | --- | --- |
| `jcl-job:CREADB21` | `app/app-transaction-type-db2/jcl/CREADB21.jcl` | 32 | `JOBLIB` |
| `jcl-job:CREADB21` | `app/app-transaction-type-db2/jcl/CREADB21.jcl` | 33 | `(senza nome)` |
| `jcl-job:CREADB21` | `app/app-transaction-type-db2/jcl/CREADB21.jcl` | 34 | `(senza nome)` |

### Anomalie del sorgente verificate a mano

Registrate, non corrette. `--check` verifica che ogni riga contenga il testo indicato.

| File | Riga | Descrizione |
| --- | --- | --- |
| `app/jcl/CREASTMT.JCL` | 90 | la riga di continuazione della DD STMTFILE contiene testo spurio dopo il blank (commento per JCL) |
| `app/jcl/TRANREPT.jcl` | 23 | primo dei due passi con lo stesso nome STEP05R |
| `app/jcl/TRANREPT.jcl` | 37 | secondo passo con lo stesso nome STEP05R |
| `app/proc/TRANREPT.prc` | 1 | file .prc con la forma di un job: ridefinisce la procedura REPROC e contiene i passi di un job fino a PEND |
| `app/proc/TRANREPT.prc` | 79 | PEND di chiusura della procedura nel file TRANREPT.prc |

## Categorie non ancora mappate

Il grafo non e' completo. Fuori ambito di questa issue:

| Categoria | Dove |
| --- | --- |
| Comandi `EXEC CICS`: trasferimenti (`XCTL`, `LINK`, `RETURN TRANSID`), mappe BMS, file, code, job generati dall'online | issue #22 |
| `EXEC SQL` e chiamate IMS (`CBLTDLI`, `EXEC DLI`) dei moduli opzionali; le chiamate `CALL 'CBLTDLI'` e `CALL 'MQ...'` sono nel grafo come `CALL` verso nodi `external`, la loro semantica no | Wave 6 |
| Tracciati dei record e dei campi | issue #3 |
| Flussi batch (ordine dei job, dataset prodotti e consumati nel ciclo) | issue #7 |
| Comportamento | issue #11 |
| File `bms`, `ctl`, `dcl`, `ddl`, `ims`, `macro`, `scheduler` (CA7, Control-M), `data`, `sample`: nessun nodo | non assegnata qui |
| Definizioni di file e programmi nei CSD (`DEFINE FILE`, `DEFINE PROGRAM`), `DSN` dentro `SYSIN` dei JCL, `PARM` risolti, `COND`, `IF/THEN` dei JCL | non mappati |
| `COPY` dentro `EXEC SQL INCLUDE`; `REPLACE`; `CALL` con operando non letterale (elencate sopra) | non mappati |

