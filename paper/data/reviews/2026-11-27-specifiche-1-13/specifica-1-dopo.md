## Obiettivo
Stabilire, con prove eseguite sul sorgente CardDemo, quali strumenti open source esistenti usare per l'analisi del legacy nelle issue successive, e lasciare tre cose riusabili: un manifesto esplicito dei sorgenti, un comando unico estendibile, un verdetto motivato per ogni strumento.

Principio: non si reimplementa ciò che esiste. Questa issue non produce l'inventario né il contratto dati: decide con quali strumenti produrli e dimostra che funzionano.

## Dipendenze e perimetro
- Dipende da: nessuna.
- Sorgenti legacy di riferimento (sola lettura): `legacy/aws-mainframe-modernization-carddemo/` (d'ora in poi `$LEGACY`), in particolare `app/`.
- Cartelle coinvolte (le sole modificabili): `analysis/`, `docs/legacy-map/strumenti.md`.
- Fuori ambito: inventario completo, grafi definitivi, contratto dati, esecuzione dei batch, codice Java, analizzatori scritti da zero.

## Specifica

### 1. Manifesto dei sorgenti
`analysis/manifest/sources.tsv`: una riga per ogni file tracciato nell'**intero submodule** `$LEGACY` (non solo `app/`: anche `README.md`, `scripts/` e `samples/` sono fonti per le issue successive), con percorso e tipo (`cobol`, `copybook`, `bms`, `jcl`, `proc`, `asm`, `macro`, `csd`, `ctl`, `ddl`, `dcl`, `ims`, `data`, `scheduler`, `script`, `doc`, `sample`, `other`).

- La fonte di verità è `git -C $LEGACY ls-files`, non un glob.
- Il tipo si assegna **senza distinzione di maiuscole** sull'estensione: nel repository convivono `.cbl` e `.CBL`, `.cpy` e `.CPY`, `.jcl` e `.JCL`. Cinque programmi COBOL hanno estensione maiuscola, tra cui `app/cbl/CBSTM03A.CBL` e `app/cbl/CBSTM03B.CBL`.
- Ogni file ha esattamente un tipo; ciò che non si riconosce è `other` ed è elencato.
- Tutte le issue successive enumerano i sorgenti da questo manifesto.

### 2. Comando unico estendibile
`./analysis/run.sh` è l'unico punto d'ingresso e usa solo Docker.

- `./analysis/run.sh <nome>` esegue `analysis/<nome>/run.sh`; `./analysis/run.sh <nome> --check` esegue `analysis/<nome>/check.sh`.
- Una cartella può dichiarare da quali altre dipende in un file `analysis/<nome>/deps` (un nome per riga). `./analysis/run.sh --all` e `--all --check` eseguono tutte le cartelle **rispettando le dipendenze** (ordine topologico, alfabetico a parità), falliscono al primo errore e segnalano dipendenze mancanti o cicliche.
- Aggiungere un'analisi significa aggiungere una cartella: `analysis/run.sh` non va più modificato dalle issue successive. Questo va dimostrato con un test automatico che crea in una cartella temporanea due analisi di prova, un produttore e un consumatore il cui nome precede alfabeticamente quello del produttore, e verifica che il consumatore trovi l'output del produttore partendo da output assenti.
- Gli output grezzi vanno in `analysis/<nome>/out/` e sono versionati quando sono deterministici.

### 3. Prova degli strumenti
Ogni prova gira in un container con versione dello strumento fissata.

| Capacità | Obbligatoria per | Candidati | Prova minima |
| --- | --- | --- | --- |
| Conteggi (file, righe di codice / commento / vuote) | paper | scc | conteggio su `$LEGACY/app/`; totale file confrontato con il manifesto |
| Compilazione e diagnostica | #4 | GnuCOBOL (`cobc -fsyntax-only`, dialetto IBM) | tutti i 31 programmi di `app/cbl/` presi dal manifesto, con `app/cpy/` e `app/cpy-bms/` come percorsi di copia; per ciascuno: esito e numero di errori. I programmi con `EXEC CICS` sono attesi in errore: si registra, non si aggira |
| Grafi `COPY` e `CALL` | #2 | primo: `cobol-migration-toolkit`; riserve: `cobmix`, ProLeap COBOL parser, Koopa | grafo per i 31 programmi di `app/cbl/` |
| Copybook → tracciato (offset, lunghezza, tipo) | #3 | primo: cb2xml; riserva: JRecord | `CVACT01Y`, `CVACT03Y`, `CVTRA05Y`, `CVEXPORT` (quest'ultimo ha `COMP`, `COMP-3`, `REDEFINES`) |
| Analisi JCL (`EXEC PGM=`, DD, dataset) | #2, #7 | `mapa` | `POSTTRAN.jcl`, `INTCALC.jcl`, `CREASTMT.JCL`, `ACCTFILE.jcl` |

**Quali candidati vanno provati.** Sempre: scc, GnuCOBOL, `cobol-migration-toolkit`, cb2xml, `mapa`. Una riserva si prova **solo se** il primo candidato della stessa capacità risulta scartato o insufficiente, una alla volta nell'ordine indicato, fino a trovarne una adottabile o a esaurirle. Le riserve non toccate compaiono in `strumenti.md` come `non provato`, che è diverso da `scartato`.

`docs/legacy-map/strumenti.md` riporta per ogni strumento provato: nome, versione esatta, licenza con link alla fonte, data dell'ultimo rilascio, comando eseguito, esito (funziona / in parte / non funziona), limiti osservati, **verdetto adottato o scartato con motivo**. Uno strumento che non si installa o non gira si registra come scartato con l'errore ottenuto: è un risultato valido.

### 4. Controlli a campione (in `check.sh`, contro il sorgente e non contro lo strumento stesso)
Gli attesi si scrivono a mano in `analysis/tools/expected/`, leggendo il sorgente, e il controllo li confronta automaticamente con l'output dello strumento adottato.

- **Manifesto:** l'elenco dei percorsi coincide esattamente con `git -C $LEGACY ls-files` (stessi percorsi, nessun duplicato, nessun extra, ogni tipo tra quelli ammessi); 44 file di tipo `cobol`, di cui 31 sotto `app/cbl/`. Test negativo: un manifesto in cui si omette un file e se ne duplica un altro dello stesso tipo deve far fallire il controllo.
- **`COPY`:** per `COBIL00C`, `CBTRN02C` e `COACTUPC` si confrontano le **occorrenze** con numero di riga, non il solo insieme dei nomi (righe di commento escluse). In `COACTUPC` il copybook `CSSETATY` è incluso più volte con `REPLACING` diversi (da riga 3208): ogni occorrenza deve restare distinta, con le sue sostituzioni. Se lo strumento conserva solo i nomi, è un limite da dichiarare e il controllo sulle occorrenze fallisce: lo strumento non è adottabile da solo per questa capacità.
- **`CALL`:** `CALL 'COBDATFT'` in `CBACT01C` e `CALL 'MVSWAIT'` in `COBSWAIT`. In `strumenti.md` va dichiarato se lo strumento vede o no i trasferimenti `EXEC CICS XCTL` / `LINK`.
- **Tracciati:** lunghezza totale 300 per `CVACT01Y`, 50 per `CVACT03Y`, 350 per `CVTRA05Y`. Inoltre, tabella attesa a mano con nome, offset, lunghezza in byte, tipo e scala per: i primi sei campi elementari di `CVACT01Y` (tra cui tre importi consecutivi di uguale ampiezza, che non devono risultare scambiati) e, in `CVEXPORT`, almeno un campo `COMP`, uno `COMP-3` e una coppia di aree legate da `REDEFINES`. Per `CVEXPORT` la lunghezza totale ottenuta si confronta con `RECORDSIZE` in `app/jcl/CBEXPORT.jcl`, segnalando l'eventuale differenza senza correggerla. Le opzioni di rappresentazione usate dallo strumento (dialetto, dimensione dei binari) sono dichiarate.
- **JCL:** per `POSTTRAN.jcl` attesi a mano: programma eseguito (`CBTRN02C`, riga 23) e associazione DD → dataset per tutte le DD del passo, comprese quelle scritte su righe di continuazione e quella verso una generazione GDG.

Ogni controllo ha un test negativo che dimostra che fallisce alterando l'atteso.

### 5. Capacità obbligatorie
`strumenti.md` si chiude con una tabella "capacità → percorso utilizzabile". Ogni capacità ha uno di due stati, registrato anche in forma leggibile da macchina in `analysis/tools/capabilities.tsv`:

- `available`: c'è uno strumento adottato e i controlli a campione del punto 4 per quella capacità passano;
- `unavailable`: tutti i candidati, riserve comprese, sono stati provati e scartati. In questo caso i controlli a campione di quella capacità non si applicano; al loro posto `check.sh` verifica che per ogni candidato esista la prova del fallimento (comando ed errore salvati in `analysis/tools/out/`). In `strumenti.md` si descrive il ripiego minimo, senza implementarlo.

La valutazione riesce anche se una capacità è `unavailable`: è un risultato. Ma la PR lo scrive in evidenza nella descrizione, con l'elenco delle issue che ne dipendono (#2, #3, #7 secondo la tabella), che restano `blocked` finché il pianificatore non apre e chiude una issue di ripiego.

## Invarianti da preservare
- Nessun file sotto `legacy/` modificato. `git status --short legacy/` resta vuoto.
- Nessuna installazione sull'host oltre a Docker.

## Criteri di accettazione (verificabili)
- [ ] Da clone pulito con submodule: `./analysis/run.sh --all` termina con codice 0 usando solo Docker.
- [ ] `./analysis/run.sh --all --check` termina con codice 0 ed esegue tutti i controlli del punto 4; ciascun controllo fallisce se si altera il valore atteso (dimostrato da un test negativo incluso).
- [ ] Due esecuzioni consecutive di `./analysis/run.sh manifest` producono un file identico.
- [ ] `docs/legacy-map/strumenti.md` ha una riga per ogni candidato della tabella: per quelli provati versione, licenza, comando, esito e verdetto; per le riserve non toccate `non provato`. In fondo, la tabella delle capacità, coerente con `analysis/tools/capabilities.tsv` (verificato da `check.sh`).
- [ ] Ogni immagine ha versione fissata (tag o digest per le basi, versione esplicita per gli strumenti).
- [ ] `git diff --stat origin/main...HEAD` tocca solo `analysis/` e `docs/legacy-map/strumenti.md`.

## Strategia di rollback
Revert della PR. Nessun effetto su altro: le cartelle sono nuove.

## Limiti per l'agente
- Non scrivere un parser COBOL, JCL o di copybook. Sono ammessi solo script di colla: avvio dei container, raccolta degli output, controlli.
- Non modificare né pre-elaborare i sorgenti per farli digerire a uno strumento: se serve, descriverlo e registrare il limite.
- Non dichiarare adottato uno strumento il cui output non è stato controllato a campione.
- Le licenze si verificano alla fonte; una licenza non accertata si scrive "non accertata".
- Se un candidato non si installa dopo un tentativo ragionevole (indicativamente trenta minuti), registrarlo come scartato e proseguire.
- Gli elenchi attesi del punto 4 si scrivono leggendo il sorgente, non copiando l'output dello strumento.
