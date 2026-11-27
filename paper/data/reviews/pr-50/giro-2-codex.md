BOCCIATA

| Rilievo | Stato | Comando/prova | Esito |
|---|---|---|---|
| 1. Estrattore duplica, costruttore deduplica | **Chiuso** | `./analysis/run.sh inventory-cics --check`, mutazione esatta `COTRN02C:156` | Mutazione respinta con exit 1: **2 record nel TSV, 1 occorrenza nel grafo**. |
| 2. Catene di `REDEFINES` | **Chiuso** | `python -B /repo/.validazione/val50b/probe_resolve.py`, in container | Due e tre alias e catena a livello 05: `non_risolto`, motivo `modificato`, in entrambe le implementazioni. Catena intatta: `costante`. |
| 3. `ASSIGN PROGRAM(X)` seguito da `LINK` | **Chiuso** | Stessa prova Python e mutazioni integrate in `--check` | `X` resta non risolto in colla e verifica; la falsa costante viene respinta. |
| 4. Risposte degli strumenti | **Non chiuso** | `bash .validazione/val50b/probe_responses.sh`; `probe_actual_prefix.sh`; `probe_schema_tail.sh` | **102 iniezioni** elementari producono rosso nei punti di consumo, anche con l’arco errato. Restano accettate risposte malformate o incomplete descritte sotto. L’arco aggiunto a `COPAUA0C:477`, con verificatore autentico, produce due difetti. |
| 5. Motivo delle prove negative | **Chiuso** | Log di `./analysis/run.sh inventory-cics --check` | Tutte le **125 prove negative** riportano causa o diagnostica. |

1. **Importante — La nuova validazione delle risposte controlla solo parte del protocollo.**  
   In `analysis/inventory-cics/check.sh:28–42`, entrambi i controlli accettano righe estranee prima della conclusione positiva. Per esempio, con exit 0:

   ```text
   RISPOSTA MALFORMATA
   schema valido
   ```

   Ho aggiunto quella riga agli output **autentici** di verifica e schema: tutti e quattro i punti positivi restano verdi.

   Inoltre, `sstate` non confronta il numero dichiarato di errori con le diagnostiche ricevute. Ho prodotto una risposta autentica con **cinque errori**, eliminato una diagnostica e conservato la conclusione `5 errori di schema`: la sezione 14 completa termina ancora con **exit 0**, dichiarando tutti i controlli superati. Riproduzione: `bash .validazione/val50b/probe_schema_tail.sh`.

   **Correzione richiesta:** validare tutte le righe del protocollo; per lo schema richiedere esattamente `min(N, 20)` diagnostiche, rispettando il limite dello strumento, con `N ≥ 1`; aggiungere queste prove alle mutazioni automatiche.  
   **Falso verde: sì**, sulla validità della risposta e sulla prova negativa. **Mappa sbagliata: non dimostrata da questo controesempio.**

Ho letto per intero il diff di correzione. Le **28 coppie ammesse** corrispondono ad argomenti IBM `name`/`filename`; `data-area` può invece ricevere dati, come in `ASSIGN PROGRAM`. Riscontro nelle sintassi della [IBM Application Programming Reference](https://publibfp.boulder.ibm.com/epubs/pdf/dfhp400.pdf).

**`DATASET` come sinonimo di `FILE` è corretto.** IBM scrive: «FILE is a synonym for the obsolete DATASET option», nella sezione *File control*, pagina 68 di [CICS Family — API Structure](https://public.dhe.ibm.com/systems/power/docs/systemi/v5r4/hr_HR/sc331007.pdf#page=84). Questo conferma l’equivalenza usata dai **47 comandi con `DATASET` sui 58 comandi sui file**.

Sul mio caso aggiuntivo con gruppi annidati, alias subordinati e livelli 88/66, le due chiusure producono **gli stessi insiemi di nomi collegati**. GnuCOBOL conferma anche l’effetto: `K-PGM` passa da `FIXTGT` a `CHANGED`; il campo della catena intatta rimane `FIXTGT`.

Il diff della PR contiene soltanto i **36 file ammessi**. `analysis/inventory/` e `docs/legacy-map/graph.json` sono invariati rispetto alla base e al primo giro. `graph-cics.json` è identico a `22f1a9d`: stesso blob `5aaef2caf5ab667ca1825c9a999a2e31be4b9de3`.

Eseguiti una volta ciascuno:

- `./analysis/run.sh inventory-cics --check` → **exit 0**.
- `./analysis/run.sh --all --check` → **exit 0**.

Verifica finale con `gh` sullo SHA **`c15a1df863fa7dd212c9ce3b2cdee85c23a81f17`**: tutti e sei i run di `analysis-check`, `verify` e `smoke` sono **SUCCESS** nella [PR #50](https://github.com/ltoscano/men-b-carddemo-java/pull/50/checks).

Rimosse **10 immagini e 2 volumi** delle prove; nessun residuo Docker `menb-val50b-`. Nessuna modifica tracciata né commit; rimane soltanto `?? .validazione/`, già presente inizialmente.