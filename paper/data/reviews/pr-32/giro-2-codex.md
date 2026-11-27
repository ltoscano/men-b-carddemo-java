BOCCIATA

I controlli passano, ma resta un falso verde sul censimento delle strutture di composizione: CBACT04C contiene due trasferimenti di struttura intera che il nuovo rilevatore salta.

**Prove eseguite.** Tutti i comandi sotto sono stati eseguiti con timeout tramite timed.py (file locale del Validatore, non conservato). `P` indica probe.sh (file locale del Validatore, non conservato): lavora su copie isolate; per le alterazioni del censimento esegue `genera` reale, cb2xml compreso, e poi `verifica.py`. Queste prove isolate sono distinte dalle esecuzioni complete di `--check`.

| Comando/prova | Esito | Durata | Timeout |
|---|---|---:|---:|
| `./analysis/run.sh data-contract --check` | 0 | 272,41 s | 900 s |
| `./analysis/run.sh --all --check` | 0 | 483,70 s | 1200 s |
| `P frammento-accorciato` | 1: confine incompleto, 3 errori | 19,12 s | 240 s |
| `P composizione-eliminata` | 1: trailer mancante, 4 errori | 14,16 s | 240 s |
| `P intervallo-allungato` | 1: `152-161` invece di `152-160` | 19,64 s | 240 s |
| `python3 boundaries.py` | 0: confini con commento e COPY corretti | 0,03 s | 30 s |
| `copy-fragment.sh` | 1: CVACT01Y senza FILLER, 13 voci contro 14 | 5,13 s | 120 s |
| `P timestamp-eliminato` | 1: DB2-FORMAT-TS mancante, 3 errori | 36,59 s | 240 s |
| `python3 diagnose.py` | Confermate due MOVE omesse in CBACT04C | 0,12 s | 30 s |
| `P posizione-alterata` | 1: offset 33 invece di 32 | 2,88 s | 60 s |
| `P scala-alterata` | 1: scala 3 invece di 2 | 3,33 s | 60 s |
| `P segno-alterato` | 1: segno assente invece di S | 2,65 s | 60 s |
| `P chiave-allungata` | 1: chiave di 12 invece di 11 byte | 2,67 s | 60 s |
| `./analysis/run.sh data-contract --check`, ripetizione 1 | 0 | 241,77 s | 900 s |
| Stesso comando, consecutivamente | 0 | 280,01 s | 900 s |
| `volume.sh`, impronta iniziale | 0 | 1,61 s | 60 s |
| `python3 integrity.py`, verifica finale | 0 | 1,64 s | 120 s |

I test dei confini con commenti e `COPY` sono **test sintetici della funzione**, non della pipeline completa. La prova sul copybook usa invece cb2xml reale, alimentato con una copia del sorgente privata del FILLER finale. Tempi ed esiti completi (file locale del Validatore, non conservato).

Nessun falso rosso osservato nelle due esecuzioni consecutive. `git status --short --untracked-files=no` è vuoto; lo status completo contiene soltanto `?? .validazione/`, già presente all’inizio. Submodule legacy pulito. L’impronta dei 329 sorgenti nel volume è invariata e coincide con il checkout. Diff: 24 file nelle correzioni, 263 nell’intera PR, zero fuori perimetro. Nessun commit o push; nessuna rimozione di volumi o immagini.

**Stato dei rilievi del primo giro.**

| Rilievo | Stato |
|---|---|
| 1 — Frammento accorciato accettato | **Chiuso nelle prove eseguite.** La stessa alterazione, con lunghezza della relazione aggiornata e derivati rigenerati, viene respinta. Anche allungamento e copybook troncato falliscono. Nessun falso verde riprodotto. |
| 2 — Struttura di composizione eliminabile | **Caso originario corretto; rilievo generale ancora aperto con nuova evidenza.** Trailer e timestamp di CBTRN02C sono protetti. CBACT04C sfugge ancora: falso verde e contratto complessivo incompleto. |
| 3 — Estrazioni dal montaggio host | **Chiuso per lettura del codice.** `lib.sh:49–58` e `check.sh:57–59` montano e leggono il volume in sola lettura. Nessun falso verde o contratto errato osservato: nessuno dei due. |

**Verifiche manuali sul sorgente**, distinte dai test eseguiti. I percorsi `app/…` seguenti sono sotto `legacy/aws-mainframe-modernization-carddemo/`.

| Programma | Riscontro |
|---|---|
| `app/cbl/CBACT04C.cbl` | READ INTO alle righe 326, 373, 394, 416, 444; REWRITE FROM a 356 e WRITE FROM a 500 risultano censiti. Mancano invece le MOVE di struttura intera alle righe **497 e 498**. L’elenco dichiarato non è completo. |
| `app/cbl/CBSTM03A.CBL` | Rilette le WRITE FROM delle famiglie `STATEMENT-LINES` e `HTML-LINES` nelle righe 435–721, inclusa la WRITE diretta a 568. Le MOVE a 529, 560 e 676–678 trasferiscono campi elementari. Non ho trovato ulteriori trasferimenti di struttura intera mancanti entro il limite concordato. |
| `app/cbl/CBTRN03C.cbl` | Confermate le nove MOVE di strutture alle righe 295, 300, 308, 312, 320, 325, 333, 337, 371, seguite dalla WRITE a 345. Confermate anche le READ INTO a 221, 249, 485, 495, 505. Nessuna omissione aggiuntiva trovata. |

In `CBTRN02C.cbl:159`, `DB2-FORMAT-TS` è effettivamente `01 PIC X(26)`: il nuovo contratto riporta offset 0, lunghezza 26, DISPLAY, senza segno. La ridefinizione anonima alle righe 160–174 e le assegnazioni 694–703 confermano il formato dichiarato; non riapro il limite sulla composizione campo per campo.

Il trailer coincide: `REJECT-TRAN-DATA` occupa 350 byte (`CBTRN02C.cbl:177`); `VALIDATION-TRAILER` segue a 350 (`:178`). La struttura trasferita a riga 448 contiene motivo di 4 byte e descrizione di 76 (`:181–182`): quindi **350/4 e 354/76**, prima della WRITE FROM a 451.

**Rilievi nuovi o rimasti.**

1. **Bloccante — il rilevatore salta due trasferimenti interi in CBACT04C.**  
   **Falso verde: sì. Contratto incompleto: sì**, manca la struttura sorgente di composizione; non ho osservato offset errati nei contratti già presenti.

   **Evidenza:** `app/cbl/CBACT04C.cbl:150` dichiara `01 DB2-FORMAT-TS PIC X(26)`. Le righe **497 e 498** la trasferiscono interamente in `TRAN-ORIG-TS` e `TRAN-PROC-TS`; riga **500** scrive `TRAN-RECORD`. Non servono analisi del flusso dei dati né riferimenti con posizione. Questi trasferimenti sono assenti da `out/fonti/trasferimenti.tsv`, dal censimento e dalle relazioni, mentre entrambi i controlli completi restituiscono 0.

   **Causa:** `analysis/data-contract/glue/struttura.py:149` trasforma `= (` in `=(`. Il ciclo a riga **241** cerca soltanto il token esatto `=` e oltrepassa le istruzioni successive. In `out/fonti/non-coperti.tsv:37–38`, le due destinazioni vengono così attribuite al `COMPUTE` di riga 464. L’elenco dei “non coperti” **non è fedele**: assorbe trasferimenti che rientrano nel limite concordato.

   Nell’esperimento diagnostico (file locale del Validatore, non conservato), modificando soltanto una copia in memoria della tokenizzazione, emergono esattamente le due MOVE mancanti; il rilevatore originale ne restituisce zero per CBACT04C.

   **Correzione richiesta:** mantenere separati operatori e parentesi e impedire alla scansione di `COMPUTE` di consumare istruzioni successive. Aggiungere censimento, contratto e due relazioni per `CBACT04C.DB2-FORMAT-TS`, aggiornando composizioni e documentazione. Aggiungere una prova negativa che elimini questa struttura e le relazioni, rigeneri tutti i derivati e pretenda codice 1.