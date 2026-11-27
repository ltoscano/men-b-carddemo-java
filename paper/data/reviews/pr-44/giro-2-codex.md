APPROVATA

Validato lo SHA `644d53b`. Letto integralmente il diff di correzione, coincidente con `git diff 96e384c HEAD -- oracle/`.

I comandi `/val/...` sono eseguiti nel container, montando `<cartella temporanea>` su `/val`.

| Rilievo | Stato | Comando | Esito |
|---|---|---|---|
| 1. Copertura e metadati della tabella | **Chiuso** | `sh /val/uscite.sh` — [script](file locale del Validatore, non conservato), [preparazione](file locale del Validatore, non conservato) | Tutti **1**: riga FICO omessa; una sola riga; 117 duplicati; lunghezza `75junk`; verifiche FICO eliminate e output alterati a `999`. Anche tabella strutturalmente valida con FICO `624` anziché `623`: **1**, differenza rilevata. Copia integra: **0**. |
| 2. Byte dopo `0x01` | **Chiuso** | `sh /val/uscite.sh` | `0x01GARBAGE` aggiunto separatamente a STMTFILE e HTMLFILE: entrambi **1**, separatore e dimensione errati. Separatore interno: **1**. |
| 3. Impronta con file illeggibile | **Chiuso** | `bash <cartella temporanea>/impronta.sh` — [script](file locale del Validatore, non conservato) | Con **due contenuti diversi**, resi illeggibili: `artifacts_hash` e `build_stamp` restituiscono sempre **1**, senza impronta su stdout. Respinti anche artefatto `bin/` e input illeggibili. |

La nuova `struttura` è un catalogo scritto a mano: **non legge né ricopia a runtime la tabella verificata**. Ho confrontato le sue formule con dichiarazioni e scritture del sorgente e con lo scenario: `2 0 2` movimenti, 61 record testo e 236 HTML; copertura di **36 campi dinamici per output**, senza omissioni attuali. Il confronto dei valori resta indipendente dalla verifica della struttura: il controesempio `623 → 624` viene rilevato.

**Un campo assente sia dalla tabella sia da `struttura` sfuggirebbe al controllo manuale.** Su copie, eliminando anche gli slot FICO e alterando i valori a `999`, questo controllo restituisce **0**. È il limite del catalogo statico, la cui completezza richiede revisione sul sorgente. Non ho trovato tale omissione nella versione attuale. Una modifica in una posizione non coperta passa anch’essa il controllo manuale, ma il confronto integrale con gli attesi invariati restituisce **1**.

**Rilievi nuovi: nessuno.**

| Verifica richiesta | Esito |
|---|---|
| `git diff --name-only origin/main...HEAD` | 35 file, tutti nel perimetro ammesso; considerate correttamente le modifiche provenienti dal merge di main. |
| Confronto con `96e384c` di `oracle/adattamenti/expected`, `oracle/adattamenti/scenario`, `oracle/avvio/expected` | Nessuna differenza. |
| `./oracle/run.sh --all --check`, eseguito **una volta** | **0**, tutti i passi completati — [log](file locale del Validatore, non conservato). |
| Stato finale | Nessuna modifica tracciata; resta soltanto `.validazione/`, già presente. Legacy pulito, fissato a `59cc6c2`. |

Container delle prove con prefisso `menb-val44b-`, rimossi automaticamente; nessuna risorsa Docker con quel prefisso residua. Nessuna immagine o volume condiviso rimosso. Nessuna correzione e nessun commit.