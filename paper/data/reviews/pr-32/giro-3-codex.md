APPROVATA CON RISERVE

SHA verificato: `353e3bc`. Resta una riserva minore sul testo di una motivazione; nessun rilievo bloccante o importante nelle prove eseguite.

`P` indica lo [script indipendente delle mutazioni](file locale del Validatore, non conservato): opera su copie isolate, rigenera dal legacy con cb2xml quando modifica il censimento e infine esegue `verifica.py`. Queste prove sono distinte dai controlli completi. [Comandi, esiti e tempi registrati](file locale del Validatore, non conservato).

| Comando/prova | Esito | Durata | Timeout |
|---|---|---:|---:|
| `./analysis/run.sh data-contract --check` | 0; 51 prove negative superate | 228,24 s | 1.000 s |
| `./analysis/run.sh --all --check` | 0; tutte le analisi superate | 555,50 s | 1.300 s |
| `P cbact04-remove` | 1; entrambe le MOVE mancanti rilevate | 47,34 s | 360 s |
| `manual-check.py`, confronto con attesi ricavati dalla lettura manuale | 0; nessuna omissione nei quattro programmi | 0,03 s | 30 s |
| `sample.py`, estrazione dei 20 casi poi riletti | 20/20 conformi | 0,03 s | 30 s |
| `exclusions.py`, estrazione dei dieci casi poi riletti | Categorie confermate; un motivo inesatto | 0,11 s | 60 s |
| `P range-short` | 1; intervallo incompleto rilevato | 19,41 s | 360 s |
| `P trailer-remove` | 1; struttura e relazioni mancanti rilevate | 24,15 s | 360 s |
| `P offset` | 1; offset 33 invece di 32 rilevato | 2,10 s | 60 s |
| `P scale` | 1; scala 3 invece di 2 rilevata | 1,92 s | 60 s |
| `data-contract --check`, ripetizione 1 | 0 | 361,83 s | 1.000 s |
| Stesso comando, consecutivamente | 0 | 387,98 s | 1.000 s |
| `integrity.py`, prima/dopo i controlli/finale | 0; impronte invariate | 1,92 / 1,75 / 1,91 s | 180 s ciascuno |
| Status finale e `git diff --check 48f491e..HEAD` | Nessuna modifica tracciata; diff senza errori | 0,20 s | 30 s |

I tempi dei comandi di estrazione e confronto non comprendono la lettura manuale.

Lo status dei file tracciati è vuoto. Lo status completo contiene soltanto `?? .validazione/`, già presente all’inizio. Submodule legacy pulito; impronte dei 329 file del manifesto invariate, coincidenti fra checkout e volume Docker. Diff: **23 file** dopo il secondo giro, **268 nell’intera PR**, nessuno fuori perimetro. Nessun commit, push, comando Docker globale o rimozione di volumi/immagini.

**Rilievo del secondo giro: chiuso.** Le MOVE di `CBACT04C.cbl:497` e `:498` compaiono nei trasferimenti e nelle relazioni; `DB2-FORMAT-TS` è censita con contratto `X(26)`, offset interno 0. Le composizioni riportano correttamente **278/26** per `TRAN-ORIG-TS` e **304/26** per `TRAN-PROC-TS`, confermati sommando i campi di `CVTRA05Y.cpy:5–17`. Eliminando struttura e due relazioni e rigenerando, la verifica restituisce 1 con sei errori, citando entrambe le MOVE. Il precedente falso verde non è riprodotto.

La lettura manuale dei quattro programmi, comprese dichiarazioni e COPY, ha dato questi risultati:

| Programma | MOVE intere verso record scritti | Differenze |
|---|---|---|
| `CBACT01C.cbl` | 289, 304 | Nessuna |
| `CBTRN03C.cbl` | 295, 300, 308, 312, 320, 325, 333, 337, 371 | Nessuna |
| `CBSTM03A.CBL` | Nessuna | Nessuna |
| `CBIMPORT.cbl` | Nessuna | Nessuna |

Rilette anche le MOVE multilinea di `CBACT01C:223–224,277–278`, `CBTRN03C:191–194` e `CBSTM03A:424–427`: sorgenti elementari o indicizzate, senza ulteriori trasferimenti interi nel perimetro concordato.

Il [campione dei non coperti](file locale del Validatore, non conservato) comprende esattamente venti voci: CBACT01C 169/237/255; CBACT04C 352/476/490; CBEXPORT 271/275/286; CBIMPORT 293/297/429; CBSTM03A 462/561/676; CBTRN02C 425/504/508/549; CBTRN03C 329. Tutte corrispondono al tipo e alla destinazione dichiarati.

Confermate le 107 esclusioni: 82 verso `IO-STATUS`, 16 verso le altre aree di stato, 4 verso `LK-M03B-RC`, 5 verso le restanti destinazioni. I [dieci casi riletti](file locale del Validatore, non conservato) coprono tutte le nove destinazioni: CBACT01C 193/419/423; CBACT02C 111; CBSTM03A 829; CBSTM03B 152; COBSWAIT 37; CSUTLDTC 97/107/122. Nessuna destinazione campionata appartiene a un record scritto. **Nessun falso rosso nelle due esecuzioni consecutive.**

**Rilievi nuovi o rimasti**

1. **Minore, non bloccante — motivazione inesatta per `WS-DATE`.**  
   `analysis/data-contract/expected/controprova-escluse.tsv:13` la descrive come campo di `WS-DATE-VALIDATION-RESULT`. Il sorgente `app/cbl/CSUTLDTC.cbl:42–52` la dichiara invece sotto **`WS-MESSAGE`**.

   **Falso verde: no**, l’esclusione resta corretta. **Contratto sbagliato o incompleto: no. Nel limite ammesso: sì**, basta leggere la dichiarazione; non occorre analizzare il flusso dei dati.

   **Correzione richiesta:** sostituire nella motivazione `WS-DATE-VALIDATION-RESULT` con `WS-MESSAGE`.