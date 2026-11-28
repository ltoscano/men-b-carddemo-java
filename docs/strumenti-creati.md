# Catalogo degli strumenti creati in questo progetto

Aggiornato il 27 novembre 2026, 21:31 UTC, allo stato di `main`. Si aggiorna a ogni merge che aggiunge o cambia un comando.

Questo file risponde a una domanda sola: **che cosa abbiamo costruito noi, a che serve, come si lancia e dove è spiegato**. Gli strumenti di terzi adottati o scartati (scc, GnuCOBOL, ProLeap, cb2xml, mapa, cobol-migration-toolkit) sono in [`legacy-map/strumenti.md`](legacy-map/strumenti.md).

Tutto gira in container: sull'host servono solo Docker e Git.

## I comandi, in breve

| Comando | A che serve | Documentazione |
| --- | --- | --- |
| `./verify.sh` | compila e prova il codice Java (cinque moduli), con PostgreSQL reale e le regole sul codice | [`sviluppo.md`](sviluppo.md) |
| `./smoke.sh` | avvia l'applicazione con Docker Compose, controlla che risponda, ripulisce | [`sviluppo.md`](sviluppo.md) |
| `./analysis/run.sh <nome>`, `--check`, `--all` | esegue un'analisi del legacy, o ne ricontrolla i risultati rigenerandoli da zero | questo file; ogni analisi ha il suo documento (sotto) |
| `./oracle/run.sh <passo>`, `--check`, `--all` | compila ed esegue i programmi COBOL originali con GnuCOBOL: è il riferimento contro cui si misurerà il Java | [`../oracle/README.md`](../oracle/README.md) |
| `./quality/regressioni-verify.sh`, `./quality/regressioni-regole.sh`, `./quality/regressioni-copertura.sh`, `./quality/regressioni-codec.sh` | provano che `./verify.sh` e le regole sul codice falliscono quando devono | [`sviluppo.md`](sviluppo.md) |
| `paper/data/tlog.sh` | registra un evento con l'ora, per i tempi del paper | `CLAUDE.md`, sezione "Misura dei tempi" |

## Analisi del legacy (`analysis/`)

Un'analisi è una cartella `analysis/<nome>/` con `run.sh` (produce), `check.sh` (ricontrolla, con prove negative) e `deps` (da quali altre analisi dipende). `analysis/run.sh` le esegue nell'ordine giusto. Il sorgente si legge da un volume Docker che distingue le maiuscole, mai modificato.

| Analisi | Che cosa produce | Di che cosa è fatta | Risultati e documento | Issue / PR |
| --- | --- | --- | --- | --- |
| `tools` | la prova degli strumenti di terzi su CardDemo, con un verdetto per ciascuna capacità | immagini Docker degli strumenti con versioni fissate; colla per normalizzare gli output; attesi scritti a mano | [`legacy-map/strumenti.md`](legacy-map/strumenti.md) | #1, #21 / PR #18, #31 |
| `inventory` | l'inventario dei sorgenti e il grafo delle dipendenze statiche: `COPY`, `CALL`, passi e file dei JCL, transazioni | colla Python che unisce gli output di ProLeap, cobol-migration-toolkit e mapa; estrattori nostri per le schede JCL e le definizioni CSD; un verificatore separato | [`legacy-map/inventario.md`](legacy-map/inventario.md), `graph.json`, `graph.schema.json` | #2 / PR #30 |
| `inventory-cics` | i comandi `EXEC CICS` dei programmi online: passaggi di controllo, mappe, file, code, punti di chiusura della transazione | un piccolo programma Java sopra ProLeap che elenca i blocchi; colla Python per estrazione, risoluzione dei bersagli e grafo; un verificatore con implementazione separata | [`legacy-map/inventario-cics.md`](legacy-map/inventario-cics.md), `graph-cics.json` | #22 / PR #50 |
| `data-contract` | il contratto dati: per ogni tracciato, posizione, lunghezza e tipo di ogni campo; chiavi dei file; relazioni tra strutture e record | colla Python sopra cb2xml; censimento e relazioni scritti a mano e controllati | [`legacy-map/data-contract/`](legacy-map/data-contract/) (`contratti.md`, `chiavi.md`, `censimento.md`, `discordanze.md`) | #3, #41 / PR #32, #42 |
| `data-codec` | le regole con cui i byte di un campo diventano un valore e viceversa, in due profili (z/OS e oracle GnuCOBOL) | una libreria Python (`glue/codec.py`); vettori di prova scritti a mano; due programmi COBOL di prova eseguiti nell'ambiente dell'oracle | [`legacy-map/data-contract/codifica.md`](legacy-map/data-contract/codifica.md) | #23 / PR #47 |
| `data-sentinelle` | la prova che il contratto dati mette ogni campo al posto giusto: 23 record di prova scritti a mano dai copybook (241 campi), decodificati con le regole di `data-codec` | record di prova e attesi scritti a mano; uno strumento che compone i byte senza leggere il contratto; un adattatore dal contratto alla libreria di codifica; un verificatore in cui ogni controllo ha una prova negativa dedicata | [`legacy-map/data-contract/sentinelle.md`](legacy-map/data-contract/sentinelle.md) | #43 / PR #51 |
| `data-fixtures` | i dati di esempio di CardDemo (22 file, ASCII ed EBCDIC, 1.813 record) decodificati campo per campo in file versionati, con l'elenco delle anomalie trovate nei dati | 55 record attesi scritti a mano leggendo i byte; un controllo che rilegge i byte del file per conto suo e li confronta con i record ricostruiti; il confronto tra versione ASCII ed EBCDIC dello stesso dato; 84 prove negative | [`legacy-map/fixture.md`](legacy-map/fixture.md) | #5 / PR #56 |


## Oracle GnuCOBOL (`oracle/`)

L'immagine in cui i programmi batch originali si compilano e si eseguono senza modifiche al sorgente (con due adattamenti dichiarati per un solo programma). Documentazione: [`../oracle/README.md`](../oracle/README.md).

| Parte | Che cosa fa | Issue / PR |
| --- | --- | --- |
| `Dockerfile`, `cobc.opts`, `ambiente.sh` | immagine con GnuCOBOL 3.2 a versione fissata; opzioni di compilazione, ciascuna con il motivo; ambiente fissato per compilatore e programmi | #4 / PR #29 |
| `launcher/avvia.c` | l'avviatore: fa partire un programma COBOL passandogli il `PARM` come farebbe il JCL | #4 / PR #29 |
| `esegui.sh` | esegue un programma in una cartella vuota e scrive un rapporto: codice di uscita, uscite, file creati | #4, #35 / PR #29, #49 |
| passo `build` | compila i 12 programmi e i moduli, registra ogni invocazione del compilatore, scrive un'impronta di ingressi e risultati | #4, #25, #35 |
| passi `avvio`, `avviatore`, `abend`, `segno`, `dialetto` | prove mirate: ogni programma parte; il `PARM` arriva giusto; l'arresto anomalo dà il codice atteso; i segni degli importi si leggono giusti; il dialetto è quello fissato | #4 / PR #29 |
| passo `routines`, `stubs/COBDATFT.cbl` | equivalente in COBOL di una routine assembler, solo per i casi determinati dal sorgente | #24 / PR #39 |
| passo `routines`, `stubs/MVSWAIT.cbl` | equivalente in COBOL della routine assembler di attesa: non attende, scrive su stderr il valore richiesto, si ferma con 97 oltre il limite del servizio; la durata è controllata per differenza con una corsa di controllo | #36 / PR #52 |
| `esegui.sh --sysin <file>` | passa a un programma l'ingresso che sul mainframe arriva dalla scheda `SYSIN` del JCL; il rapporto ne riporta dimensione e impronta | #36 / PR #52 |
| passo `adattamenti` | il batch degli estratti conto (`CBSTM03A`) con due adattamenti su copie di compilazione, più uno scenario con quattro file indicizzati | #25 / PR #44 |
| `stubs/` | sostituti dichiarati di ciò che in un container non esiste: `CEE3ABD` (arresto anomalo); segnaposto per `CEEDAYS`, che ferma l'esecuzione con un codice riconoscibile | #4 |
| `tests/` | piccoli programmi COBOL di prova scritti da noi (eco del `PARM`, sonde su segno e dialetto, caricamento e rilettura di file indicizzati) | varie |

## Lato Java (`verify.sh`, `smoke.sh`, `quality/`, `docker/`, `compose.yaml`)

Documentazione: [`sviluppo.md`](sviluppo.md).

| Parte | Che cosa fa | Issue / PR |
| --- | --- | --- |
| cinque moduli Maven (`carddemo-domain`, `-loader`, `-online`, `-batch`, `-parity`) | lo scheletro dell'applicazione; per ora senza funzioni di CardDemo | #13 / PR #17 |
| `compose.yaml`, `docker/` | database, servizio online, runner batch | #14 / PR #20 |
| test di integrazione con PostgreSQL reale | Testcontainers; `quality/RapportoSurefire.java` controlla che il rapporto dei test sia di questa corsa e completo | #15 / PR #33 |
| regole sul codice | dipendenze tra moduli, database in memoria vietati, numeri in virgola mobile e `var` vietati, test di architettura | #26 / PR #40 |
| copertura dei test e analisi statica | JaCoCo (rapporto aggregato) e SpotBugs dentro `./verify.sh`; `quality/RapportiQualita.java` controlla che i rapporti siano di questa corsa, completi e prodotti con la configurazione fissata; regressioni in `./quality/regressioni-copertura.sh` (anche per sottoinsieme di casi, `--lista` per i nomi) | #27 / PR #48 |
| codifica dei campi COBOL in Java (`carddemo-domain`: `GnuCobolFieldCodec`, `FieldPicture`) | decodifica, ricodifica e codifica dei campi nel profilo dell'oracle, senza virgola mobile; un passo di `./verify.sh` pretende nel rapporto dei test tutti i 375 vettori di riferimento, per identificativo e nell'ordine del file; un test ispeziona il codice compilato e vieta virgola mobile, conversioni con perdita e restringimenti non motivati; regressioni in `./quality/regressioni-codec.sh` (26 casi) | #54 / PR #57 |


## CI (`.github/workflows/`)

| Workflow | Che cosa esegue |
| --- | --- |
| `ci.yml` | `./verify.sh` e `./smoke.sh` |
| `analysis.yml` | `./analysis/run.sh --all --check` |
| `oracle.yml` | `./oracle/run.sh --all --check` |

## Quanto codice è

Misura del 21:31 UTC su `main`, righe dei file versionati esclusi dati, attesi, vettori e documenti (comando: `git ls-files <cartella>` filtrato e `wc -l`; è un conteggio di righe, non di istruzioni):

| Area | Righe |
| --- | ---: |
| `analysis/` (sei analisi e parti comuni; la misura non comprende `data-sentinelle`, aggiunta dopo) | circa 13.300 |
| `oracle/` | circa 5.100 |
| `quality/` | circa 1.100 |
| `verify.sh`, `smoke.sh`, `analysis/run.sh`, `oracle/run.sh` | circa 1.000 |

La regola del progetto è scrivere codice proprio solo per incollare strumenti esistenti. Queste ventimila righe vanno lette così: gli strumenti di terzi fanno l'analisi; il codice nostro li collega, ne normalizza gli output e soprattutto **controlla** i risultati (verificatori separati, prove negative). Quanta parte sia colla e quanta controllo non è stato misurato.

## Che cosa non è documentato altrove

- Non esiste un `README` dentro `analysis/`: questo file ne fa le veci.
- I file `glue/*.py` delle analisi sono descritti solo dai commenti in testa a ciascuno e dal documento dell'analisi.
- Le decisioni prese strada facendo sono in [`registro-approvazioni.md`](registro-approvazioni.md); il racconto passo per passo è nel paper (`paper/mec-b-paper.md`).
