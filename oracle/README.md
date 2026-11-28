# Oracle GnuCOBOL, parte 1 (#4)

Immagine container in cui gli 11 programmi batch di CardDemo che compilano senza modifiche, più `CBSTM03A` compilato da una copia adattata (#25, passo `adattamenti`), si compilano con GnuCOBOL e si avviano. È il primo pezzo dell'oracle: il comportamento di riferimento contro cui si misurerà il Java. Qui non si eseguono i programmi sui dati veri (#5 e successive) e delle routine esterne sono implementate `COBDATFT` (#24) e `MVSWAIT` (#36), entrambe nel passo `routines`; le sole letture di dati originali sono la sonda sul segno dei numeri (passo `segno`) e le poche righe dello scenario di `CBSTM03A` (passo `adattamenti`).

Sull'host servono solo Docker, Git e le utility POSIX. GnuCOBOL gira nel container.

```
git submodule update --init
./oracle/run.sh build              # immagine, volume del legacy, compilazione (circa 20 s con la cache di Docker)
./oracle/run.sh --all --check      # tutti i controlli, con le prove negative (alcuni minuti; anche in CI, .github/workflows/oracle.yml)
./oracle/run.sh avvio --check      # un solo controllo
```

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `run.sh` | comando unico, estendibile per cartelle come `analysis/run.sh`: `<nome>` esegue `oracle/<nome>/run.sh`, `--check` esegue `check.sh`, `deps` dichiara le dipendenze, `--all` le rispetta. **Differenza:** con `--check` un passo senza `check.sh` è un errore |
| `Dockerfile` | immagine `menb-oracle-gnucobol:3.2-<hash del Dockerfile>` |
| `cobc.opts` | le opzioni di `cobc`, una per riga, ciascuna con il motivo; uguali per tutti i programmi |
| `programs.tsv` | i 12 programmi del legacy della build: sorgente, tipo (eseguibile o modulo), motivo del tipo letto nel sorgente |
| `launcher/avvia.c` | l'avviatore: il `main` di ogni eseguibile, costruisce l'area del `PARM` |
| `stubs/` | `CEE3ABD` (stub), `COBDATFT` e `MVSWAIT` (equivalenti delle routine assembler, #24 e #36) e il segnaposto `CEEDAYS` |
| `tests/` | programmi COBOL di prova: `PARMECHO`, `ABDUSING`, `ABDNOARG`, `M03BCALL`, `DTCCALL`, `SEGNOPRB`, `PERFPRB`, `DATFTPRB`, `IDXLOAD` e `IDXDUMP` (caricamento e rilettura dei file indicizzati di `CBSTM03B`, #25), `WAITPRB` (chiamata diretta di `MVSWAIT`, #36), `IDXLOADF` (caricamento di un file indicizzato da record a lunghezza fissa senza terminatori, #53) |
| `ambiente.sh` | (nel container) l'ambiente fissato: le sole variabili che ricevono `cobc` e i programmi |
| `esegui.sh` | (nel container) avvia un eseguibile in una cartella vuota, nell'ambiente fissato, e scrive il rapporto (codice di uscita, stdout, stderr, file creati) e l'ambiente ricevuto dal programma; con `--sysin FILE` (#36) collega il file all'ingresso standard e aggiunge al rapporto la sezione `== sysin` |
| `lib.sh` | funzioni comuni: immagine, volume del legacy, esecuzione nel container con limite di tempo, impronta della build, prove negative |
| `build/` | passo `build`: compila tutto in `build/out/` (ignorato da git); `check.sh` rifà la build e la verifica contro elenchi fissi, compresi gli argomenti esatti di ogni invocazione di `cobc`; `avvolgi.sh` è l'involucro delle prove sugli esiti dei comandi (sezione "Esiti dei comandi") |
| `avvio/` | passo `avvio`: prova di avvio reale di ogni eseguibile e dei due moduli; attesi in `avvio/expected/` |
| `avviatore/` | passo `avviatore`: `PARMECHO` riceve `2022071800`; attesi in `avviatore/expected/` |
| `abend/` | passo `abend`: `CEE3ABD` nelle due forme di chiamata; attesi in `abend/expected/` |
| `segno/` | passo `segno`: lettura e scrittura di importi con segno dai dati originali; attesi in `segno/expected/` |
| `dialetto/` | passo `dialetto`: sonda semantica su `perform-osvs`, un'impostazione del dialetto letta dalla configurazione del compilatore; attesi in `dialetto/expected/` |
| `routines/` | passo `routines`: `COBDATFT` provata con il chiamante `DATFTPRB`; tabella dei casi determinati e non determinati in `routines/cobdatft-casi.md` (e `.tsv`), casi in `casi.tsv`, attesi in `routines/expected/`. `MVSWAIT` (#36) provata con `WAITPRB` e con `COBSWAIT` e `--sysin`: tabella in `mvswait-casi.md` (e `.tsv`), casi in `mvswait-prove.tsv`, attesi in `mvswait-attesi/`, osservazioni (non attesi) in `mvswait-osservazioni.md`, `.tsv` e `mvswait-osservati/`, rapporto di riferimento per la retrocompatibilità di `esegui.sh` in `mvswait-riferimento/`; script `mvswait-run.sh`, `mvswait-check.sh`, `mvswait-coerenza.sh` |
| `adattamenti/` | `adatta.sh` genera a ogni build le copie di compilazione adattate di `CBSTM03A` (TAB di `CUSTREC` a 4 colonne, righe 266-291 commentate); passo `adattamenti`: verifica delle copie e scenario con quattro file indicizzati (`scenario/`), attesi in `adattamenti/expected/`. Tutto in `adattamenti/registro.md` |
| `dati/` | passo `dati` (#53): il file dei conti (`ACCTFILE`) caricato da `analysis/oracle-dati/out/ACCTFILE.rec` con `IDXLOADF`, riletto con `IDXDUMP` e verificato (`carica.sh` nel container, `run.sh` sull'host); file indicizzato in `dati/out/ACCTFILE.dat` (ignorato da git, ricreato a ogni corsa), attesi in `dati/expected/`. Sezione "File dei conti" qui sotto |
| `selftest/` | test automatico del comando unico (ordine, ciclo, dipendenza mancante, primo errore, controllo mancante) |

Ogni `check.sh` rigenera da zero ciò che controlla, in una cartella nuova: nessun risultato di una corsa precedente viene preso per attuale. La build scrive per ultima `build/out/IMPRONTA`, l'impronta di tutti gli input (sorgenti dell'oracle, opzioni, elenco, strati dell'immagine, commit del legacy) e degli artefatti prodotti; i passi che usano gli artefatti la ricalcolano e rifiutano una build assente, interrotta, vecchia o con artefatti cambiati dopo la build. Il controllo della build verifica anche che `cobc.opts` contenga esattamente le opzioni fissate nel controllo, che **ogni invocazione di `cobc` abbia esattamente gli argomenti attesi** (registrati da `compile.sh` uno per riga, così come sono stati passati: le opzioni fissate più i soli argomenti strutturali del tipo, nient'altro, in quell'ordine) e che i passi dei criteri di accettazione esistano con i loro script. Tutti i confronti dei controlli sono esatti (righe e insiemi interi); l'unico confronto per sottostringa è il motivo atteso nelle prove negative (`expect_fail`), che identifica il messaggio di errore. Ogni programma gira con stdin vuoto (o, solo dove chiesto con `--sysin`, con un file di schede) e un limite di tempo (`ORACLE_TIMEOUT_RUN`, 60 s; compilazione `ORACLE_TIMEOUT_COMPILE`, 900 s), applicato con `timeout` dentro il container. Gli attesi sono scritti a mano leggendo il sorgente (i paragrafi di `OPEN`, `9910-DISPLAY-IO-STATUS`, `9999-ABEND-PROGRAM`); ogni controllo ha prove negative automatiche, alcune su esecuzioni reali alterate (avviatore con ordine dei byte invertito, stub che ritorna, eseguibili senza moduli).

## Immagine e ambiente

- Base `debian:trixie-slim` fissata per digest, la stessa di `analysis/tools/docker/gnucobol` (il compilatore con cui #1 ha verificato che gli 11 compilano).
- GnuCOBOL 3.2.0: pacchetti Debian `gnucobol3`, `libcob4t64`, `libcob4-dev` alla versione `3.2-3`.
- **Backend dei file indicizzati: Berkeley DB** (`indexed file handler : BDB` in `cobc --info`), `libdb5.3t64` fissato a `5.3.28+dfsg2-9`. I file sequenziali usano il gestore interno di libcob. Il controllo della build verifica questi valori in `build/out/ambiente.txt`.
- Configurazione di runtime: nessuna variabile di libcob nell'immagine, valgono i default di `runtime.cfg`. In particolare: `COB_VARSEQ_FORMAT` 0, `COB_FILE_PATH` non impostata (cartella corrente), `COB_SYNC` no. Vedi "Ambiente fissato" qui sotto.

### Ambiente fissato (compilatore e runtime)

`cobc` e libcob leggono la loro configurazione anche da variabili d'ambiente: una `COB_CONFIG_DIR` diversa, per esempio, fa usare a `cobc` un altro `ibm.conf` senza che cambi nessun argomento (rilievo del Validatore al giro 2 della PR #29: con `perform-osvs: no` aggiunto a una copia della configurazione, un `PERFORM` cambiava flusso e tutti i controlli restavano verdi). Per questo:

- **ogni invocazione di `cobc`** (`build/compile.sh`) e **ogni esecuzione di un programma compilato** (`esegui.sh`) parte da `env -i` seguito da un elenco esplicito di variabili (`ambiente.sh`). Nulla dell'ambiente ereditato arriva al compilatore o al runtime: non il container, non `docker run -e`, non un `export` in uno script;
- variabili ammesse per `cobc`: `PATH=/usr/bin:/bin`, `HOME=/tmp`, `LC_ALL=C`;
- variabili ammesse per i programmi: le stesse, più `COB_LIBRARY_PATH=/oracle-bin` (gli artefatti sono sempre montati lì) e, una per una, le `DD_<nome>=<percorso>` chieste esplicitamente a `esegui.sh` con `--dd` (nessun'altra forma è accettata);
- quindi **sono assenti** tutte le altre variabili che GnuCOBOL 3.2 legge. Elenco ricavato da `cobc --help`, `cobc --info`, `cobcrun --runtime-config`, `runtime.cfg` e dai nomi presenti negli eseguibili `cobc` e `libcob`:
  - compilatore: `COB_CONFIG_DIR`, `COB_COPY_DIR`, `COBCPY`, `COB_COPY_LIB_<nome>`, `COB_CC`, `COB_CFLAGS`, `COB_LDFLAGS`, `COB_LDADD`, `COB_LIBS`, `COB_LIB_PATHS`, `COB_DEBUG_FLAGS`, `COB_MSG_FORMAT`, `COB_OBJECT_EXT`, `COB_MODULE_EXT`, `COB_EXE_EXT`, `COB_EXT_EXPORT`, `COB_STRIP_CMD`, `COB_UNIX_LF`, `COBC_GEN_DUMP_COMMENTS`, `COBC_CORE_ON_ERROR`, `COBOL_WORDS_DIRECTIVE`, `TMPDIR`;
  - runtime: `COB_RUNTIME_CONFIG`, `COB_PRE_LOAD`, `COB_LOAD_CASE`, `COB_PHYSICAL_CANCEL`, `COB_FILE_PATH`, `COB_VARSEQ_FORMAT`, `COB_LS_FIXED`, `COB_LS_VALIDATE`, `COB_LS_NULLS`, `COB_LS_SPLIT`, `COB_SEQ_CONCAT_NAME`, `COB_SEQ_CONCAT_SEP`, `COB_SORT_CHUNK`, `COB_SORT_MEMORY`, `COB_SYNC`, `DB_HOME`, `COB_COL_JUST_LRC`, `COB_ZEROES_ALPHABETIC`, `COB_SPACES_ALPHABETIC`, `COB_CURRENT_DATE`, `COB_DATE`, `COB_SWITCH_<n>`, `COB_SET_DEBUG`, `COB_SET_TRACE`, `COB_TRACE_FILE`, `COB_TRACE_FORMAT`, `COB_OLD_TRACE`, `COB_STACKTRACE`, `COB_CORE_ON_ERROR`, `COB_CORE_FILENAME`, `COB_DUMP_FILE`, `COB_DUMP_WIDTH`, `COB_DEBUG_LOG`, `COB_DISABLE_WARNINGS`, `COB_ENV_MANGLE`, le variabili dello schermo e della stampa (`COB_BELL`, `COB_REDIRECT_DISPLAY`, `COB_SCREEN_ESC`, `COB_SCREEN_EXCEPTIONS`, `COB_TIMEOUT_SCALE`, `COB_INSERT_MODE`, `COB_MOUSE_FLAGS`, `COB_MOUSE_INTERVAL`, `COB_DISPLAY_PRINT_PIPE`, `COB_DISPLAY_PRINT_FILE`, `COB_DISPLAY_PUNCH_FILE`, `COB_LEGACY`, `COB_EXIT_WAIT`, `COB_EXIT_MSG`, `COBPRINTER`), le forme `dd_<nome>` e `<nome>` dei file;
  - libc: `TZ`, `LANG` e le `LC_*` diverse da `LC_ALL=C`.

Il controllo della build verifica ciò che compilatore e runtime riportano di aver usato, letto nello stesso ambiente fissato:

- le variabili ricevute da `cobc` e dai programmi (`build/out/ambiente-cobc.txt`, `ambiente-run.txt`) sono esattamente quelle fissate nel controllo;
- `cobc --info` riporta `COB_CONFIG_DIR : /usr/share/gnucobol/config` e `COB_COPY_DIR : /usr/share/gnucobol/copy`, e nessuna riga `env:` (la riga con cui `cobc` segnala una variabile che sostituisce la propria configurazione);
- la cartella di configurazione così riportata e lo SHA-256 di ognuno dei suoi 40 file (`.conf`, `.words`, `.ttbl`, `runtime.cfg`) coincidono con `build/expected/configurazione.sha256`. `cobc` non dice quali file della cartella legge: si fissa la cartella intera;
- `cobcrun --runtime-config` riporta esattamente `build/expected/runtime-config.txt`: `runtime.cfg` dell'immagine, tutte le impostazioni al default o non impostate, la sola riga `env:` è `COB_LIBRARY_PATH : /oracle-bin`.

La cartella di configurazione registrata in `configurazione.sha256` è quella che `cobc --info` dichiara di usare: il percorso della riga `env: COB_CONFIG_DIR : <percorso>` se c'è, altrimenti quello della riga `COB_CONFIG_DIR : <percorso>`. Fino alla issue #35 dalla riga `env:` si prendeva il nome della variabile al posto del percorso (rilievo 2 del giro 3 della PR #29): il controllo restava rosso, ma con la diagnostica sbagliata (`can't cd to COB_CONFIG_DIR`) e senza le impronte della cartella realmente usata. Oggi `build/check.sh` confronta per intero il manifesto della build con configurazione alternativa con uno acquisito in modo indipendente (percorso passato dal controllo, nomi elencati con `find`, hash con un solo `sha256sum`), verifica che nel log non ci sia `can't cd` e che la configurazione resti comunque rifiutata.

I due file attesi sono la configurazione dell'immagine così com'è, registrata una volta e da allora fissa: sono l'identità della configurazione, non valori derivati dal sorgente. Gli SHA-256 dei file di configurazione entrano anche nell'impronta della build. Ogni esecuzione registra inoltre l'ambiente ricevuto dal programma (`<P>.ambiente`), che i controlli dei passi confrontano con quello fissato.

Sonda semantica: `tests/PERFPRB.cbl` (passo `dialetto`) dipende da `perform-osvs`, un'impostazione che non è un'opzione di `cobc` ma viene dalla configurazione del dialetto. Con la configurazione dell'immagine stampa `B C D DONE`; con `perform-osvs: no` stampa `B C D E AFTER-INNER B C D DONE`. Un cambio di configurazione che sfuggisse agli altri controlli cambierebbe questo esito.

Effetto sui risultati: con l'ambiente fissato gli attesi delle prove di avvio, dell'avviatore, di CEE3ABD e del segno non sono cambiati. Prima i programmi ricevevano anche le variabili del container (`HOSTNAME`, il `PATH` di Debian) e `COB_LIBRARY_PATH` puntava a un'altra cartella: nessuna di queste aveva effetto su questi programmi.
- Il legacy si legge da un volume Docker proprio, `menb-oracle-legacy-<commit>`, copiato byte per byte dal submodule e verificato a ogni build con lo SHA-256 di ogni file; montato in sola lettura. Su macOS un bind mount non distingue le maiuscole; il volume sì. I sorgenti non vengono modificati né pre-elaborati.
- **Avviso di libxml2 su stderr.** Ogni programma, all'avvio, scrive su stderr `Warning: program compiled against libxml 212 using older 209`: libcob di Debian è compilata con libxml2 2.12, ma trixie installa la 2.9.14 (pacchetto `2.12.7+dfsg+really2.9.14`). Nessuno degli 11 programmi usa XML. La riga compare negli attesi perché è ciò che si osserva.

## Opzioni di compilazione

Tutte in `cobc.opts`, con il motivo: `-std=ibm`, `-fbinary-truncate`, `-fsingle-quote`, `-fsign=EBCDIC`, `-Wall`, `-I/legacy/app/cpy`. In più, per tipo di artefatto, solo questi argomenti strutturali:

```
modulo:     cobc <opzioni> -m -o OUT/bin/<P>.so <sorgente>
eseguibile: cobc <opzioni> -c -o OUT/obj/<P>.o <sorgente>
            cobc -x -A -DMENB_ENTRY=<P> -o OUT/bin/<P> /oracle/launcher/avvia.c OUT/obj/<P>.o
```

Per `CBSTM03A` (#25) il primo argomento è `-I/out/adattati` e il sorgente è la copia adattata `/out/adattati/CBSTM03A.CBL` (`adattamenti/registro.md`); nessun altro programma ha quell'argomento.

`build/check.sh` confronta, per ognuno dei 28 programmi compilati, gli argomenti effettivi di ogni invocazione con questo modello: un'opzione in più, in meno o in un altro ordine fa fallire il controllo (prova negativa reale: `CBACT04C` ricompilato con `-fno-binary-truncate` in coda, `CSUTLDTC` con `-fsign=ASCII` in coda). Nessuna opzione di controllo a tempo di esecuzione (`-debug`, `-fec`): su z/OS non c'è `SSRANGE` nel JCL di compilazione, e i controlli di GnuCOBOL fermerebbero programmi che su z/OS proseguono.

Scelte che possono cambiare ciò che i programmi fanno:

| Scelta | Motivo |
| --- | --- |
| `-std=ibm` (dialetto IBM, versione lax) | lo stesso di #1. Imposta tra l'altro: `binary-size 2-4-8` (un `COMP` occupa 2, 4 o 8 byte come su IBM), `binary-byteorder big-endian`, `assign-clause external` e `filename-mapping yes`, `arithmetic-osvs yes`, `perform-osvs yes`, `move-ibm yes`, `hostsign yes`, `defaultbyte 0` (campi senza `VALUE` a X'00') |
| `-fbinary-truncate` | il JCL di compilazione del legacy (`scripts/compile_batch.jcl.template`, `samples/proc/BUILDBAT.prc`: `PARM=(APOST,LIST,MAP,NUMBER[,NOSEQ])`) non indica `TRUNC`, quindi vale il default di Enterprise COBOL `TRUNC(STD)`. `ibm.conf` imposta invece `binary-truncate: no` (come `TRUNC(BIN)`); qui si riporta a sì. Il default effettivo dell'installazione originale non è noto |
| `-fsingle-quote` | `APOST` nello stesso JCL. Nessuno degli 11 usa `QUOTE`: oggi senza effetto |
| CALL dinamiche (default di cobc) | le routine chiamate (`CEE3ABD`, segnaposto, `CBSTM03B`, `CSUTLDTC`) sono moduli `.so` cercati in `COB_LIBRARY_PATH` a tempo di esecuzione, così i segnaposto restano separati dai programmi. Il default di Enterprise COBOL è `NODYNAM` (chiamata statica). Nessuno degli 11 usa `CANCEL`, quindi non ci si attende una differenza di comportamento; non è stato verificato |
| `-fsign=EBCDIC` | i file di dati del legacy (`app/data/ASCII/`) scrivono il segno dei numeri `DISPLAY` nell'ultima cifra con la convenzione EBCDIC (`{` `A`-`I` positivi, `}` `J`-`R` negativi), che corrisponde ai nibble di zona C/D di z/OS. Con il default della macchina (ASCII) GnuCOBOL legge `0000009190}` come +919,00 invece di -919,00. Decisione dell'Approvatore (voce 29 del registro) dopo il giro 1 della PR #29. Effetti verificati nel passo `segno` (sezione sotto) |
| Ordine di collazione: default | `-fdefault-colseq` non è impostato: collazione ASCII. Vedi le differenze sotto |

## Programmi

Opzioni: per tutti quelle di `cobc.opts`. Avvertimenti: dal log di compilazione (`build/out/log/<programma>.log`).

| Programma | Tipo | Perché (dal sorgente) | Avvertimenti |
| --- | --- | --- | --- |
| `CBACT01C` | eseguibile | `READACCT.jcl`, `EXEC PGM=CBACT01C` | 0 |
| `CBACT02C` | eseguibile | `READCARD.jcl` | 0 |
| `CBACT03C` | eseguibile | `READXREF.jcl` | 0 |
| `CBACT04C` | eseguibile | `INTCALC.jcl`, `PARM='2022071800'`; riceve l'area del PARM (`PROCEDURE DIVISION USING EXTERNAL-PARMS`) | 0 |
| `CBCUS01C` | eseguibile | `READCUST.jcl` | 0 |
| `CBSTM03A` | eseguibile, dalla copia adattata | `CREASTMT.JCL`, `STEP040 EXEC PGM=CBSTM03A`. L'originale non compila: si compila la copia di `adattamenti/adatta.sh` (`adattamenti/registro.md`) | 5: riga 237, `size of 'TIOT-INDEX' larger than size of 'BUMP-TIOT'`; righe 300, 303, 306, 309, `ALTER is obsolete in IBM COBOL` |
| `CBSTM03B` | modulo | `PROCEDURE DIVISION USING LK-M03B-AREA`; `CALL 'CBSTM03B'` in `CBSTM03A` (righe 351, 377) | 0 |
| `CBTRN01C` | eseguibile | `PROCEDURE DIVISION` senza `USING`; nessun JCL lo avvia e nessun programma lo chiama | 0 |
| `CBTRN02C` | eseguibile | `POSTTRAN.jcl` | 1: riga 403, `precision of result may change with arithmetic-osvs` (il `COMPUTE WS-TEMP-BAL = ACCT-CURR-CYC-CREDIT - ACCT-CURR-CYC-DEBIT + DALYTRAN-AMT`) |
| `CBTRN03C` | eseguibile | `TRANREPT.jcl` e `TRANREPT.prc` | 1: riga 177, `NEXT SENTENCE is archaic` (un `NEXT SENTENCE` dentro `IF ... END-IF`) |
| `COBSWAIT` | eseguibile | `WAITSTEP.jcl` | 0 |
| `CSUTLDTC` | modulo | `PROCEDURE DIVISION USING` con tre parametri; `CALL 'CSUTLDTC'` in `CORPT00C` (righe 392, 412) | 0 |

Errori: 0 per tutti. La build compila anche lo stub `CEE3ABD`, `COBDATFT`, `MVSWAIT`, il segnaposto `CEEDAYS` e i dodici programmi di prova: 28 artefatti in `build/out/bin/`, più le due copie adattate in `build/out/adattati/`. Con `-fsign=EBCDIC` avvertimenti e attesi della prova di avvio non cambiano.

### Avvio senza file d'ingresso (passo `avvio`, verificato qui)

Ogni eseguibile parte in una cartella vuota, senza variabili `DD_`, senza `PARM`, con stdin vuoto.

- Gli 8 programmi con file stampano `START OF EXECUTION OF PROGRAM <P>`, tentano la prima `OPEN INPUT`, ricevono lo stato **35** (file assente), stampano `ERROR OPENING ...`, `FILE STATUS IS: NNNN0035`, `ABENDING PROGRAM` e chiamano `CEE3ABD`: codice di uscita **99**. Nessun file viene creato (la prima `OPEN` di ognuno è in ingresso).
- `CBSTM03A` (copia adattata, #25) apre in uscita `STMTFILE` e `HTMLFILE` (creati vuoti nella cartella di lavoro), poi chiede a `CBSTM03B` l'apertura di `TRNXFILE`: ritorna `35`, stampa `ERROR OPENING TRNXFILE`, `RETURN CODE: 35`, `ABENDING PROGRAM` e chiama `CEE3ABD` senza argomenti: codice **99**. Su stderr libcob avverte della chiusura implicita dei due file aperti, nell'ordine inverso a quello di apertura (osservato).
- `COBSWAIT` non ha file: legge `SYSIN` (vuoto) e chiama `MVSWAIT`: codice **0**, con la riga di `MVSWAIT` che riporta il valore 0. Fino a #36 era il segnaposto (codice 98). Con `SYSIN` vuoto l'esito non è determinato dal sorgente: l'atteso è l'esito **osservato** con GnuCOBOL (caso `O1` di `routines/mvswait-osservazioni.md`), non un riferimento per la migrazione.
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

`stubs/CEE3ABD.cbl` regge le due forme di chiamata del legacy (`CALL 'CEE3ABD' USING ABCODE, TIMING` e `CALL 'CEE3ABD'`), distinte con `C$NARG`. Scrive su stderr `MENB-ORACLE CEE3ABD: ARRESTO ANOMALO ABCODE=+0000000999 TIMING=+0000000000` (o `... SENZA ARGOMENTI`) e termina l'intera esecuzione con **codice di uscita 99**, fisso. Normali, per confronto: 0; 4 (`CBTRN02C` con scarti); la severità di `CEEDAYS` per `CSUTLDTC`; **1** quando libcob si ferma per un errore di runtime (per esempio `libcob: error: module 'CEE3ABD' not found`, osservato nella prova negativa senza moduli). Il segnaposto `CEEDAYS` scrive `MENB-ORACLE SEGNAPOSTO: CEEDAYS NON IMPLEMENTATO (ISSUE #24)` e termina con **98** (così faceva anche `MVSWAIT` fino a #36).

La terminazione usa `STOP RUN`: libcob chiude i file ancora aperti (su stderr: `libcob: warning: implicit CLOSE of ABD-FILE ('ABDFILE')`). Comportamento osservato e controllato per entrambe le forme: il codice visto dalla shell che ha lanciato il programma è 99; il record scritto prima della chiamata, con il file ancora aperto, **è su disco** dopo l'arresto, esattamente 20 byte; il programma non riprende dopo la `CALL` (nessun secondo record, nessuna riga successiva). Fatto ulteriore, verificato nella stessa prova con uno stub alterato che esce con `_exit(99)` senza chiudere nulla: anche così il record è su disco. Il controllo lo dimostra solo per il caso provato (file `SEQUENTIAL` a record fissi di 20 byte, un solo record, `_exit` subito dopo la `WRITE`); non dimostra che libcob non usi mai un buffer, per altri formati, record più grandi o più record.

`TIMING` non cambia nulla. Su z/OS `CEE3ABD` produce un abend utente (U0999) e non un codice di ritorno: il passo termina in abend e i passi successivi del job seguono le regole `COND` per gli abend. Qui l'abend diventa il codice 99: chi esegue un job dovrà trattarlo come abend.

## Segno dei numeri DISPLAY (passo `segno`, verificato qui)

Un campo `PIC S9(n)V99` in `USAGE DISPLAY` (zoned) porta il segno nell'ultima cifra. Su z/OS è il nibble di zona dell'ultimo byte (C positivo, D negativo); nei file ASCII del legacy lo stesso byte è scritto con i caratteri della convenzione EBCDIC: `{` `A` … `I` = cifra 0 … 9 positiva, `}` `J` … `R` = cifra 0 … 9 negativa. In `app/data/ASCII/dailytran.txt` la posizione 143 (ultimo byte di `DALYTRAN-AMT`) contiene in tutti i 300 record solo questi caratteri.

Il programma di prova `SEGNOPRB` legge quel file con il copybook originale `CVTRA06Y` (come `LINE SEQUENTIAL`, perché il file ha un record per riga) e stampa, per quattro record, i byte grezzi, il valore letto e il ramo che sceglierebbe `CBTRN02C` (`IF DALYTRAN-AMT >= 0`, righe 547-551). Attesi scritti a mano dai byte delle posizioni 133-143, leggendo le prime dieci cifre e decodificando l'ultimo carattere con la tabella sopra:

| Record | Byte 133-143 | Valore atteso | Ramo |
| --- | --- | --- | --- |
| 1 | `0000005047G` | +504,77 (`G` = 7 positivo) | credito |
| 2 | `0000009190}` | -919,00 (`}` = 0 negativo) | debito |
| 23 | `0000000709R` | -70,99 (`R` = 9 negativo) | debito |
| 26 | `0000003250{` | +325,00 (`{` = 0 positivo) | credito |

Con `-fsign=EBCDIC` i quattro valori e i quattro rami sono quelli attesi. Prova negativa reale: la stessa sonda compilata senza `-fsign=EBCDIC` (file delle opzioni senza quella riga) legge +504,70, +919,00, +70,90, +325,00 e manda tutti e quattro gli importi nel ramo credito: il controllo fallisce.

Cosa cambia l'opzione oltre alla lettura, misurato dalla stessa sonda:

- **Scrittura.** GnuCOBOL scrive un campo zoned con segno nella stessa convenzione: +1,00 → `0000000010{`, -1,00 → `0000000010}`, 0 → `0000000000{` (lo zero ha segno positivo esplicito), -12,34 → `0000000123M`. I quattro importi letti, ricalcolati (`COMPUTE ... = DALYTRAN-AMT * 1`) e scritti nel file `SEGNOOUT`, tornano **identici byte per byte** a quelli del file originale: il formato prodotto è coerente con quello dei dati forniti. Senza l'opzione (osservato nella prova negativa) il positivo si scrive con cifre semplici (`00000000100`) e il negativo con `p`-`y` nell'ultimo byte (-1,00 → `0000000010p`, -12,34 → `0000000123t`): un formato diverso da quello dei dati.
- **`DISPLAY` a console.** Un campo zoned con segno mostrato con `DISPLAY` esce come cifre seguite dal segno (`00000050477+`, `00000091900-`), nello stesso formato con e senza l'opzione; cambia solo il valore, se è stato letto male. Le righe di `DISPLAY` della prova di avvio e degli stub non cambiano.
- **Confronti.** I confronti numerici usano il valore: con l'opzione `-919,00 < 504,77` e `-919,00 < 0` sono veri, senza sono falsi. I confronti alfanumerici (su byte, per esempio su un gruppo o con riferimento a sottostringa) confrontano i byte presenti in memoria: l'opzione non cambia la regola, ma senza di essa quei byte possono essere stati riscritti (punto seguente). Nella sonda il confronto tra i byte dei record 2 e 1 dà lo stesso esito nei due casi.
- **Osservato solo nella prova negativa, non controllato:** senza l'opzione, dopo aver usato `DALYTRAN-AMT` (in una `MOVE` o in una `IF`), i byte del record in memoria risultano cambiati (`0000005047G` diventa `00000050470`): libcob riscrive il campo nella propria convenzione.
- **Misurato in validazione** (giro 2 della PR #29, sonde del Validatore non automatizzate qui): con e senza `-fsign=EBCDIC`, lettura e riscrittura di campi `PIC 9`, `COMP-3` con e senza segno, `SIGN LEADING SEPARATE` e `SIGN TRAILING SEPARATE` danno valori e byte identici, anche rispetto all'ingresso (nei casi provati). Con il copybook originale `CVACT01Y` il primo record di `acctdata.txt` (`ACCT-CURR-BAL`, byte 13-24, `00000001940{`) si legge +194,00; anche i saldi +158,00 e +147,00 dei record successivi.
- **Non verificato:** gli altri file di dati, oltre a `dailytran.txt` e ai record di `acctdata.txt` citati sopra.

## COBDATFT (passo `routines`, verificato qui)

`stubs/COBDATFT.cbl` riproduce `app/asm/COBDATFT.asm` solo dove le istruzioni determinano il risultato byte per byte. Tabella dei casi con le righe dell'assembler in `routines/cobdatft-casi.md`. In breve: ingresso `1` con uscita diversa da `2` (e byte 6-19 dell'area diversi da `-INVALID INPUT`, i 14 byte noti del pool dei letterali) e ingresso `2` con uscita diversa da `1` formattano la data e restituiscono 0, senza controlli di calendario. Ogni ramo di errore (riga 56, `MVC` di 38 byte da un letterale di 13) e il confronto di 20 byte di riga 36 quando i 14 byte noti coincidono dipendono da byte oltre i letterali: la routine scrive `MENB-ORACLE COBDATFT: caso non riproducibile dall'oracle` su stderr e termina con **97**.

Verificato da `routines/check.sh` con il chiamante `DATFTPRB` (area riempita con X'A5', stampata in esadecimale prima e dopo la CALL) su 13 casi, 9 determinati e 4 non determinati, contro attesi scritti a mano; `routines/coerenza.sh` verifica che la tabella copra ogni combinazione di selettori una sola volta e che gli attesi siano quelli che la tabella prescrive. Prove negative reali: routine che scrive un byte da conservare, che restituisce 4, che non si ferma nei casi non determinati, che alla riga 36 guarda solo il byte 6 o solo 13 byte del pool, segnaposto di #4 rimesso al suo posto (ogni caso termina con 98).

`CBACT01C` chiama `COBDATFT` solo dopo aver letto un record di `ACCTFILE` (paragrafo `1300-POPUL-ACCT-RECORD`): senza file si ferma prima, all'apertura (stato 35, passo `avvio`), quindi il suo atteso di avvio non cambia. Che la routine sia caricata dai programmi è dimostrato con `DATFTPRB`, che la chiama con lo stesso meccanismo (`CALL` letterale dinamica risolta in `COB_LIBRARY_PATH`); per `CBACT01C` stesso lo mostrerà la prima esecuzione sui dati (#5).

## MVSWAIT e SYSIN (passo `routines`, verificato qui, #36)

`stubs/MVSWAIT.cbl` è l'equivalente di `app/asm/MVSWAIT.asm`, che legge per riferimento un intero di 4 byte e chiama `STIMER WAIT,BINTVL=` (macro `ASMWAIT`): un'attesa in centesimi di secondo, poi ritorno con codice 0. Tabella dei casi, con le righe dell'assembler e le frasi della documentazione IBM di `STIMER` (*z/OS 2.4 MVS Programming: Assembler Services Reference, Volume 2*, capitolo 97), in `routines/mvswait-casi.md`. Due adattamenti dichiarati:

- **non attende** (temporale: l'oracle deve essere ripetibile e veloce);
- **scrive su stderr una riga con il valore richiesto**, in decimale e in esadecimale, per esempio `MENB-ORACLE MVSWAIT: ATTESA RICHIESTA 0000003600 (X'00000E10') CENTESIMI DI SECONDO, NON ESEGUITA` (di uscita: l'originale non scrive nulla).

Riferimento di parità per la migrazione: **il valore richiesto** (che il Java deve passare identico al proprio meccanismo di attesa), il codice di ritorno 0, l'argomento invariato, nessuna uscita su stdout, l'arresto per un valore oltre `X'7FFFFFFF'`. **Non** è riferimento di parità la riga di diagnostica: esiste solo per rendere osservabile il valore, il Java non la riproduce; i rapporti dell'oracle la contengono e la confrontano esattamente perché è l'evidenza del valore.

Per un valore con il bit alto acceso (`X'80000000'` … `X'FFFFFFFF'`) `STIMER` termina il programma con l'abend `X'12F'`: non è riprodotto, la routine scrive la riga dell'arresto e termina con **97**, come i casi non riproducibili di `COBDATFT`. Non riprodotta: la scrittura di `X'FF'` nell'area di salvataggio del chiamante (riga 25), senza equivalente osservabile in GnuCOBOL. Non verificato nella documentazione IBM: che cosa faccia `STIMER WAIT` con intervallo zero (zero è comunque sotto il limite; l'equivalente ritorna 0).

`esegui.sh --sysin FILE` collega il file all'ingresso standard del programma: l'equivalente delle schede di `//SYSIN DD *`, lette da `ACCEPT ... FROM SYSIN`. È un ingresso diverso da `--parm` (il `PARM=` del JCL). Solo con l'opzione il rapporto ha in coda la sezione `== sysin` con byte e SHA-256 del file; senza, comandi esterni, rapporto e ambiente sono quelli di prima. Dopo il giro 1 di validazione della PR #52: il file si copia in un file privato (`mktemp`) prima di ogni scrittura o cancellazione dello script, così impronta e ingresso del programma restano gli stessi byte anche se `--sysin` coincide (o è collegato) con `.ambiente`, `.stdout`, `.stderr`, il rapporto o la cartella di lavoro; stdout, stderr e rapporto di una corsa precedente si vuotano all'inizio; ingresso, stdout e stderr del programma si aprono prima di avviarlo (descrittori 3, 4, 5) e un'apertura fallita è un errore dello strumento (codice 2, rapporto vuoto), non un codice del programma.

Verificato da `routines/mvswait-check.sh` (chiamato da `routines/check.sh`):

- 8 chiamate dirette con `WAITPRB` (0, 1, 3600, 99999999, 100000000, `X'7FFFFFFF'` con ritorno 0; `X'80000000'`, `X'FFFFFFFF'` con arresto 97), con l'argomento tra due campi `X'A5'` stampati prima e dopo la `CALL`; 2 esecuzioni di `COBSWAIT` con la scheda di `WAITSTEP.jcl` (valore 3600) e con altre 8 cifre, ricavate dal JCL con un comando a ogni esecuzione. Attesi scritti a mano dal sorgente e committati prima della prima esecuzione; tutti coincidono con l'esecuzione;
- `mvswait-coerenza.sh`: la tabella copre da `00000000` a `FFFFFFFF` senza buchi né sovrapposizioni, ogni atteso è quello che la tabella prescrive, le schede sono quelle ricavate indipendentemente dalla riga 26 del JCL;
- **limiti operativi** per ogni esecuzione che chiama `MVSWAIT` (anche ogni lancio di `COBSWAIT`), applicati all'artefatto vero: differenza di durata con una corsa di controllo che non chiama `MVSWAIT` (`WAITPRB` senza PARM, prima e dopo ogni caso, nello stesso container) al massimo 500 ms in ogni esecuzione, senza ripetizioni (codice 3 e `INFRASTRUTTURA LENTA` se i controlli stessi sono lenti), e arresto dopo 3 secondi (`ORACLE_TIMEOUT_RUN=3`). Respinge un'attesa di un secondo fissa, solo alla prima esecuzione o solo all'ultimo caso;
- osservazioni separate dagli attesi (`SYSIN` vuoto, `3600`, `ABCDEFGH`, `0000360X`: valori osservati 0, 3600, 0, 0), confrontate come registrazione dell'oracle, non come riferimento;
- retrocompatibilità di `esegui.sh`: `COBSWAIT` con il segnaposto di #4, senza `--sysin`, dà un rapporto identico a quello di riferimento prodotto dalla versione precedente dello script (`mvswait-riferimento/COBSWAIT-segnaposto.txt`, l'atteso di avvio di prima di #36). Gli attesi già versionati degli altri passi non cambiano; cambia solo `avvio/expected/COBSWAIT.txt`, perché cambia il modulo `MVSWAIT`, non lo script;
- prove negative reali: segnaposto rimesso al suo posto (98), routine che modifica l'argomento, che restituisce 4, che scrive su stdout, che attende davvero o un secondo fisso (fallisce per durata), che ritorna 0 con il bit alto acceso, che riporta il valore con i byte in ordine inverso o con il segno (una mutazione, una sola violazione: si verifica che cambino solo i rapporti attesi); `--sysin` con file inesistente, cartella, percorso relativo, ripetuto, ignorato, senza copia privata su `.ambiente` (anche via collegamento); ingresso o stdout che non si aprono, con i residui di una corsa precedente; `wc`, `sha256sum`, `cp`, `mktemp` di `esegui.sh` e `date`, `sed`, `mv`, `mkdir` di `mvswait-run.sh` che falliscono o rispondono male; radice del repository con spazi; attesi, osservazioni, tabella, casi e schede alterati; residui di una corsa precedente.

## File dei conti (passo `dati`, verificato qui, #53)

```
./analysis/run.sh oracle-dati      # i 50 record nel profilo dell'oracle: analysis/oracle-dati/out/ACCTFILE.rec
./oracle/run.sh dati               # caricamento, rilettura, verifica; file indicizzato in oracle/dati/out/ACCTFILE.dat
./oracle/run.sh dati --check       # da zero in una cartella nuova, con le prove negative
```

**Ingresso.** `analysis/oracle-dati/out/ACCTFILE.rec`, versionato: i 50 record di `app/data/EBCDIC/AWS.M2.CARDDEMO.ACCTDATA.PS` (il file che `app/jcl/ACCTFILE.jcl` carica nel KSDS con `REPRO`) portati nel profilo dell'oracle campo per campo, 300 byte ciascuno, senza terminatori, nell'ordine del file. Come si producono e si verificano: `docs/legacy-map/oracle-dati.md`.

**Caricamento.** `IDXLOADF` (`tests/IDXLOADF.cbl`) legge l'ingresso come file sequenziale a record fissi di 300 byte e scrive ogni record, cosi' com'e', in un file indicizzato con organizzazione, chiave e lunghezza del `SELECT` e dell'`FD` di `CBACT01C` (righe 29-33 e 52-56: `INDEXED`, accesso sequenziale, chiave `FD-ACCT-ID PIC 9(11)` nei byte 1-11, record di 300 byte). Non riempie e non tronca; controlla ogni stato di file (apertura, lettura, scrittura, chiusura). `IDXLOAD` di #25 non si usa: legge righe di testo, le riempie di spazi e non controlla la chiusura dell'ingresso. Osservato con GnuCOBOL 3.2 (#53): l'ultimo record incompleto di un file sequenziale a record fissi si legge con **stato 00**, e nell'area restano i byte del record precedente; per questo `IDXLOADF` legge la dimensione dell'ingresso prima di aprirlo (`CBL_CHECK_FILE_EXIST`, sullo stesso nome che apre) e rifiuta una dimensione che non sia un multiplo esatto di 300 (codice 8, `IDXLOADF ENTRATA DI <n> BYTE, NON MULTIPLA DI 0300`); alla fine i record letti devono essere dimensione / 300. Una chiave non crescente o doppia ferma la scrittura con stato 21 (osservato, accesso sequenziale).

**Rilettura.** `IDXDUMP` di #25, riusato com'e': rilegge in ordine di chiave, scrive ogni record byte per byte (`WRITE ... FROM`, nessuna conversione), controlla apertura, lettura e chiusura e termina con 0 solo se la lettura arriva alla fine del file con stato 10. La rilettura deve essere identica byte per byte all'ingresso: stessi 50 record, stesse chiavi, e quindi l'ordine del file d'origine e' l'ordine di chiave. Rapporto (`dati/out/ACCTFILE.rapporto`, atteso `dati/expected/ACCTFILE.rapporto`): numero di record, byte, prima e ultima chiave, SHA-256 della rilettura (uguale a quello di `ACCTFILE.rec`). Sono confrontati con gli attesi anche i rapporti di `esegui.sh` dei due programmi e gli ambienti ricevuti.

**Percorso stabile.** Come il JCL (`DELETE` prima di `DEFINE`), a ogni corsa la cartella `dati/out/` si cancella e si ricrea; il file indicizzato si scrive in `dati/out/lavoro/` e va a **`oracle/dati/out/ACCTFILE.dat`** solo dopo tutte le verifiche. Nel container dell'oracle e' **`/oracle/dati/out/ACCTFILE.dat`** (montaggio in sola lettura di `oracle/`): #55 lo usera' con `esegui.sh ... --dd DD_ACCTFILE=/oracle/dati/out/ACCTFILE.dat`. Che il file si apra e si rilegga da li', in sola lettura, e' verificato a ogni corsa (ultimo passo di `run.sh`). Se qualcosa fallisce non resta alcun file indicizzato, ne' al percorso stabile ne' nella cartella di lavoro. Il file e' generato, non versionato.

**Ordine di chiave.** La chiave e' numerica `DISPLAY` senza segno: le cifre hanno lo stesso ordine in ASCII (`30`-`39`) e in EBCDIC (`F0`-`F9`). Per questo, per questo file, l'ordine di chiave dell'oracle coincide con quello del mainframe; non vale in generale per chiavi alfanumeriche (vedi "Ordine di collazione" piu' sotto).

**Controlli** (`dati/check.sh`): passo rieseguito da zero e riletto in modo indipendente; `SELECT`/`FD` di `IDXLOADF` e `IDXDUMP` uguali a quelli di `CBACT01C` (letti dal sorgente); prove negative della specifica (record tolto, record scambiati, chiave duplicata, byte alterato in un campo numerico e nel `FILLER`, file troncato a meta' record, `ACCT-ADDR-ZIP` del record 49 ASCII al posto di quello EBCDIC, record di 299 byte non riempito, caricatore che esce con errore, rilettura che si ferma un record prima, residuo diverso con corsa regolare riuscita, residuo sano con caricamento fallito senza file rimasto, cartella `dati/` cancellata vista dal controllo dei passi di `build/check.sh`), attesi alterati, e gli esiti di ogni comando di `carica.sh` e di `run.sh` (involucro `build/avvolgi.sh`, esito 42 dopo il lavoro; risposte malformate; limite di tempo).

## Assegnazione dei file: da nome DD a file

Con `-std=ibm` (`assign-clause external`, `filename-mapping yes`), `SELECT ... ASSIGN TO <nome>` apre il file indicato dalla variabile d'ambiente `DD_<nome>` (in alternativa `dd_<nome>` o `<nome>`); se nessuna è impostata, apre un file chiamato `<nome>` nella cartella corrente (`COB_FILE_PATH` non è impostata). È l'equivalente della scheda `//<nome> DD DSN=...` del JCL.

- **Sequenziale**, `CBTRN02C`, `SELECT DALYTRAN-FILE ASSIGN TO DALYTRAN` (in `POSTTRAN.jcl`: `//DALYTRAN DD DISP=SHR,DSN=AWS.M2.CARDDEMO.DALYTRAN.PS`):
  `DD_DALYTRAN=/dati/dalytran.ps` → il programma legge `/dati/dalytran.ps`.
- **Indicizzato**, `CBACT01C`, `SELECT ACCTFILE-FILE ASSIGN TO ACCTFILE`, `ORGANIZATION IS INDEXED` (in `READACCT.jcl`: `//ACCTFILE DD DISP=SHR,DSN=AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS`):
  `DD_ACCTFILE=/dati/acctdata.bdb` → il programma apre il file Berkeley DB `/dati/acctdata.bdb`, che contiene dati e indici (con BDB non ci sono file `.idx` separati).

Verificato qui per i file sequenziali: in `abend` il file è assegnato con `DD_ABDFILE` a un percorso fuori dalla cartella di lavoro e il record si trova lì; in `avviatore`, senza variabile, `PARMDUMP` si crea nella cartella corrente. Per i file indicizzati il nome si risolve con lo stesso meccanismo. File indicizzati reali si creano e si leggono solo nello scenario di `CBSTM03A` (passo `adattamenti`, #25): `IDXLOAD` li scrive, `IDXDUMP` e `CBSTM03B` li leggono, tutti con `DD_<nome>`; l'apertura sui dati completi è lavoro di #5.

## Differenze note tra GnuCOBOL ed Enterprise COBOL

Marcatura: **verificata qui** = un controllo di questa issue la dimostra; **misurata in validazione** = sonda eseguita dal Validatore (Codex) al giro 1 della PR #29, non automatizzata qui; **da verificare** = in un'issue successiva, con dati o con un caso dedicato; **non verificabile** = servirebbe z/OS, che non abbiamo.

| Tema | Cosa si sa | Stato |
| --- | --- | --- |
| Binari: ordine dei byte | `COMP` in big-endian come su z/OS (`binary-byteorder big-endian`); l'area del PARM letta correttamente; con ordine nativo il programma legge 2560 invece di 10 | verificata qui |
| Binari: dimensione | `binary-size 2-4-8`: `S9(4) COMP` occupa 2 byte (l'area del PARM è di 12 byte come attesa) | verificata qui per `S9(4) COMP`; per gli altri formati da verificare |
| Binari: troncamento | `-fbinary-truncate` emula `TRUNC(STD)`. Misurato in validazione: `MOVE 12345` verso `S9(4) COMP` dà 2345 (senza l'opzione 12345). Che coincida con z/OS in tutti i casi non è provato | misurata in validazione; parità z/OS da verificare |
| Aritmetica intermedia | `-std=ibm` attiva `arithmetic-osvs`; cobc avverte che in `CBTRN02C` riga 403 la precisione può cambiare. Misurato in validazione: con A=1,239, B=8, C=100, `A / B * C` a due decimali dà 15,40 con l'opzione e 15,48 senza (il primo coerente, secondo il Validatore, con le regole IBM per quel caso). La parità generale con `ARITH(COMPAT)` non è dimostrata | misurata in validazione; parità da verificare (#5 e successive) |
| Segno dei numeri `DISPLAY` | Con `-fsign=EBCDIC` lettura e scrittura seguono la convenzione dei file di dati del legacy (sezione "Segno dei numeri DISPLAY") | verificata qui |
| Ordine di collazione | ASCII qui, EBCDIC su z/OS: cambiano i confronti tra stringhe con cifre, lettere minuscole e maiuscole, l'ordine di `SORT` e l'ordine delle chiavi nei file indicizzati. Misurato in validazione: il confronto tra `'0'` e `'A'` si inverte con `-fdefault-colseq=EBCDIC`, ma l'ordine delle chiavi restituito da BDB (`0` prima di `A`) **non cambia** con quell'opzione | misurata in validazione; effetto sui programmi da verificare |
| Chiavi alternative con duplicati | `CBACT04C` dichiara `ALTERNATE RECORD KEY IS FD-XREF-ACCT-ID` senza `WITH DUPLICATES`, mentre l'indice alternativo è definito `NONUNIQUEKEY` (`app/jcl/XREFFILE.jcl`, riga 75). Misurato in validazione: con BDB l'inserimento di un record con chiave alternativa già presente dà stato **22**. Come reagisce z/OS non è provato. Su z/OS l'indice alternativo ha anche una sua DD (path), che qui non esiste | GnuCOBOL misurata in validazione; da risolvere in #5; z/OS non verificabile |
| Record variabili | `CBACT01C` scrive `VBRC-FILE` con `RECORDING MODE IS V`. GnuCOBOL (`COB_VARSEQ_FORMAT` 0) mette davanti a ogni record 2 byte di lunghezza big-endian, esclusa l'intestazione, più 2 byte X'00' (misurato in validazione: record `ABC` → `00 03 00 00 41 42 43`); su z/OS il descrittore (RDW) ha 4 byte e la lunghezza include il descrittore | formato GnuCOBOL misurato in validazione; equivalenza da verificare |
| Codici di stato dei file | `OPEN INPUT` di un file assente, sequenziale o indicizzato: stato 35, osservato in 8 programmi, nei 4 file di `CBSTM03B` e in `CBSTM03A` (avvio; prova negativa 9 di `adattamenti`). Su z/OS, secondo la documentazione IBM, un dataset inesistente indicato in una DD con `DISP=SHR` ferma il passo prima dell'avvio del programma (errore di allocazione), e lo stato 35 si ha quando manca la DD: non verificabile qui. Gli altri stati (in particolare quelli specifici di VSAM) non sono stati provati | 35 verificata qui; resto da verificare |
| Arresto anomalo | Qui `CEE3ABD` chiude i file e termina con 99; il record già scritto resta su disco (anche senza chiusura, nel solo caso provato: vedi sezione CEE3ABD). Su z/OS cosa resta di un file aperto al momento di un abend (buffer non scritti) dipende dal metodo di accesso | GnuCOBOL verificata qui per il caso provato; z/OS non verificabile |
| `NEXT SENTENCE` dentro `IF ... END-IF` | In `CBTRN03C` (riga 177). Su IBM salta dopo il punto successivo, oltre l'`END-IF`. Misurato in validazione: GnuCOBOL fa lo stesso nel caso provato | misurata in validazione per un caso; `CBTRN03C` da verificare |
| Campi senza `VALUE` | `defaultbyte 0`: X'00' (misurato in validazione; con `-fdefaultbyte=init` sarebbero spazi per `PIC X` e `'0'` per `PIC 9`). Su z/OS il valore iniziale non specificato è imprevedibile secondo IBM | non verificabile la parità |
| Chiamate dinamiche | Misurato in validazione: `M03BCALL` con `CBSTM03B` collegato staticamente o dinamicamente dà lo stesso output | misurata in validazione per un caso |
| `DISPLAY` e `ACCEPT FROM SYSIN` | stdout e stdin del processo al posto di `SYSOUT` e della DD `SYSIN` (`esegui.sh --sysin`, #36) | verificata qui (stdout; `SYSIN` con la scheda di 80 colonne di `WAITSTEP.jcl`: `COBSWAIT` ne legge i primi 8 caratteri); `SYSIN` vuoto, corto o non numerico solo osservato (`routines/mvswait-osservazioni.md`), parità z/OS non verificabile |

## Esiti dei comandi (issue #35)

Un controllo che non si accorge di un comando fallito dà un falso verde: al giro 3 della PR #29 un `cobcrun --runtime-config` che stampava l'output giusto e poi usciva con 42 lasciava verde tutta la suite. Da #35, negli script `build/compile.sh`, `build/verifica.sh`, `build/run.sh`, `build/check.sh`, `lib.sh` ed `esegui.sh`:

- **Acquisizioni della build.** `compile.sh tutto` legge l'ambiente effettivo (`cobc --version`, due `cobc --info`, `dpkg-query`, due `cobcrun --runtime-config`, le due liste di variabili con `env`, l'estrazione della cartella di configurazione, l'elenco dei suoi file e lo `sha256sum` di ognuno) **prima** di compilare, ciascuno con il suo nome e un solo esito ammesso, 0. Un'acquisizione fallita ferma la build con `compile.sh: acquisizione fallita: <nome> (codice <n>)`; `build/run.sh`, che scrive `build/out/IMPRONTA` solo dopo una build riuscita, non la scrive.
- **Esiti ammessi diversi da 0.** Quello di `cobc` (registrato nel log e in `compilazione.tsv`: decide se la build fallisce) e l'esito 1 di `grep` quando non trova righe (`grep -c` con conteggio 0, `grep -v` su un elenco senza commenti, `grep -E` senza righe `env:`). Ogni altro esito è un errore operativo: ferma lo script o, in `verifica.sh`, è un `DIFETTO`.
- **Costrutti eliminati.** Le sostituzioni di comando `$(…)` dentro gli argomenti di un altro comando (`echo`, `[`, `docker`, `orun`), dove il loro fallimento si perdeva e poteva cambiare l'esito, e le pipeline il cui primo comando poteva fallire senza effetto sull'esito (`grep | wc`, `nm | awk`, `ls | sort` dentro `for`). Al loro posto: assegnazioni con l'esito controllato, file intermedi letti dal passo successivo, `set -o pipefail` (anche in `compile.sh`, `verifica.sh` ed `esegui.sh`, che girano con `dash`), espansioni della shell al posto di `cut` e `basename`, e la tabulazione come costante invece di `$(printf '\t')`. Dopo il giro 1 di validazione della PR #49 la ricerca è stata ripetuta su ogni pipeline e ogni sostituzione di comando di `build/*`, `lib.sh` ed `esegui.sh`: l'elenco con la classificazione e la prova che copre ciascuna è nella descrizione della PR #49. In `verifica.sh` ogni passo di preparazione (elenchi, ordinamenti, confronti) scrive un file e ha l'esito controllato: un passo fallito è un `DIFETTO` ("verifica incompleta"), non un confronto riuscito su dati parziali; le righe `== codice` dei log devono essere tante quante le invocazioni attese di `cobc`. Restano sostituzioni di comando solo nei messaggi di diagnostica scritti dopo che il difetto è già stato contato (per esempio l'elenco delle differenze dopo un `DIFETTO`): un loro fallimento cambia il testo, non l'esito.

Le prove sono in `build/check.sh`, punto 6. Lo schema è sempre lo stesso: un solo comando alla volta è avvolto da `build/avvolgi.sh`, che lo esegue davvero (output autentico), scrive una riga nel registro (`<ID> <invocazione> <esito reale> <esito restituito> <argomenti>`) e restituisce 42. Ogni prova verifica che lo script fallisca per il motivo atteso e, dal registro, che il comando bersaglio sia stato raggiunto con l'esito reale atteso. Le invocazioni ripetute dello stesso comando si provano separatamente (`42@N`: solo l'N-esima; `42:ARG`: solo quella con quell'argomento).

- Acquisizioni: la **build di produzione** (`build/run.sh` con `lib.sh` e l'impronta) gira su una copia dell'oracle in `.work/`, con il legacy collegato, in cui `compile.sh` ha un solo comando avvolto; per ogni punto si verifica anche che `IMPRONTA` non esista. Nel ciclo degli hash fallisce il secondo file (`acu.conf`) dei 40, non l'ultimo. Controprova: tutti gli involucri insieme in modo `passa`, la build riesce, scrive l'impronta e i suoi risultati sono identici a quelli della build normale.
- `esegui.sh` e `verifica.sh`: l'involucro sta davanti nel `PATH` del container (i programmi compilati non lo vedono: partono da `env -i` con `PATH=/usr/bin:/bin`). Controprove con gli involucri in modo `passa`.
- `lib.sh` e le funzioni di `check.sh`, sull'host: il comando è sostituito da una funzione della shell che lo esegue davvero e restituisce 42.

Confronto tra CI e locale: le prove eseguite per passo si contano sul log di `./oracle/run.sh --all --check` con lo stesso `awk` dell'ultimo passo di `.github/workflows/oracle.yml`.

**Limite dichiarato** (regola del registro delle approvazioni nata dalla PR #20): i controlli si accorgono di un comando che fallisce, di un'attesa che non finisce, di una risposta malformata o incompleta, di un risultato rimasto da una corsa precedente; non si difendono da uno strumento sostituito che restituisce dati falsi ma ben formati con esito 0.

## Limiti

- I controlli girano in CI con `.github/workflows/oracle.yml` (issue #35), come utente non privilegiato: il workflow lo esige, perché le prove che rendono un file illeggibile con `chmod 000` con `root` si fermerebbero con un errore esplicito, e registra l'UID effettivo dei container (`orun -- id`).
- Il primo passo della CI costruisce l'immagine dell'oracle su una macchina nuova, con i pacchetti dell'archivio Debian corrente (versioni fissate solo per GnuCOBOL e Berkeley DB, vedi sotto): l'architettura del runner (amd64) può differire da quella locale.
- Nessun programma del legacy gira sui dati reali (#5). Il file dei conti completo e' caricato in un file indicizzato dal passo `dati` (#53), ma `CBACT01C` non vi e' ancora eseguito (#55). Dei dati si legge `dailytran.txt` (sonda sul segno) e, per lo scenario di `CBSTM03A`, 13 righe di `cardxref.txt`, `custdata.txt`, `acctdata.txt` e `dailytran.txt` caricate in quattro piccoli file indicizzati (`adattamenti/registro.md`).
- `CBSTM03A` gira da una copia adattata: le righe di console delle righe 266-291 (nome del job e nomi DD letti dai blocchi di controllo di z/OS) non sono riprodotte (`adattamenti/registro.md`).
- Il controllo degli argomenti di `cobc` legge ciò che `compile.sh` registra: dimostra che le invocazioni registrate sono quelle attese, e `compile.sh` registra gli argomenti nello stesso punto in cui li passa a `cobc`. Una modifica a `compile.sh` che registrasse argomenti diversi da quelli eseguiti non sarebbe vista da questo controllo; per il segno la sonda `SEGNOPRB` ne verifica comunque l'effetto, per gli altri effetti no.
- `CEE3ABD` non riproduce il dump né la gestione delle condizioni di Language Environment.
- I pacchetti sono fissati per versione su un archivio Debian corrente: se Debian ritira una di quelle versioni, la build dell'immagine fallisce (non è stato usato `snapshot.debian.org`).
- `docker build` non ha un limite di tempo proprio; i programmi e le compilazioni sì.
- L'ambiente fissato si applica dentro gli script dell'oracle. Una modifica di `ambiente.sh`, `compile.sh` o `esegui.sh` che aggiungesse variabili all'elenco è vista dal confronto dell'ambiente registrato (e, per `perform-osvs`, dalla sonda `PERFPRB`). Una che le aggiungesse solo all'esecuzione e non alla registrazione sarebbe vista solo dalle sonde semantiche (segno, `PERFORM`), non per le altre impostazioni.
