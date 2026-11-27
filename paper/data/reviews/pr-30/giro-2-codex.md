**BOCCIATA**

Ho riprodotto due falsi verdi del comando completo: una generazione GDG sbagliata prodotta dalla colla e una risposta mapa malformata accettata senza errore.

Durate wall-clock; timeout di 600 s per `inventory`, 1200 s per `--all --check`, 60 s per le prove mirate. Nessun timeout raggiunto. Script, argomenti completi e log sono nel registro delle prove (file locale del Validatore, non conservato); sotto `R=/tmp/val2-review`.

| Prova eseguita / comando | Esito | Durata |
|---|---|---:|
| `./analysis/run.sh inventory`, prima esecuzione | Exit 0 | 127,00 s |
| Stesso comando, seconda esecuzione | Exit 0; tutti i TSV, grafo e inventario identici | 122,07 s |
| `./analysis/run.sh inventory --check` | Exit 0 | 177,90 s |
| `./analysis/run.sh --all --check` | Exit 0 | 333,12 s |
| `docker run … menb-inventory-jsonschema:4.23.0 /s.json /g.json` | Schema valido | 1,12 s |
| `python3 "$R/call-audit.py"` | 63 CALL letterali e 1 in variabile; confronto esatto col grafo | 0,52 s |
| `bash "$R/e2e-build.sh" copy` | Rigenera la COPY sbagliata; controllo completo **exit 1**, come richiesto | 124,81 / 125,21 s |
| `bash "$R/run-graph-mutations.sh"`: DD scambiate | Verifica diretta exit 1 | 1,24 s¹ |
| Stesso script: transazione verso altro blocco DEFINE | Verifica diretta exit 1 | 1,53 s¹ |
| Stesso script: dataset rinominato | Verifica diretta exit 1 | 1,42 s¹ |
| Stesso script: PARM alterato | Verifica diretta exit 1 | 1,60 s¹ |
| Stesso script: passo attribuito ad altro job tramite arco | Verifica diretta exit 1 | 1,43 s¹ |
| Stesso script: generazione GDG, membro, metadato `contenitore` alterati | **Tutte accettate**, anche dallo schema | 1,10 / 1,61 / 1,55 s¹ |
| `bash "$R/e2e-build.sh" gdg` | Rigenera il GDG sbagliato; controllo completo **exit 0** | 114,06 / 153,59 s |
| `bash "$R/test-fixtures.sh"` | Fixture mie superate | 0,90 s |
| `python3 "$R/samples.py"` | Tre nuovi campioni coincidenti | 0,03 s |
| `inventory --check` con ProLeap che termina 23 | Exit 1, `ProLeap fallito` | 9,42 s |
| `bash "$R/malformed-e2e.sh"` | Risposta mapa corrotta; controllo completo **exit 0** | 136,06 s |
| `python3 "$R/integrity.py"` finale | Ripristino e integrità confermati | 0,24 s |

¹ Durata della verifica. Prima di ogni mutazione il grafo è stato ricostruito separatamente con `build.py`, usando gli intermedi appena rigenerati nei controlli iniziali. Non ho rieseguito gli strumenti per ciascuna di queste mutazioni; COPY e GDG sono invece provati end-to-end.

Le fixture dell’Esecutore sono state lette e rieseguite dai controlli completi. Le mie aggiungono operandi a capo con commento interposto, false EXEC/DD dentro `DD DATA`, DEFINE e PROGRAM commentati nel CSD, testo dopo `*>` e dentro letterali COBOL. Nessun falso rosso osservato nei casi provati; il rifiuto esplicito del formato senza terminatore è ammesso.

| Rilievo del primo giro | Stato al secondo giro |
|---|---|
| **1 — CALL nei copybook omessa** | **Chiuso.** Esiste `COACTUPC:4232 → CSUTLDPY → CSUTLDTC:293`. Conteggio autonomo: 62 CALL letterali nei programmi, una letterale e una in variabile nei copybook, tutte rappresentate. Nessun’altra omissione trovata. |
| **2 — Collegamenti errati accettati** | **Parzialmente risolto.** La COPY alterata e le cinque mutazioni sopra sono rifiutate. Restano attributi semanticamente errati accettati: rilievo 1 sotto. |
| **3 — Conteggio delle continuazioni** | **Chiuso nelle prove eseguite.** Python, awk e localizzatore concordano sugli operandi a capo. |
| **4 — In-stream e commenti** | **Chiuso nelle prove eseguite.** Fixture dell’Esecutore e mie danno gli attesi. |
| **5 — Affermazioni dell’inventario** | **Chiuso.** La tabella ora riguarda l’assenza di archi diretti; le cinque menzioni JCL contestate sono riportate correttamente. Una CALL in variabile e otto nomi COPY non risolti sono corretti. |

Nei 62 copybook non ho trovato COPY attive annidate. L’altra categoria presente è `EXEC SQL` in `CSDB2RPY`, già esclusa dal perimetro dichiarato. Il rilievo 6 resta chiuso.

I tre oggetti nuovi sono stati ricavati dal sorgente e confrontati con attesi miei:

| Oggetto | Dipendenze verificate | Confronto |
|---|---|---|
| `PAUDBLOD.CBL` | COPY IMSFUNCS:142, CIPAUSMY:149, CIPAUDTY:153, PAUTBPCB:161; CALL CBLTDLI:244,296,321 | Esatto |
| `POSTTRAN.jcl` | STEP15:23 → CBTRN02C, senza PARM; tutte le 9 DD, incluso DALYREJS(+1):34 | Esatto |
| CDRA, `app/app-vsam-mq/csd/CRDDEMOM.csd` | DEFINE TRANSACTION:17 → PROGRAM(COACCT01):18, stesso blocco | Esatto |

1. **Bloccante — Residuo del rilievo 2: attributi del grafo non verificati.**  
   [verify.py:269](analysis/inventory/glue/verify.py:269) elimina il suffisso del dataset; i confronti a riga 332 controllano bersaglio e DSN/DISP, ma non `generazione`, `gdg` e `membro`. Analogamente, a riga 297 si controlla l’arco di appartenenza senza confrontare il metadato `contenitore`.

   `COMBTRAN.jcl:37` dichiara `TRANSACT.COMBINED(+1)`. Alterando **build.py** affinché scriva `generazione: "-1"` sulla SORTOUT, il successivo `inventory --check` passa integralmente: log (file locale del Validatore, non conservato), grafo errato (file locale del Validatore, non conservato). Anche `membro: "FAKE"` al posto di `DB2FREE` (`CREADB21.jcl:46`) e il contenitore errato di WAITSTEP passano la verifica diretta.

   **Falso verde: sì, dimostrato end-to-end per il GDG. Mappa: sbagliata nelle mutazioni; nessun errore attribuito qui al grafo originale.**  
   Correzione richiesta: confrontare questi attributi per tutte le occorrenze con i valori ricavabili dagli intermedi, verificare la coerenza del contenitore e aggiungere prove negative fuori dai campioni manuali.

2. **Importante — Nuovo rilievo: risposta mapa malformata assorbita dal livello B.**  
   [normalize.py:39](analysis/inventory/glue/normalize.py:39) accetta record sconosciuti senza richiedere una struttura riconoscibile; a riga 60 scrive TSV vuoti e restituisce successo.

   Ho sostituito soltanto il CSV di `TRANEXTR.jcl` con `TRUNCATED INVALID RESPONSE`, preservando l’exit code reale. Il normale output contiene record FILE e JOB. Il controllo completo rimane verde perché il file resta nel livello B atteso: script della prova (file locale del Validatore, non conservato), log (file locale del Validatore, non conservato).

   **Falso verde: sì, per una risposta malformata non rilevata. Mappa: nessun nuovo errore osservato nell’esperimento, grazie al ripiego.**  
   Correzione richiesta: validare struttura e record dell’output mapa per ogni invocazione e rifiutare risposte corrotte anche per file già al livello B. Non richiede gestire nuove sintassi JCL né verificare dati falsi ma ben formati.

Ho letto specifica, primo giro, risposta e diff; le prove eseguite sono indicate sopra. Ripristino finale completo: output identici agli iniziali, 330 file legacy con SHA-256 invariati, indice e diff tracciato vuoti. `git status --short` mostra soltanto `?? .validazione/`, presente all’avvio. Nessun commit o push.