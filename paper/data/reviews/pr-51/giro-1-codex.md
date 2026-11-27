BOCCIATA

Esaminato `faf2559`. **File fuori perimetro: nessuno**: i 35 file modificati sono ammessi. `legacy/` e `analysis/data-codec/` risultano invariati.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Rigenerazione ed eseguibilità | `./analysis/run.sh data-sentinelle` | **0**; documento identico; `run.sh`, `check.sh`, `deps` eseguibili |
| Prima verifica | `./analysis/run.sh data-sentinelle --check` | **0**; 2.557 prove superate, 103 dichiarate non applicabili |
| Seconda verifica consecutiva | `./analysis/run.sh data-sentinelle --check` | **0**; stessi risultati |
| Sorgente → sentinella | Verifica inclusa nei due `--check`, più prove private | Passa sui dati presenti; rileva righe errate, dichiarazioni saltate ed errore di tipo ripetuto nel contratto e nella sentinella |
| Conteggi | Stampa di `--check` e blocchi `awk` della descrizione PR | 15 copybook, 22 coppie, 23 sentinelle, 241 attesi; conteggi coincidenti |
| Verifica generale | `./analysis/run.sh --all --check` | **0** |
| Stato e perimetro | `git status --short`; `git diff --name-only origin/main...HEAD`; stato del submodule | Nessuna modifica tracciata; rimane soltanto `?? .validazione/`, già presente all’inizio |
| CI | `gh pr checks` | **0**; `analysis-check`, `smoke`, `verify` verdi |

La [lettura manuale campo per campo](file locale del Validatore, non conservato) copre `COCOM01Y`, `CVACT01Y`, `CVTRA02Y` e tutte le sette viste di `CVEXPORT`: **130 confronti campo/vista**, con riga sorgente, nome, `PICTURE`, `USAGE`, lunghezza, intervallo e byte. Include `COMP` e `COMP-3`.

Le prove private su scambi, aree `REDEFINES`, indici `OCCURS`, dichiarazioni omesse e attesi duplicati sono state rilevate. Il compositore non legge contratti né codec; una sua regola del segno alterata produce **12 errori di decodifica**, quindi il confronto non risulta circolare. La storia Git conferma `0509f16` prima dell’adattatore `24c138a`; dopo cambiano soltanto i due valori dichiarati nel commit `91455b3`.

I carichi variabili risultano dal sorgente: **12 = 11 + 1**, **39 = 11 + 12 + 12 + 4**, in `CBACT01C.cbl:123–130`; scritture alle righe `288–290` e `303–305`. [Fonti verificate sul volume Docker](file locale del Validatore, non conservato).

1. **Bloccante — La copertura incompleta può risultare verde.**  
   In `analysis/data-sentinelle/glue/controlli.py:474–515`, le viste vengono confrontate con le righe dichiarate nell’elenco, senza pretendere una sentinella effettiva per ciascuna vista. Eliminando `EXPORT-ACCOUNT-DATA.tsv` e lasciando vuota la lista della relativa riga, `run.sh` termina con **0**, anche dopo uno scambio degli offset di `EXP-ACCT-OPEN-DATE` e `EXP-ACCT-REISSUE-DATE`, con geometria chiusa. Questa prova riguarda il verificatore positivo.

   Inoltre, eliminando `prefisso-39.tsv` **e** il suo nome dall’elenco, **rigenerazione e `--check` completi terminano entrambi con 0**: 2.547 prove superate, 102 non applicabili. Anche due file entrambi riferiti al prefisso da 12 byte passano la verifica positiva.

   **Correzione richiesta:** confrontare le viste attese con le coppie realmente coperte; verificare la copertura effettiva dei campi; pretendere per `VBR-REC` i prefissi `{12, 39}`. Aggiungere prove negative per omissioni coordinate di file ed elenco e per prefissi duplicati.  
   **Falso verde: sì. Contratto errato accettato dal verificatore positivo: dimostrato.**  
   [Prove](file locale del Validatore, non conservato), [patch dell’omissione](file locale del Validatore, non conservato), [verifica completa verde](file locale del Validatore, non conservato).

2. **Importante — Una fonte esterna di lunghezza obbligatoria può essere omessa.**  
   Il controllo in `controlli.py:542–545` pretende una fonte soltanto quando `contratti.tsv` riporta `recordsize`. Per `CUSTREC`, sostituendo la fonte con `- / nessuna fonte esterna`, **rigenerazione e `--check` terminano con 0**: 2.556 prove superate, 104 non applicabili. Il sorgente dichiara invece `RECLN 500` in `legacy/aws-mainframe-modernization-carddemo/app/cpy/CUSTREC.cpy:2`.

   **Schema del difetto:** l’omissione dell’evidenza trasforma un controllo dovuto in una prova non applicabile.  
   **Correzione richiesta:** consentire l’assenza soltanto dove effettivamente prevista e verificata; provare la rimozione delle fonti obbligatorie, comprese quelle nei commenti e negli `FD`.  
   **Falso verde: sì, sul confronto indipendente della lunghezza; contratto errato non dimostrato da questo solo caso.**  
   [Patch](file locale del Validatore, non conservato), [verifica completa verde](file locale del Validatore, non conservato).

3. **Importante — Le prove automatiche non proteggono i controlli di ricodifica.**  
   Ho disattivato, esclusivamente in una copia privata, entrambe le condizioni di `controlli.py:438` e `:444`. Il `--check` completo termina ancora con **0**, con tutte le **2.557** prove superate.

   **Schema del difetto:** nessuna prova negativa esercita le due asserzioni richieste dalla specifica; la loro eliminazione resta invisibile alla suite.  
   **Correzione richiesta:** aggiungere prove separate che raggiungano il confronto dei byte ricodificati e la ricomposizione del record, pretendendo le rispettive diagnosi. Il codec condiviso deve restare invariato.  
   **Falso verde: sì, rispetto alla rimozione dei controlli; nessun errore di ricodifica osservato nei dati presenti.**  
   [Mutazione](file locale del Validatore, non conservato), [verifica completa verde](file locale del Validatore, non conservato).

4. **Minore — Alcune “non applicabilità” sono dichiarate erroneamente.**  
   In `glue/negativi.py:389–401`, la scala di `CDEMO-PGM-CONTEXT` viene esclusa. Ho costruito una mutazione supportata dal codec: `9(1)V9(1)`, compensando un byte su `CDEMO-CUST-ID`, con metadati coerenti e totale invariato di 160 byte. Il verificatore ottiene **7.9** e **12345678**, e rifiuta correttamente entrambi. Inoltre, GnuCOBOL conferma che `PIC V9` occupa un byte e legge `.7`: l’affermazione contraria in `sentinelle.md:102` è falsa.

   In `negativi.py:565–578`, la coppia deve avere identiche `PICTURE` e `USAGE`. Nella vista `EXPORT-CARD-XREF-DATA`, però, `EXPORT-SEQUENCE-NUM` (`CVEXPORT.cpy:16`, `COMP`) ed `EXP-XREF-CUST-ID` (`:86`, `DISPLAY`) possono entrambi valere **900000004**. Il controllo attuale rileva l’uguaglianza tipizzata; la prova viene ingiustamente esclusa.

   **Correzione richiesta:** rivedere i criteri di applicabilità, aggiungere questi casi e aggiornare documento e conteggi.  
   **Falso verde sui controesempi: no**, perché il verificatore li rifiuta; il catalogo delle prove è incompleto. [Evidenze](file locale del Validatore, non conservato).

5. **Minore — La ricodifica del record variabile confronta anche il riempimento.**  
   `controlli.py:432` limita il valore al prefisso, ma `:438` confronta tutti gli **80 byte**, prima del taglio a `:441`. Alterando soltanto il byte 80 del risultato ricodificato, mantenendo identici entrambi i prefissi, ottengo due errori `[ricodifica]`. La specifica esclude quei byte dall’atteso.

   **Schema del difetto:** il limite del prefisso viene applicato dopo un confronto che ha già incluso il riempimento.  
   **Correzione richiesta:** limitare anche quel confronto ai byte effettivi e aggiungere una prova sui byte esterni al prefisso.  
   **Falso verde: no; possibile falso rosso e difformità dalla specifica.** [Prova](file locale del Validatore, non conservato).

6. **Minore — La prova `documento-alterato` considera riuscito anche un errore operativo di `diff`.**  
   In `analysis/data-sentinelle/check.sh:76–79`, qualsiasi uscita diversa da zero produce “ok”. Isolando lo stesso blocco e fornendo un file inesistente al vero `diff`, l’uscita è **2**, ma viene stampata la diagnosi di differenza rilevata.

   **Schema del difetto:** esito atteso della prova negativa ed errore del comando vengono confusi.  
   **Correzione richiesta:** accettare esclusivamente l’uscita **1**; trattare **2** e gli altri codici come errori operativi.  
   **Falso verde: sì, del solo test negativo; contratto errato non dimostrato da questo caso.** [Evidenza](file locale del Validatore, non conservato).

Risorse Docker `menb-val51-` rimosse. Nessun commit; file tracciati invariati.