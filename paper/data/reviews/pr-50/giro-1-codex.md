**BOCCIATA**

Perimetro: nessun file fuori ambito. `legacy/`, `analysis/inventory/` e `docs/legacy-map/graph.json` sono invariati.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Rigenerazione | `./analysis/run.sh inventory-cics` | Exit 0; 240 blocchi; output identici ai versionati |
| Primo controllo | `./analysis/run.sh inventory-cics --check` | Exit 0, 458 s; 83 prove negative riportate |
| Secondo controllo consecutivo | `./analysis/run.sh inventory-cics --check` | Exit 0, 335 s; 83 prove negative riportate |
| Tutte le analisi | `./analysis/run.sh --all --check` | Exit 0, 786 s |
| Eseguibili | Controllo iniziale di `check.sh` | `run.sh`, `check.sh`, `deps` e `crosscheck.sh` presenti ed eseguibili |
| Stato finale | `git status --short`; stato del submodule | Solo `?? .validazione/`, già presente all’inizio; nessuna modifica tracciata |
| Perimetro Git | `git diff --name-only origin/main...HEAD` | Solo file ammessi |
| CI | `gh pr checks` | `analysis-check`, `smoke` e `verify` verdi sullo SHA `22f1a9d` |

Il conteggio indipendente trova **240 blocchi in 25 programmi**, su tutti i **106 sorgenti** del manifesto, senza blocchi nei copybook. Nessuna differenza per file, posizione o per ciascuno dei 26 comandi. Ho confrontato anche opzioni ordinate e operandi di tutti i blocchi, e ricostruito indipendentemente i 173 archi. AJV 8.17.1 valida schema e grafo senza errori. [Riscontro completo](file locale del Validatore, non conservato), [opzioni e archi](file locale del Validatore, non conservato).

La lettura blocco per blocco comprende `COTRN02C` (11 blocchi), `COBIL00C` (13), `COUSR02C` (6), `COPAUA0C` (12), oltre a `COPAUS0C` e `COPAUS1C`. Per esempio, i `READ UPDATE` sono effettivamente presenti in `app/cbl/COBIL00C.cbl:345` e `app/cbl/COUSR02C.cbl:322`; il `READ` di `app/cbl/COTRN02C.cbl:578` non ha `UPDATE`. Questi percorsi sono relativi a `legacy/aws-mainframe-modernization-carddemo/`.

Ho riscontrato tutte le 103 `VALUE` citate, relative a 68 dati distinti, e cercato modifiche dirette, attraverso gruppi, alias e passaggi a chiamate. Non ho individuato una falsa costante nella mappa attuale, né un non risolto che avrebbe dovuto essere risolto. I controesempi dei rilievi 2 e 3 sono fixture indipendenti. [Riferimenti file/riga delle costanti](file locale del Validatore, non conservato).

La prova ProLeap senza recupero restituisce rispettivamente 2/2/6 blocchi nei tre programmi IMS; con recupero, 12/10/8. Confermati quindi i 20 blocchi recuperati, senza perdite o aggiunte rispetto al sorgente. I primi errori corrispondono agli `EXEC DLI` di `COPAUA0C.cbl:293`, `COPAUS0C.cbl:461` e `COPAUS1C.cbl:439`; errori e riprese sono dichiarati.

Gli attesi precedono l’estrattore: commit `626f6ae`, seguito da `c0ff93a`. Nessuna modifica successiva agli attesi o ai fixture. Tutte le mutazioni richieste della colla, dopo rigenerazione, sono state respinte da `--check`, comprese entrambe le varianti di tipo errato del nodo. Restano però questi difetti ulteriori.

1. **Bloccante — L’estrazione non viene confrontata direttamente con sorgente e occorrenze.**  
   **Schema del difetto:** una trasformazione successiva può nascondere una corruzione dell’output intermedio.

   `verify.py:28` non riceve `blocchi.tsv`: confronta grafo, sorgente e conteggio awk. Ho duplicato nell’estrazione il blocco `COTRN02C:156` e fatto deduplicare i record a `build.py`. Risultato: **241 record di blocco nel TSV, 240 occorrenze nel grafo**, `run.sh` e l’intero `--check` entrambi con **exit 0**, comprese tutte le 83 prove negative. [Patch della prova](file locale del Validatore, non conservato), [log](file locale del Validatore, non conservato).

   **Correzione richiesta:** confrontare direttamente i multinsiemi di estrazione, occorrenze e riscontro sul sorgente, includendo posizione, comando, opzioni e operandi; aggiungere una prova in cui il costruttore assorbe il difetto dell’estrattore.  
   **Falso verde: sì. Mappa sbagliata: no nel controesempio; l’estrazione accettata è sbagliata.**

2. **Bloccante — Le catene di `REDEFINES` possono produrre costanti false.**  
   **Schema del difetto:** la relazione tra aree sovrapposte viene espansa per un solo salto.

   Il problema è in `glue/resolve.py:271` e nella corrispondente implementazione di `glue/verify.py:438`. Nel [fixture](file locale del Validatore, non conservato), `ALIAS-AREA` ridefinisce `BASE-AREA`, `ALIAS-TWO` ridefinisce `ALIAS-AREA`, e una `MOVE` modifica un campo del secondo alias. Entrambe le implementazioni ignorano questa scrittura e classificano `WS-PGM` come costante `FIXTGT`.

   La catena di estrazione, costruzione, schema e verifica accetta l’arco sbagliato. L’esecuzione con `cobc -std=ibm` mostra invece `BEFORE=FIXTGT` e `AFTER=CHANGED`. [Prova eseguibile](file locale del Validatore, non conservato). La forma è ammessa dalla [documentazione IBM](https://www.ibm.com/docs/en/cobol-aix/5.1.0?topic=entry-redefines-clause).

   **Correzione richiesta:** calcolare la chiusura transitiva delle sovrapposizioni, inclusi gruppi e subordinati, in colla e verifica; aggiungere attesi e prove negative per catene multiple. L’affermazione «Non produce mai una costante falsa» in `inventario-cics.md:475` è attualmente smentita.  
   **Falso verde: sì. Mappa sbagliata: sì.**

3. **Bloccante — La sola lettura degli operandi CICS viene dedotta dal nome dell’opzione, ignorando il comando.**  
   **Schema del difetto:** una stessa opzione può essere ingresso oppure destinazione di una scrittura.

   `resolve.py:349` e `verify.py:478` esentano `PROGRAM(...)` dalle modifiche indipendentemente dal comando. Il [fixture](file locale del Validatore, non conservato) contiene:

   ```cobol
   01 WS-PGM PIC X(8) VALUE 'FIXTGT'.
       EXEC CICS ASSIGN PROGRAM(WS-PGM) END-EXEC.
       EXEC CICS LINK PROGRAM(WS-PGM) END-EXEC.
   ```

   Estrazione, costruzione e verifica terminano con 0 e conservano l’arco a `FIXTGT`. Tuttavia `ASSIGN PROGRAM` **scrive** il nome del programma corrente nel campo, come specificato da [IBM](https://www.ibm.com/docs/en/cics-ts/6.x?topic=summary-assign). Il dato deve quindi restare non risolto secondo la specifica.

   **Correzione richiesta:** riconoscere come lettura soltanto coppie comando/opzione sicuramente di ingresso; trattare conservativamente le altre come possibili modifiche. Aggiungere fixture e prova negativa specifici.  
   **Falso verde: sì. Mappa sbagliata: sì.**

4. **Bloccante — Alcune risposte degli strumenti vengono accettate senza validazione.**  
   **Schema del difetto:** exit 0 viene equiparato a verifica conclusa.

   In `check.sh:63` e `:71` manca il controllo della risposta conclusiva di `verify.py`; a `:70` manca quello della risposta del validatore di schema delle fixture, presente invece per il grafo principale a `:51`.

   Ho simulato risposte **vuote con exit 0**: l’intero controllo resta verde. Ho poi aggiunto un arco `PROGRAM → program:COMEN01C` al `READ` di `COPAUA0C:477`: con la risposta vuota del verificatore, **174 archi vengono accettati e `--check` termina con 0**. Senza l’iniezione, il verificatore rileva due errori. [Log del falso verde](file locale del Validatore, non conservato), [riscontro senza iniezione](file locale del Validatore, non conservato).

   **Correzione richiesta:** validare risposta completa, formato e conclusione coerente con l’exit code a ogni invocazione, comprese fixture e prove negative; provare risposte vuote, malformate e troncate in ciascun punto.  
   **Falso verde: sì. Mappa sbagliata: sì, dimostrata sulla mutazione del legacy attuale.**

5. **Minore — Non tutte le prove negative riportano il motivo nel log.**  
   **Schema del difetto:** il motivo viene controllato internamente ma scartato nella rendicontazione.

   Per esempio, `check.sh:146` e `:237` stampano solo nome ed exit code. Il log contiene `ok: arco atteso di COSGN00C (exit 1)`, senza la diagnostica del confronto fallito. Il criterio richiede nome **e motivo** per ogni prova.

   **Correzione richiesta:** stampare anche la diagnostica effettivamente verificata, uniformemente per tutte le prove.  
   **Falso verde: no per questo rilievo. Mappa sbagliata: no.**

Nessuna correzione o commit effettuato. Copie mutate eliminate; risorse Docker `menb-val50-` rimosse, senza risorse residue con quel prefisso. [Esiti finali](file locale del Validatore, non conservato), [pulizia](file locale del Validatore, non conservato).