# Strumenti di analisi del legacy: banco di prova (Wave 0A, issue #1)

Questo documento dice quali strumenti open source esistenti si usano per analizzare CardDemo, perché, e cosa non sanno fare. Ogni riga della tabella nasce da una prova eseguita il 27 novembre 2026 sul sorgente (`legacy/aws-mainframe-modernization-carddemo/`, commit `59cc6c2`), in container, con versioni fissate. Il principio è quello del progetto: non si reimplementa ciò che esiste; lo strumento si adotta solo se il suo output, controllato a campione contro il codice, coincide.

## Come si riproduce

Sull'host servono Git e Docker (più bash e le utility POSIX di base che ogni shell ha). Niente JDK, Maven, GnuCOBOL o Python locali.

```
git submodule update --init
./analysis/run.sh --all             # esegue manifesto e prove degli strumenti (codice 0)
./analysis/run.sh --all --check     # esegue tutti i controlli a campione e le prove negative (codice 0)
./analysis/run.sh manifest          # una sola analisi; con --check i suoi controlli
```

Struttura (tutto sotto `analysis/`):

| Percorso | Contenuto |
| --- | --- |
| `run.sh` | l'unico punto d'ingresso; non va modificato per aggiungere analisi |
| `<nome>/run.sh`, `<nome>/check.sh`, `<nome>/deps` | una analisi = una cartella; `deps` elenca le cartelle da cui dipende, una per riga |
| `manifest/` | manifesto dei sorgenti (`sources.tsv`) |
| `tools/` | questa valutazione: `trials/` (una prova per strumento), `docker/` (un Dockerfile per strumento), `glue/` (script di colla), `expected/` (attesi scritti a mano), `out/` (output grezzo e verdetti), `capabilities.tsv` |
| `selftest/` | test automatico del comando unico (dipendenze, ordine, cicli, primo errore) |
| `lib/common.sh` | funzioni condivise dagli script |

Per aggiungere un'analisi si crea `analysis/<nome>/` con `run.sh` (e se serve `check.sh` e `deps`). `./analysis/run.sh --all` la trova da sola e la esegue dopo le cartelle da cui dipende (ordine topologico, alfabetico a parità). Gli script ricevono `ANALYSIS_ROOT` e `ANALYSIS_NAME` e possono includere `lib/common.sh`. Gli output grezzi vanno in `analysis/<nome>/out/`.

Due dettagli di metodo che influenzano i risultati:

- **Il legacy viene copiato in un volume Docker** (`menb-analysis-legacy-<commit>`) prima di essere letto dagli strumenti. Motivo: su macOS i bind mount di Docker Desktop possono risolvere i nomi senza distinguere maiuscole (si è visto `COPY CUSTREC` trovare `CUSTREC.cpy` come `CUSTREC.CPY`), quindi gli stessi comandi darebbero risultati diversi su un host Linux. Il volume ha un file system sensibile alle maiuscole, come quello di un host Linux. Il sorgente non viene modificato né pre-elaborato: è una copia byte per byte (`cp -a`).
- **Gli attesi sono scritti a mano** in `analysis/tools/expected/` leggendo il sorgente (righe e programmi citati nei file), non copiando l'output degli strumenti. `check.sh` li confronta con l'output normalizzato; per ogni controllo esiste una prova negativa che altera un valore atteso e pretende che il controllo fallisca.

## Il manifesto dei sorgenti

`analysis/manifest/sources.tsv` ha una riga (percorso, tipo) per ognuno dei 329 file tracciati nell'intero submodule, ricavati da `git -C $LEGACY ls-files -z` (Git sull'host; la classificazione gira in container). Il tipo si assegna senza distinzione di maiuscole, con le regole elencate in testa a `analysis/manifest/classify.py`: cartelle speciali (`samples/`, `diagrams/`, `scripts/`), poi estensione. Conteggi per tipo (`analysis/manifest/out/summary.tsv`):

| Tipo | File | Tipo | File | Tipo | File |
| --- | ---: | --- | ---: | --- | ---: |
| cobol | 44 (31 sotto `app/cbl/`) | copybook | 62 | bms | 21 |
| jcl | 46 | data | 24 | doc | 20 |
| sample | 15 | script | 11 | ims | 8 |
| ctl | 8 | ddl | 6 | csd | 4 |
| dcl | 3 | asm | 2 | macro | 2 |
| proc | 2 | scheduler | 2 | **other** | **49** |

I 49 file `other` sono elencati in `analysis/manifest/out/other.txt`: 4 file `.gitkeep`/`.gitignore` e i 45 file senza estensione di `scripts/markers/`, che sono marcatori di stato degli script e non sorgenti. Le estensioni maiuscole sono trattate come le minuscole: i 5 programmi `.CBL` (`CBSTM03A`, `CBSTM03B`, `DBUNLDGS`, `PAUDBLOD`, `PAUDBUNL`) risultano `cobol`. Scelte dove la specifica lasciava margine: i file sotto `samples/` sono `sample` anche se hanno estensione `jcl`/`prc`; `LICENSE` e `NOTICE` di primo livello, `md`, `png` e `drawio` sono `doc`; `txt` e `.PS` sono `data`.

## Tabella dei candidati

Legenda dell'esito: *funziona* = produce quanto serve e supera i controlli a campione; *in parte* = produce output corretto ma incompleto per l'uso richiesto; *non funziona* = non si installa o non gira. `/legacy` è il sorgente montato in sola lettura nel container.

| Strumento | Capacità | Versione | Licenza | Ultimo rilascio | Comando | Esito | Limiti osservati | Verdetto |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| scc | conteggi | 4.1.0 (binario Linux ufficiale, SHA-256 verificato) | MIT ([LICENSE](https://github.com/boyter/scc/blob/master/LICENSE)) | 2026-09-07 (v4.1.0) | `scc --no-config --no-gitignore --no-ignore --no-scc-ignore --no-cocomo --no-complexity --by-file -f csv /legacy/app` | funziona | Non conosce BMS, CSD, CTL, DCL, MAC, PSB/DBD, ca7/controlm: 54 file di `app/` non contati (21 mappe BMS comprese). Classifica i file EBCDIC `.PS` come PostScript (11 file, una riga ciascuno, non sono codice) e salta quello binario (`EXPORT.DATA.PS`). | adottato per i conteggi: file e righe di `app/cbl` (31 / 20.650), `app/cpy` (30 / 2.786), `app/jcl` (38 / 2.429) coincidono con la baseline del progetto; copertura consegnata e mancante: vedi "Copertura dei conteggi" sotto |
| GnuCOBOL | compilazione e diagnostica | 3.2 (`cobc` 3.2.0, pacchetto Debian `gnucobol3` 3.2-3) | GPL-3+ per `cobc`; LGPL-3+ per il runtime ([sito](https://www.gnu.org/software/gnucobol/), file `copyright` del pacchetto) | 2023-07-28 (3.2, [ftp.gnu.org](https://ftp.gnu.org/gnu/gnucobol/)) | `cobc -fsyntax-only -std=ibm -I /legacy/app/cpy -I /legacy/app/cpy-bms /legacy/app/cbl/<P>` per i 31 programmi | funziona | Non esegue `EXEC CICS`: i 17 programmi online falliscono (atteso, non aggirato). Fallisce anche su 3 programmi batch per ragioni che stanno nel sorgente (vedi sotto). Il dialetto `-std=ibm` non è z/OS. | adottato per sintassi e diagnostica dei batch (#4): 11 programmi senza errori, 20 con errori tutti spiegati |
| cobol-migration-toolkit | grafi COPY e CALL | 0.8.0 (tag `v0.8.0`, commit `2e2a9e0`) | Apache-2.0 ([LICENSE](https://github.com/makedirectory/cobol-migration-toolkit/blob/v0.8.0/LICENSE)) | 2026-07-22 (v0.8.0; beta) | `cobol-migrate scan /legacy/app/cbl --copybook-path /legacy/app/cpy --copybook-path /legacy/app/cpy-bms --format json --format dot --output /out` | in parte | Basato su regex. Per i COPY riporta solo l'insieme dei nomi per programma: niente riga, niente occorrenze ripetute (in `COACTUPC` 18 nomi contro 56 occorrenze), `REPLACING` solo come segnalazione sul nome. Non vede i trasferimenti `EXEC CICS XCTL`/`LINK` (0 su 2 attesi in `COSGN00C`). Le CALL statiche le trova tutte (3 su 3 attese). | adottato solo per le CALL; scartato per le occorrenze COPY: il controllo sulle occorrenze con riga e sostituzioni fallisce, quindi non è adottabile da solo per la capacità |
| cobmix | grafi COPY e CALL (riserva) | 0.1.2 (PyPI; la 0.1.0 del README dà lo stesso esito) | non accertata: nessun file LICENSE nel repository, metadati PyPI vuoti | 2026-09-29 (0.1.2, [PyPI](https://pypi.org/project/cobmix/)) | `cobmix --code-file /legacy/<P> --copy-path /legacy/app/cpy --copy-path /legacy/app/cpy-bms --graphs copybook --format json --output /out/<P>` | in parte | Conserva una occorrenza per ogni COPY e il loro ordine (56 in `COACTUPC`), ma gli archi non hanno numero di riga né sostituzioni `REPLACING`. Non ha una vista CALL tra quelle richieste (ast, cfg, dfg, copybook, overlay, division). | scartato: provato perché cmt era insufficiente; fallisce il controllo sulle occorrenze (manca riga e `REPLACING`) |
| ProLeap COBOL parser | grafi COPY e CALL (riserva) | commit `d1bfe75` (versione del pom 4.0.0), compilato dai sorgenti con Maven; più una colla Java di circa 60 righe (`CopyLister.java`) | MIT ([LICENSE](https://github.com/uwol/proleap-cobol-parser/blob/d1bfe75bdd6d480f70c74c6345bcc02610ac30d3/LICENSE)); `CLAUDE.md` del progetto la dava come AGPL-3: non è così | ultimo tag v2.4.0 del 2018-01-01; ultimo commit 2026-03-01 (il jar 4.0.0 non è su Maven Central al percorso atteso, HTTP 404) | `java -cp glue:classes:lib/* CopyLister /legacy/<P>` per i 31 programmi | funziona | È una libreria, senza riga di comando: serve la colla Java, che usa le classi di ProLeap per normalizzare le righe a formato fisso e il parser del suo preprocessore, senza scrivere un parser. Oggi si usa solo per le occorrenze COPY; CALL e il resto dell'albero non sono stati provati. | adottato per le occorrenze COPY con riga e sostituzioni: coincidono con gli attesi per `COBIL00C`, `CBTRN02C`, `COACTUPC` (71 occorrenze, 39 distinte di `CSSETATY`) e nel numero per tutti i 31 programmi (252) |
| Koopa | grafi COPY e CALL (riserva) | - | - | - | - | - | - | non provato |
| cb2xml | copybook → tracciato | 1.01.08 (jar della release, SHA-256 verificato) | LGPL-2.1 ([repository](https://github.com/bmTas/cb2xml)) | 2024-07-30 (1.01.08; il repository ha commit fino al 2026-10-01) | `java -cp cb2xml.jar net.sf.cb2xml.Cb2Xml -cobol /legacy/app/cpy/<C>.cpy -xml /out/<C>.xml -indentXml -Dialect Mainframe` per `CVACT01Y`, `CVACT03Y`, `CVTRA05Y`, `CVEXPORT` | funziona | Il jar della release non ha classe principale nel manifest: si lancia con `-cp` e `net.sf.cb2xml.Cb2Xml`. Le posizioni sono da 1 (si portano a offset da 0). Per i gruppi `OCCURS` la lunghezza è per singolo elemento. | adottato per i tracciati (#3): lunghezze 300 / 50 / 350 / 500 e campi attesi coincidono |
| JRecord | copybook → tracciato (riserva) | - | - | - | - | - | - | non provato |
| mapa | analisi JCL | commit `d05705a` (cartella `jcl/`, applicazione `Demo01`), compilato dai sorgenti | MIT ([LICENSE](https://github.com/cschneid-the-elder/mapa/blob/d05705af310730c3e9aa848e824755e652618512/LICENSE)) | nessun rilascio né tag; ultimo commit 2026-11-16 | `java -cp class:antlr-4.13.2-complete.jar:commons-cli-1.4.jar Demo01 -file /legacy/app/jcl/<J> -include /legacy/app/proc -outcsv /out/<J>.csv` per `POSTTRAN.jcl`, `INTCALC.jcl`, `CREASTMT.JCL`, `ACCTFILE.jcl` | funziona | Il Makefile del progetto richiede più passate (la prima segnala errori attesi dai suoi autori) e due jar inclusi nel repository (ANTLR 4.13.2, commons-cli 1.4): si usano quelli, il `JCLParser.jar` precompilato no. Scrive un log nella cartella corrente. L'output grezzo contiene UUID e orari: non è deterministico, si versiona solo la forma normalizzata. Non riporta `PARM=` né le istruzioni IDCAMS/SORT in `SYSIN *`; per le DD `SYSOUT=*` riporta `SYSOUT` senza classe; una generazione GDG appare come `AWS.M2.CARDDEMO.DALYREJS(+1)`. | adottato per passi, programmi, DD e dataset (#2, #7): i 10 passi attesi e le 9 DD di `POSTTRAN` coincidono |

### Dettaglio dei risultati che vanno oltre una cella

**scc.** 186 dei 240 file di `app/` sono contati (COBOL 106 file / 40.826 righe, JCL 46, Plain Text 10, SQL 6, Markdown 3, Assembly 2, PL/SQL 2, PostScript 11). I 54 non contati sono tutti spiegati dall'estensione sconosciuta (bms, ca7, controlm, csd, ctl, dat, dbd, dcl, gitkeep, init, mac, psb) più il file binario. Il controllo confronta contati + non contati con il numero di file del manifesto sotto `app/` (240).

**Copertura dei conteggi (scc).** Consegnato e controllato:
- per ogni file contato, righe = codice + commenti + vuote; per `app/cbl`, `app/cpy`, `app/jcl` tutte le colonne dell'aggregato (file, righe, codice, commenti, vuote, byte) coincidono con la somma dei file; file e righe coincidono con la baseline del progetto (31 / 20.650, 30 / 2.786, 38 / 2.429);
- sei campioni contati a mano (`analysis/tools/expected/scc_files.tsv`) per righe, codice, commenti e vuote: quattro coincidono con scc (`CVACT03Y.cpy`, `CVTRA05Y.cpy`, `COBSWAIT.cbl`, `POSTTRAN.jcl`).

Divergenze di scc osservate e registrate nei campioni (il controllo fallisce se cambiano): in COBOL scc riconosce come commento solo la riga il cui primo carattere non bianco è `*`, quindi **una riga commento con numero di sequenza nelle colonne 1-6 (`000100*****`) è contata come codice**: `CBACT01C.cbl` ha 51 commenti a colonna 7, scc ne dà 30 (e 379 righe di codice contro 358). In assembler scc non riconosce i commenti a colonna 1: `MVSWAIT.asm` ha 16 righe commento, scc 0. Quindi **la ripartizione codice/commenti di scc non è affidabile sui file COBOL con numeri di sequenza e su tutti gli assembler**; righe totali e vuote lo sono nei campioni.

Non coperto, e non consegnato da questa issue: i 54 file di `app/` che scc non conta (21 mappe BMS, 8 CTL, 4 CSD, 3 DCL, 2 MAC, 8 tra PSB e DBD, più `.dat`, `.INIT`, `.gitkeep`, ca7, controlm e il binario `EXPORT.DATA.PS`) e, per gli stessi motivi, tutti i file fuori da `app/`. La baseline del progetto per i BMS (17 file / 4.472 righe) è una misura precedente con `wc -l` e **non è riprodotta da questo banco**; chi ne ha bisogno deve aggiungere la propria analisi in una nuova cartella sotto `analysis/`.

**GnuCOBOL.** Esito per i 31 programmi di `app/cbl/` (tabella completa in `analysis/tools/out/gnucobol/syntax.tsv`, diagnostica per programma in `out/gnucobol/log/`):

- 11 senza errori: `CBACT01C`–`CBACT04C`, `CBCUS01C`, `CBSTM03B`, `CBTRN01C`–`CBTRN03C`, `COBSWAIT`, `CSUTLDTC`.
- 17 online con errori, attesi: contengono `EXEC CICS` e fanno `COPY DFHAID`/`DFHBMSCA`, che non esistono nel repository. Registrati, non aggirati.
- `CBEXPORT` e `CBIMPORT` (1 errore ciascuno): `RECORD KEY IS EXPORT-SEQUENCE-NUM`, ma quel campo è definito in `WORKING-STORAGE` (`COPY CVEXPORT`) e non nel record dell'`FD`, che è `PIC X(500)`. **Il programma, così com'è, è rifiutato da GnuCOBOL; non si è verificato se lo accetti il compilatore IBM.** Rilevante per #4.
- `CBSTM03A` (39 errori): `COPY CUSTREC` include `CUSTREC.cpy`, che contiene caratteri TAB nelle righe da 6 in poi; `cobc` non li accetta nel formato fisso. Il sorgente non è stato modificato. Rilevante per #4.

Il dialetto è `-std=ibm`; non si è provato `ibm-strict`.

**Grafi COPY e CALL.** La capacità richiede due cose e le prove le hanno separate.
- *CALL:* cobol-migration-toolkit trova `CBACT01C → COBDATFT`, `CBACT01C → CEE3ABD` e `COBSWAIT → MVSWAIT`; elenca come non risolti `CEE3ABD`, `CEEDAYS`, `COBDATFT`, `MVSWAIT` (non sono programmi del repository: `COBDATFT` e `MVSWAIT` sono in assembler sotto `app/asm/`, gli altri due servizi di runtime). **I trasferimenti `EXEC CICS XCTL` e `LINK` non sono visti**: in `COSGN00C` i due `XCTL` verso `COADM01C` e `COMEN01C` (righe 231 e 236) non compaiono nel grafo. Nei programmi di menu il programma di destinazione è in variabile (per esempio `PROGRAM(CDEMO-MENU-OPT-PGMNAME(WS-OPTION))` in `COMEN01C`, riga 185): *quale* destinazione sia scelta si decide a tempo di esecuzione, in base all'opzione digitata, e nessuno degli strumenti provati la risolve. L'*insieme delle destinazioni possibili* invece è ricavabile staticamente dal sorgente: la tabella `CDEMO-MENU-OPT` di `app/cpy/COMEN02Y.cpy` (dati `VALUE` sotto `CDEMO-MENU-OPTIONS-DATA`, esposti con `REDEFINES`) elenca `COACTVWC`, `COACTUPC`, `COCRDLIC`, `COCRDSLC`, `COCRDUPC`, `COTRN00C`, `COTRN01C`, `COTRN02C`, `CORPT00C`, `COBIL00C` e `COPAUS0C` (quest'ultimo è un modulo opzionale). Questa estrazione non è consegnata da questo banco di prova: è lavoro per #2.
- *COPY:* il controllo confronta le occorrenze con riga e sostituzioni per `COBIL00C` (10), `CBTRN02C` (5), `COACTUPC` (56, di cui 39 di `CSSETATY` con `REPLACING` diversi da riga 3208). cobol-migration-toolkit e cobmix falliscono (motivi in tabella; evidenza in `out/cmt/verdetto-copy.txt` e `out/cobmix/verdetto-copy.txt`); ProLeap passa. In più, per tutti i 31 programmi il numero di COPY riportato coincide con una ricerca testuale indipendente (`expected/copy_counts.tsv`, 252 occorrenze).
- Koopa, ultima riserva, non è stato toccato perché ProLeap è adottabile.

**Tracciati (cb2xml).** Opzioni di rappresentazione: dialetto `Mainframe`, formato XML 2017. Con questo dialetto un `COMP` occupa 2 byte fino a 4 cifre, 4 byte da 5 a 9, 8 byte da 10 a 18 (convenzione IBM, `TRUNC` standard); `COMP-3` occupa (cifre + 1) / 2 byte arrotondati per eccesso. Gli attesi a mano riguardano: i primi sei campi di `CVACT01Y` (offset 0, 11, 12, 24, 36, 48; i tre importi da 12 byte `ACCT-CURR-BAL`, `ACCT-CREDIT-LIMIT`, `ACCT-CASH-CREDIT-LIMIT` non risultano scambiati), `CVEXPORT` con un campo `COMP` (`EXPORT-SEQUENCE-NUM`, 4 byte), due `COMP-3` (`EXP-ACCT-CURR-BAL`, 7 byte con scala 2; `EXP-CUST-FICO-CREDIT-SCORE`, 2 byte), un `COMP` con scala (`EXP-ACCT-CURR-CYC-DEBIT`, 8 byte) e due coppie `REDEFINES`. La lunghezza di `CVEXPORT` ottenuta (500) si confronta con `RECORDSIZE(500 500)` di `app/jcl/CBEXPORT.jcl`: nessuna differenza. Osservazione per #3, non verificata sul manuale IDCAMS: lo stesso JCL dichiara `KEYS(4 28)`, mentre `EXPORT-SEQUENCE-NUM`, la chiave dichiarata nel programma, ha offset 27 (da zero) e lunghezza 4; se l'offset di `KEYS` è contato da zero le due definizioni differiscono di un byte.

**JCL (mapa).** Passi attesi verificati: `POSTTRAN` (`STEP15` → `CBTRN02C`, riga 23), `INTCALC` (`CBACT04C`), `CREASTMT` (`IDCAMS`, `SORT`, `IDCAMS`, `IEFBR14`, `CBSTM03A`), `ACCTFILE` (3 × `IDCAMS`). Per `POSTTRAN`, tutte e 9 le DD con il loro dataset, comprese quelle scritte su righe di continuazione (`DSN=` sulla riga successiva a `DD DISP=`) e `DALYREJS` verso la generazione GDG `(+1)`.

## Capacità → percorso utilizzabile

Stato registrato anche in `analysis/tools/capabilities.tsv` e verificato da `check.sh`.

| Capacità | Stato | Strumenti | Issue che ne dipendono | Come si usa |
| --- | --- | --- | --- | --- |
| conteggi | available | scc | paper | `./analysis/run.sh tools`, output in `analysis/tools/out/scc/` |
| compilazione-diagnostica | available | gnucobol | #4 | `analysis/tools/out/gnucobol/syntax.tsv` e `log/` |
| grafi-copy-call | available | proleap+cmt | #2 | COPY da `out/proleap/copy.tsv` (riga e sostituzioni); CALL da `out/cmt/calls.tsv` e `calls.dot`. Gli `XCTL`/`LINK` CICS non sono visti da nessuno dei due: vanno ricavati altrimenti |
| tracciati-copybook | available | cb2xml | #3 | `out/cb2xml/*.xml` e `layout.tsv` |
| analisi-jcl | available | mapa | #2, #7 | `out/mapa/jcl_steps.tsv` e `jcl_dd.tsv` |

Nessuna capacità risulta `unavailable`: non c'è quindi un ripiego da descrivere e nessuna delle issue a valle (#2, #3, #7) resta bloccata da questa valutazione.
