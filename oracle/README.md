# Oracle GnuCOBOL, parte 1 (#4)

Immagine container in cui gli 11 programmi batch di CardDemo che compilano senza modifiche si compilano con GnuCOBOL e si avviano. È il primo pezzo dell'oracle: il comportamento di riferimento contro cui si misurerà il Java. Qui non si elaborano dati (esecuzione con i dati veri: #5 e successive) e non si implementano le routine esterne (#24).

Sull'host servono solo Docker, Git e le utility POSIX. GnuCOBOL gira nel container.

```
git submodule update --init
./oracle/run.sh build              # immagine, volume del legacy, compilazione (circa 20 s con la cache di Docker)
./oracle/run.sh --all --check      # tutti i controlli, con le prove negative (circa 90 s)
./oracle/run.sh avvio --check      # un solo controllo
```

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `run.sh` | comando unico, estendibile per cartelle come `analysis/run.sh`: `<nome>` esegue `oracle/<nome>/run.sh`, `--check` esegue `check.sh`, `deps` dichiara le dipendenze, `--all` le rispetta. **Differenza:** con `--check` un passo senza `check.sh` è un errore |
| `Dockerfile` | immagine `menb-oracle-gnucobol:3.2-<hash del Dockerfile>` |
| `cobc.opts` | le opzioni di `cobc`, una per riga, ciascuna con il motivo; uguali per tutti i programmi |
| `programs.tsv` | gli 11 programmi della build: sorgente, tipo (eseguibile o modulo), motivo del tipo letto nel sorgente |
| `launcher/avvia.c` | l'avviatore: il `main` di ogni eseguibile, costruisce l'area del `PARM` |
| `stubs/` | `CEE3ABD` (stub) e i segnaposto `COBDATFT`, `MVSWAIT`, `CEEDAYS` |
| `tests/` | programmi COBOL di prova: `PARMECHO`, `ABDUSING`, `ABDNOARG`, `M03BCALL`, `DTCCALL` |
| `esegui.sh` | (nel container) avvia un eseguibile in una cartella vuota e scrive il rapporto: codice di uscita, stdout, stderr, file creati |
| `lib.sh` | funzioni comuni: immagine, volume del legacy, esecuzione nel container con limite di tempo, impronta della build, prove negative |
| `build/` | passo `build`: compila tutto in `build/out/` (ignorato da git); `check.sh` rifà la build e la verifica contro un elenco fisso |
| `avvio/` | passo `avvio`: prova di avvio reale di ogni eseguibile e dei due moduli; attesi in `avvio/expected/` |
| `avviatore/` | passo `avviatore`: `PARMECHO` riceve `2022071800`; attesi in `avviatore/expected/` |
| `abend/` | passo `abend`: `CEE3ABD` nelle due forme di chiamata; attesi in `abend/expected/` |
| `selftest/` | test automatico del comando unico (ordine, ciclo, dipendenza mancante, primo errore, controllo mancante) |

Ogni `check.sh` rigenera da zero ciò che controlla, in una cartella nuova: nessun risultato di una corsa precedente viene preso per attuale. La build scrive per ultima `build/out/IMPRONTA`, l'impronta di tutti gli input (sorgenti dell'oracle, opzioni, elenco, strati dell'immagine, commit del legacy) e degli artefatti prodotti; i passi che usano gli artefatti la ricalcolano e rifiutano una build assente, interrotta, vecchia o con artefatti cambiati dopo la build. Il controllo della build verifica anche che `cobc.opts` contenga esattamente le opzioni fissate nel controllo e che i passi dei criteri di accettazione esistano con i loro script. Ogni programma gira con stdin vuoto e un limite di tempo (`ORACLE_TIMEOUT_RUN`, 60 s; compilazione `ORACLE_TIMEOUT_COMPILE`, 900 s), applicato con `timeout` dentro il container. Gli attesi sono scritti a mano leggendo il sorgente (i paragrafi di `OPEN`, `9910-DISPLAY-IO-STATUS`, `9999-ABEND-PROGRAM`); ogni controllo ha prove negative automatiche, alcune su esecuzioni reali alterate (avviatore con ordine dei byte invertito, stub che ritorna, eseguibili senza moduli).

## Immagine e ambiente

- Base `debian:trixie-slim` fissata per digest, la stessa di `analysis/tools/docker/gnucobol` (il compilatore con cui #1 ha verificato che gli 11 compilano).
- GnuCOBOL 3.2.0: pacchetti Debian `gnucobol3`, `libcob4t64`, `libcob4-dev` alla versione `3.2-3`.
- **Backend dei file indicizzati: Berkeley DB** (`indexed file handler : BDB` in `cobc --info`), `libdb5.3t64` fissato a `5.3.28+dfsg2-9`. I file sequenziali usano il gestore interno di libcob. Il controllo della build verifica questi valori in `build/out/ambiente.txt`.
- Configurazione di runtime: nessuna variabile di libcob nell'immagine, valgono i default di `runtime.cfg` (registrati a ogni build in `build/out/ambiente.txt`). Gli script impostano solo `COB_LIBRARY_PATH` (cartella dei moduli) e, quando serve, `DD_<nome>` per i file. In particolare: `COB_VARSEQ_FORMAT` 0, `COB_FILE_PATH` non impostata (cartella corrente), `COB_SYNC` no.
- Il legacy si legge da un volume Docker proprio, `menb-oracle-legacy-<commit>`, copiato byte per byte dal submodule e verificato a ogni build con lo SHA-256 di ogni file; montato in sola lettura. Su macOS un bind mount non distingue le maiuscole; il volume sì. I sorgenti non vengono modificati né pre-elaborati.
- **Avviso di libxml2 su stderr.** Ogni programma, all'avvio, scrive su stderr `Warning: program compiled against libxml 212 using older 209`: libcob di Debian è compilata con libxml2 2.12, ma trixie installa la 2.9.14 (pacchetto `2.12.7+dfsg+really2.9.14`). Nessuno degli 11 programmi usa XML. La riga compare negli attesi perché è ciò che si osserva.

## Opzioni di compilazione

Tutte in `cobc.opts`, con il motivo: `-std=ibm`, `-fbinary-truncate`, `-fsingle-quote`, `-Wall`, `-I/legacy/app/cpy`. In più, per tipo di artefatto: un **eseguibile** si compila con `cobc -c` e si collega all'avviatore con `cobc -x -A -DMENB_ENTRY=<programma> avvia.c <programma>.o`; un **modulo** si compila con `cobc -m`. Nessuna opzione di controllo a tempo di esecuzione (`-debug`, `-fec`): su z/OS non c'è `SSRANGE` nel JCL di compilazione, e i controlli di GnuCOBOL fermerebbero programmi che su z/OS proseguono.

Scelte che possono cambiare ciò che i programmi fanno:

| Scelta | Motivo |
| --- | --- |
| `-std=ibm` (dialetto IBM, versione lax) | lo stesso di #1. Imposta tra l'altro: `binary-size 2-4-8` (un `COMP` occupa 2, 4 o 8 byte come su IBM), `binary-byteorder big-endian`, `assign-clause external` e `filename-mapping yes`, `arithmetic-osvs yes`, `perform-osvs yes`, `move-ibm yes`, `hostsign yes`, `defaultbyte 0` (campi senza `VALUE` a X'00') |
| `-fbinary-truncate` | il JCL di compilazione del legacy (`scripts/compile_batch.jcl.template`, `samples/proc/BUILDBAT.prc`: `PARM=(APOST,LIST,MAP,NUMBER[,NOSEQ])`) non indica `TRUNC`, quindi vale il default di Enterprise COBOL `TRUNC(STD)`. `ibm.conf` imposta invece `binary-truncate: no` (come `TRUNC(BIN)`); qui si riporta a sì. Il default effettivo dell'installazione originale non è noto |
| `-fsingle-quote` | `APOST` nello stesso JCL. Nessuno degli 11 usa `QUOTE`: oggi senza effetto |
| CALL dinamiche (default di cobc) | le routine chiamate (`CEE3ABD`, segnaposto, `CBSTM03B`, `CSUTLDTC`) sono moduli `.so` cercati in `COB_LIBRARY_PATH` a tempo di esecuzione, così i segnaposto restano separati dai programmi. Il default di Enterprise COBOL è `NODYNAM` (chiamata statica). Nessuno degli 11 usa `CANCEL`, quindi non ci si attende una differenza di comportamento; non è stato verificato |
| Ordine di collazione e segno: default | `-fdefault-colseq` e `-fsign` non sono impostati: collazione ASCII, segno dei numeri `DISPLAY` nella convenzione ASCII. Vedi le differenze sotto |

## Programmi

Opzioni: per tutti quelle di `cobc.opts`. Avvertimenti: dal log di compilazione (`build/out/log/<programma>.log`).

| Programma | Tipo | Perché (dal sorgente) | Avvertimenti |
| --- | --- | --- | --- |
| `CBACT01C` | eseguibile | `READACCT.jcl`, `EXEC PGM=CBACT01C` | 0 |
| `CBACT02C` | eseguibile | `READCARD.jcl` | 0 |
| `CBACT03C` | eseguibile | `READXREF.jcl` | 0 |
| `CBACT04C` | eseguibile | `INTCALC.jcl`, `PARM='2022071800'`; riceve l'area del PARM (`PROCEDURE DIVISION USING EXTERNAL-PARMS`) | 0 |
| `CBCUS01C` | eseguibile | `READCUST.jcl` | 0 |
| `CBSTM03B` | modulo | `PROCEDURE DIVISION USING LK-M03B-AREA`; `CALL 'CBSTM03B'` in `CBSTM03A` (righe 351, 377) | 0 |
| `CBTRN01C` | eseguibile | `PROCEDURE DIVISION` senza `USING`; nessun JCL lo avvia e nessun programma lo chiama | 0 |
| `CBTRN02C` | eseguibile | `POSTTRAN.jcl` | 1: riga 403, `precision of result may change with arithmetic-osvs` (il `COMPUTE WS-TEMP-BAL = ACCT-CURR-CYC-CREDIT - ACCT-CURR-CYC-DEBIT + DALYTRAN-AMT`) |
| `CBTRN03C` | eseguibile | `TRANREPT.jcl` e `TRANREPT.prc` | 1: riga 177, `NEXT SENTENCE is archaic` (un `NEXT SENTENCE` dentro `IF ... END-IF`) |
| `COBSWAIT` | eseguibile | `WAITSTEP.jcl` | 0 |
| `CSUTLDTC` | modulo | `PROCEDURE DIVISION USING` con tre parametri; `CALL 'CSUTLDTC'` in `CORPT00C` (righe 392, 412) | 0 |

Errori: 0 per tutti. La build compila anche lo stub, i tre segnaposto e i cinque programmi di prova: 20 artefatti in `build/out/bin/`.

### Avvio senza file d'ingresso (passo `avvio`, verificato qui)

Ogni eseguibile parte in una cartella vuota, senza variabili `DD_`, senza `PARM`, con stdin vuoto.

- Gli 8 programmi con file stampano `START OF EXECUTION OF PROGRAM <P>`, tentano la prima `OPEN INPUT`, ricevono lo stato **35** (file assente), stampano `ERROR OPENING ...`, `FILE STATUS IS: NNNN0035`, `ABENDING PROGRAM` e chiamano `CEE3ABD`: codice di uscita **99**. Nessun file viene creato (la prima `OPEN` di ognuno è in ingresso).
- `COBSWAIT` non ha file: legge `SYSIN` (vuoto) e chiama `MVSWAIT`, il segnaposto: codice **98**.
- `CBSTM03B`, chiamato da `M03BCALL` con l'area di `CBSTM03A`: per ognuno dei quattro file l'apertura ritorna `35` in `LK-M03B-RC`; con un nome DD non gestito il codice resta quello impostato prima della chiamata. `M03BCALL` termina con 0.
- `CSUTLDTC`, chiamato da `DTCCALL` con gli argomenti di `CORPT00C`: arriva alla chiamata di `CEEDAYS`, il segnaposto: codice **98**. Questa prova non è chiesta dalla specifica (che chiede il chiamante solo per `CBSTM03B`): è aggiunta perché altrimenti il modulo `CSUTLDTC` non sarebbe mai caricato da nessuna prova.

## Avviatore e area del PARM (passo `avviatore`, verificato qui)

Su z/OS il `PARM` del JCL arriva al programma come area: lunghezza binaria di due byte, poi il testo. `CBACT04C` la riceve con `PROCEDURE DIVISION USING EXTERNAL-PARMS` (`PARM-LENGTH PIC S9(04) COMP`, `PARM-DATE PIC X(10)`) e non legge la riga di comando.

L'avviatore (`launcher/avvia.c`) è il `main` di ogni eseguibile: `<eseguibile> [PARM]`. Costruisce l'area con la **lunghezza in ordine big-endian**, cioè l'ordine che si aspetta un `COMP` compilato con `-std=ibm` (`binary-byteorder big-endian`, lo stesso di z/OS), copia il testo (al massimo 100 caratteri), riempie il resto con X'00' e chiama il programma con quell'area come unico argomento. Senza argomento la lunghezza è 0, come un passo senza `PARM=`. I programmi senza `USING` ignorano l'area. Il codice di uscita è il `RETURN-CODE`.

Esempio, l'equivalente di `//STEP15 EXEC PGM=CBACT04C,PARM='2022071800'`:

```
COB_LIBRARY_PATH=<bin> <bin>/CBACT04C 2022071800
```

Verificato da `avviatore/check.sh`: `PARMECHO` riceve l'area `00 0a 32 30 32 32 30 37 31 38 30 30` e legge lunghezza 10 e testo `2022071800`. Prove negative reali: con l'avviatore che scrive la lunghezza in little-endian l'area diventa `0a 00 ...` e il controllo fallisce; con `PARMECHO` compilato con `-fbinary-byteorder=native` il programma legge 2560 e il controllo fallisce. L'ordine dei byte dell'avviatore è quindi legato all'opzione sui binari: se cambia `cobc.opts`, va cambiato anche l'avviatore (e il controllo se ne accorge).

Su z/OS il contenuto dell'area oltre la lunghezza non è definito; qui è X'00'. Rilevante solo se un programma legge `PARM-DATE` con un `PARM` più corto di 10 caratteri.

## CEE3ABD e segnaposto (passo `abend`, verificato qui)

`stubs/CEE3ABD.cbl` regge le due forme di chiamata del legacy (`CALL 'CEE3ABD' USING ABCODE, TIMING` e `CALL 'CEE3ABD'`), distinte con `C$NARG`. Scrive su stderr `MENB-ORACLE CEE3ABD: ARRESTO ANOMALO ABCODE=+0000000999 TIMING=+0000000000` (o `... SENZA ARGOMENTI`) e termina l'intera esecuzione con **codice di uscita 99**, fisso. Normali, per confronto: 0; 4 (`CBTRN02C` con scarti); la severità di `CEEDAYS` per `CSUTLDTC`; **1** quando libcob si ferma per un errore di runtime (per esempio `libcob: error: module 'CEE3ABD' not found`, osservato nella prova negativa senza moduli). I segnaposto `COBDATFT`, `MVSWAIT`, `CEEDAYS` scrivono `MENB-ORACLE SEGNAPOSTO: <nome> NON IMPLEMENTATO (ISSUE #24)` e terminano con **98**.

La terminazione usa `STOP RUN`: libcob chiude i file ancora aperti (su stderr: `libcob: warning: implicit CLOSE of ABD-FILE ('ABDFILE')`). Comportamento osservato e controllato per entrambe le forme: il codice visto dalla shell che ha lanciato il programma è 99; il record scritto prima della chiamata, con il file ancora aperto, **è su disco** dopo l'arresto, esattamente 20 byte; il programma non riprende dopo la `CALL` (nessun secondo record, nessuna riga successiva). Fatto ulteriore, verificato nella stessa prova con uno stub alterato che esce con `_exit(99)` senza chiudere nulla: anche così il record è su disco, cioè libcob 3.2 non trattiene in memoria i record di un file sequenziale.

`TIMING` non cambia nulla. Su z/OS `CEE3ABD` produce un abend utente (U0999) e non un codice di ritorno: il passo termina in abend e i passi successivi del job seguono le regole `COND` per gli abend. Qui l'abend diventa il codice 99: chi esegue un job dovrà trattarlo come abend.

## Assegnazione dei file: da nome DD a file

Con `-std=ibm` (`assign-clause external`, `filename-mapping yes`), `SELECT ... ASSIGN TO <nome>` apre il file indicato dalla variabile d'ambiente `DD_<nome>` (in alternativa `dd_<nome>` o `<nome>`); se nessuna è impostata, apre un file chiamato `<nome>` nella cartella corrente (`COB_FILE_PATH` non è impostata). È l'equivalente della scheda `//<nome> DD DSN=...` del JCL.

- **Sequenziale**, `CBTRN02C`, `SELECT DALYTRAN-FILE ASSIGN TO DALYTRAN` (in `POSTTRAN.jcl`: `//DALYTRAN DD DISP=SHR,DSN=AWS.M2.CARDDEMO.DALYTRAN.PS`):
  `DD_DALYTRAN=/dati/dalytran.ps` → il programma legge `/dati/dalytran.ps`.
- **Indicizzato**, `CBACT01C`, `SELECT ACCTFILE-FILE ASSIGN TO ACCTFILE`, `ORGANIZATION IS INDEXED` (in `READACCT.jcl`: `//ACCTFILE DD DISP=SHR,DSN=AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS`):
  `DD_ACCTFILE=/dati/acctdata.bdb` → il programma apre il file Berkeley DB `/dati/acctdata.bdb`, che contiene dati e indici (con BDB non ci sono file `.idx` separati).

Verificato qui per i file sequenziali: in `abend` il file è assegnato con `DD_ABDFILE` a un percorso fuori dalla cartella di lavoro e il record si trova lì; in `avviatore`, senza variabile, `PARMDUMP` si crea nella cartella corrente. Per i file indicizzati il nome si risolve con lo stesso meccanismo, ma qui nessun file indicizzato esiste davvero (le prove aprono solo file assenti, stato 35): l'apertura di un file indicizzato reale è lavoro di #5.

## Differenze note tra GnuCOBOL ed Enterprise COBOL

Marcatura: **verificata qui** = un controllo di questa issue la dimostra; **da verificare** = in un'issue successiva, con dati o con un caso dedicato; **non verificabile** = servirebbe z/OS, che non abbiamo.

| Tema | Cosa si sa | Stato |
| --- | --- | --- |
| Binari: ordine dei byte | `COMP` in big-endian come su z/OS (`binary-byteorder big-endian`); l'area del PARM letta correttamente; con ordine nativo il programma legge 2560 invece di 10 | verificata qui |
| Binari: dimensione | `binary-size 2-4-8`: `S9(4) COMP` occupa 2 byte (l'area del PARM è di 12 byte come attesa) | verificata qui per `S9(4) COMP`; per gli altri formati da verificare |
| Binari: troncamento | `-fbinary-truncate` emula `TRUNC(STD)`. Che il comportamento coincida con z/OS sui valori oltre le cifre della PICTURE non è provato | da verificare |
| Aritmetica intermedia | `-std=ibm` attiva `arithmetic-osvs` (precisione dei risultati intermedi limitata come su IBM); cobc avverte che in `CBTRN02C` riga 403 la precisione può cambiare. Le regole di Enterprise COBOL (`ARITH(COMPAT)`) non sono state confrontate | da verificare (#5 e successive, con importi reali) |
| Segno dei numeri `DISPLAY` | I file ASCII del legacy (`app/data/ASCII/`) usano la convenzione di segno EBCDIC (`{` = +0, `}` = -0 nell'ultima cifra). Con il segno di default (ASCII) GnuCOBOL legge `00000001940}` come +194,00 invece di -194,00; con `-fsign=EBCDIC` lo legge -194,00 (prova manuale, non automatizzata). L'opzione non è stata applicata perché qui non si leggono dati: va decisa e verificata in #5 | da verificare (#5) |
| Ordine di collazione | ASCII qui, EBCDIC su z/OS: cambiano i confronti tra stringhe con cifre, lettere minuscole e maiuscole, l'ordine di `SORT` e l'ordine delle chiavi nei file indicizzati (BDB ordina per byte ASCII) | da verificare |
| Chiavi alternative con duplicati | `CBACT04C` dichiara `ALTERNATE RECORD KEY IS FD-XREF-ACCT-ID` senza `WITH DUPLICATES`, mentre l'indice alternativo è definito `NONUNIQUEKEY` (`app/jcl/XREFFILE.jcl`, riga 75). Come reagiscono z/OS (stato all'apertura) e GnuCOBOL con BDB (chiave unica nel file creato) non è provato. Su z/OS l'indice alternativo ha anche una sua DD (path), che qui non esiste | da verificare (#5); il comportamento z/OS non verificabile |
| Record variabili | `CBACT01C` scrive `VBRC-FILE` con `RECORDING MODE IS V`. GnuCOBOL (`COB_VARSEQ_FORMAT` 0) mette davanti a ogni record 2 byte di lunghezza big-endian, esclusa l'intestazione, più 2 byte X'00'; su z/OS il descrittore (RDW) ha 4 byte e la lunghezza include il descrittore | da verificare |
| Codici di stato dei file | `OPEN INPUT` di un file assente, sequenziale o indicizzato: stato 35, osservato in 8 programmi e nei 4 file di `CBSTM03B`. Su z/OS, secondo la documentazione IBM, un dataset inesistente indicato in una DD con `DISP=SHR` ferma il passo prima dell'avvio del programma (errore di allocazione), e lo stato 35 si ha quando manca la DD: non verificabile qui. Gli altri stati (in particolare quelli specifici di VSAM) non sono stati provati | 35 verificata qui; resto da verificare |
| Arresto anomalo | Qui `CEE3ABD` chiude i file e termina con 99; i record già scritti restano su disco (anche senza chiusura). Su z/OS cosa resta di un file aperto al momento di un abend (buffer non scritti) dipende dal metodo di accesso | GnuCOBOL verificata qui; z/OS non verificabile |
| `NEXT SENTENCE` dentro `IF ... END-IF` | In `CBTRN03C` (riga 177). Su IBM salta dopo il punto successivo, oltre l'`END-IF`; che GnuCOBOL faccia lo stesso non è provato | da verificare |
| Campi senza `VALUE` | `defaultbyte 0`: X'00'. Su z/OS il contenuto iniziale dipende dalle opzioni di Language Environment | da verificare |
| `DISPLAY` e `ACCEPT FROM SYSIN` | stdout e stdin del processo al posto di `SYSOUT` e della DD `SYSIN` | verificata qui (stdout); `SYSIN` vuoto osservato solo per `COBSWAIT` |

## Limiti

- La CI del repository esegue solo `./verify.sh`: questi controlli non girano in CI (il workflow è fuori dal perimetro di #4).
- Nessun dato reale: nessun file indicizzato viene creato o letto (#5).
- `CEE3ABD` non riproduce il dump né la gestione delle condizioni di Language Environment.
- I pacchetti sono fissati per versione su un archivio Debian corrente: se Debian ritira una di quelle versioni, la build dell'immagine fallisce (non è stato usato `snapshot.debian.org`).
- `docker build` non ha un limite di tempo proprio; i programmi e le compilazioni sì.
