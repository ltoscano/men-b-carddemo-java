BOCCIATA

SHA `9304eef`. I due rilievi del secondo giro sono chiusi nei controesempi richiesti. Ho però riprodotto **tre nuovi falsi verdi del controllo completo**.

Timeout: 600 s per `inventory`, 1200 s per `--all --check`, 60 s per i comandi ausiliari; nessun timeout raggiunto. Script e log sono in `<cartella temporanea>`; [registro completo delle esecuzioni](file locale del Validatore; non conservato nel repository).

Nella tabella, `P` abbrevia `python3 <cartella temporanea>/mutations.py`. Per le mutazioni del grafo ho alterato **`build.py`**, prodotto gli output con quella colla e poi eseguito `inventory --check`, che rigenera tutti gli intermedi dal legacy. Le durate comprendono preparazione e controllo completo.

| Comando / caso | Esito | Durata |
|---|---|---:|
| `./analysis/run.sh inventory`, prima esecuzione | 0 | 131,60 s |
| Stesso comando, seconda esecuzione | 0; output identici | 140,46 s |
| `./analysis/run.sh inventory --check` | 0 | 156,14 s |
| `./analysis/run.sh --all --check` | 0 | 349,39 s |
| `docker run … menb-inventory-jsonschema:4.23.0 /s.json /g.json` | Schema valido | 0,89 s |
| `P round2` — generazione `-1` su DD `(+1)` | 1, errore GDG esplicito | 132,11 s |
| `P round2` — membro `DB2FREE` → `FAKE` | 1, membro errato | 130,34 s |
| `P round2` — contenitore errato di WAITSTEP | 1, contenitore errato | 117,47 s |
| `P round2` — risposta mapa non valida su TRANEXTR, livello B | 1, output non riconoscibile | 103,42 s |
| `P five` — `nodo.file` di CBSTM03B alterato | 1, confronto col manifesto | 175,15 s |
| `P five` — `occ_call.operando` alterato | 1, confronto con intermedi e atteso | 200,46 s |
| `P five` — `occ_dd.dd`: SYSOUT → FAKEOUT | 1, confronto con scheda | 149,41 s |
| `P five` — `nodo.classe`: sysout → dummy | 1, confronto con DD entranti | 137,77 s |
| `P five` — `occ_call.non_risolto` rimosso | 1, schema | 91,74 s |
| `read-manual.py` e `samples.py` — tre campioni nuovi | Confronto esatto, attributi inclusi | 0,60 + 0,02 s |
| `chain.py` — COACTUPC → CSUTLDPY → CSUTLDTC | Presente; confermato sul sorgente | 0,54 s |
| `P regression` — due DD scambiate fra passi | 1, entrambe le appartenenze errate segnalate | 94,60 s |
| `P regression` — CCUP puntata a COTRN02C | 1, programma e blocco errati | 92,48 s |
| `P extra` — esecuzione aggiuntiva falsa su ACCTFILE | **0: falso verde** | 155,11 s |
| `P extra` — COBSWAIT classificato utility | **0: falso verde** | 181,87 s |
| `P proleap` — risposta ProLeap non valida su CSUTLDPY | **0: falso verde** | 114,78 s |
| `P clean` — primo controllo dopo ripristino | 0 | 93,31 s |
| `P clean` — secondo controllo consecutivo | 0 | 124,91 s |
| `audit.py final` | Ripristino e integrità confermati | 0,56 s |

Il primo confronto manuale si era fermato per un errore nel mio atteso (`COSTM01.cpy` anziché `COSTM01.CPY`): corretto usando il manifesto, poi superato. Non è un difetto della PR.

I campioni letti dal volume coincidono con il grafo:

| Oggetto nuovo | Confronto effettuato |
|---|---|
| `TRANBKP.jcl`, con `REPROC.prc` | Job: 3 EXEC e 6 DD; procedura: 1 EXEC e 4 DD. Verificati appartenenze, righe, fonte, assenza di PARM, DSN, DISP, GDG `+1`, membro `REPROCT` e dataset simbolico |
| `CBSTM03A.CBL` | 4 COPY; 13 CALL a CBSTM03B e una a CEE3ABD, tutte con le rispettive righe e senza occorrenze aggiuntive |
| CPVD, `app/app-authorization-ims-db2-mq/csd/CRDDEMO2.csd` | DEFINE:39 → PROGRAM(COPAUS1C):40; percorso, modulo e bersaglio corretti |

Il diff completo della PR e quello `c7f30f7..HEAD` rispettano il perimetro. Tutti i file tracciati sono tornati identici all’avvio; legacy host e volume invariati. **Diff tracciato e indice vuoti**; `git status --short` mostra soltanto `?? .validazione/`, già presente all’avvio. Nessun commit o push.

| Rilievo del secondo giro | Stato |
|---|---|
| 1 — GDG, membro e contenitore non verificati | **Chiuso nei tre controesempi ripetuti:** tutti respinti dal controllo completo |
| 2 — Risposta mapa malformata assorbita dal livello B | **Chiuso:** TRANEXTR con risposta non valida viene respinto esplicitamente |

Per gli attributi derivati: non esiste un testo canonico indipendente per `descrizione`; il manifesto fornisce il percorso, senza un secondo attributo `modulo`; le schede forniscono l’etichetta EXEC, mentre prefissi e disambiguazione dei nomi sono convenzioni. Non considero un rilievo la duplicazione di queste regole.

1. **Bloccante — Un’esecuzione aggiuntiva errata può essere ignorata.**

   Ho alterato la colla aggiungendo `ACCTFILE/STEP05 → program:CBACT01C`, con file e riga 22, mantenendo l’arco corretto verso `IDCAMS`. Il sorgente contiene soltanto `EXEC PGM=IDCAMS`.

   Il grafo passa da **119 a 120 occorrenze PASSO_ESEGUE nei JCL**. Il controllo completo restituisce **0**, compresa la suite negativa: [log](file locale del Validatore; non conservato nel repository), [colla alterata](file locale del Validatore; copia delle mutazioni usata da Fable per la verifica).

   In `verify.py:258–266`, le occorrenze sono assegnate a dizionari per file/riga: quella corretta sovrascrive quella falsa. Il totale EXEC confrontato conta invece i nodi passo.

   **Falso verde: sì, dimostrato end-to-end. Mappa: sbagliata nella mutazione, con una dipendenza inesistente. Limiti esclusi: no; strumenti e sorgenti restano corretti.**

   Correzione richiesta: verificare tutte le occorrenze JCL in entrambe le direzioni, senza sovrascritture; imporre la corrispondenza univoca con ciascuna scheda EXEC e aggiungere questa prova negativa.

2. **Bloccante — Il bersaglio EXEC può avere il tipo sbagliato pur avendo il nome corretto.**

   Ho alterato la colla sostituendo `WAITSTEP/WAIT → program:COBSWAIT` con `→ utility:COBSWAIT`, aggiungendo il relativo nodo utility. Il controllo completo restituisce **0**: [log](file locale del Validatore; non conservato nel repository), [colla alterata](file locale del Validatore; copia delle mutazioni usata da Fable per la verifica).

   Esiste un valore indipendente: il manifesto classifica `app/cbl/COBSWAIT.cbl` come COBOL. `verify.py:299–303` confronta il nome, ma per `PGM` ammette indistintamente `program`, `asm` e `utility`. L’inventario alterato elenca quindi COBSWAIT tra i programmi senza arco diretto di esecuzione.

   **Falso verde: sì, dimostrato end-to-end. Mappa: sbagliata nella mutazione; perde il collegamento al programma presente. Limiti esclusi: no; la classificazione è verificabile col manifesto.**

   Correzione richiesta: confrontare il bersaglio completo, compreso il tipo determinato dalla presenza nel manifesto; aggiungere una prova negativa che conservi il nome cambiandone la categoria.

3. **Importante — Una risposta ProLeap malformata è ancora accettata sui file senza COPY.**

   Ho sostituito soltanto la risposta ProLeap di `app/cpy/CSUTLDPY.cpy` con `TRUNCATED INVALID RESPONSE`, preservando l’exit code reale. Il controllo completo restituisce **0**, con output normalizzati identici: [log](file locale del Validatore; non conservato nel repository), [wrapper alterato](file locale del Validatore; copia delle mutazioni usata da Fable per la verifica).

   `analysis/inventory/lib.sh:51–54` scarta incondizionatamente la prima riga mediante `NR>1`, senza validare l’intestazione. La risposta malformata diventa zero COPY, valore compatibile con quel sorgente.

   **Falso verde: sì, per una risposta malformata non rilevata. Mappa: nessun errore aggiuntivo osservato in questa prova. Limiti esclusi: no; non sono dati falsi ma ben formati né nuova sintassi legacy.**

   Correzione richiesta: validare intestazione e struttura della risposta ProLeap per ogni invocazione, anche quando non sono attese COPY; rifiutare esplicitamente risposte vuote o non riconoscibili.