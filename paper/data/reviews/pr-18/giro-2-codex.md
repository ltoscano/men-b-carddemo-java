BOCCIATA

Le cinque mutazioni del primo giro ora vengono rilevate. Resta però non soddisfatta la capacità completa dei conteggi: `--check` accetta esplicitamente ripartizioni codice/commenti smentite dai campioni manuali, mantenendo `conteggi=available`. Ho inoltre trovato due falsi verdi nei metadati dei verdetti.

Ho verificato `HEAD=4c3396a`; rispetto al ramo prima delle correzioni (`094e184`) è presente un solo commit nuovo.

Tutte le prove sotto sono state **eseguite da me**. `C` indica `./analysis/run.sh --all --check`. Timeout: 1.500 s per `--all`, 600 s per ciascun `C`. Ogni mutazione è stata ripristinata prima della successiva. Ho usato le cache Docker presenti.

| Prova / mutazione | Comando | Esito osservato | Durata |
|---|---|---|---:|
| Rigenerazione completa | `./analysis/run.sh --all` | 0 | 39,373 s |
| Controllo iniziale | `C` | 0 | 53,051 s |
| scc: `Code/Comments/Blanks` di `app/cbl` azzerati in `dirs.csv` | `C` | **1**, somme incoerenti rilevate | 2,138 s |
| cb2xml: `ACCT-CURR-BAL` rinominato nell’XML, TSV invariato | `C` | **1**, rinormalizzazione diversa | 14,082 s |
| cmt: `MVSWAIT` sostituito nel JSON, TSV invariato | `C` | **1**, rinormalizzazione diversa | 12,086 s |
| JCL: `POSTTRAN/STEP15`, `PGM → PROC` | `C` | **1**, tipo errato rilevato | 3,387 s |
| GnuCOBOL: errori di `CBSTM03A → 9999` | `C` | **1**, confronto con i 39 errori nel log | 2,383 s |
| Nuova: rimossa un’occorrenza COPY di `CBACT04C` da ProLeap | `C` | **1**, 4 occorrenze contro 5 attese | 2,561 s |
| Nuova: offset di `CVACT03Y.XREF-CARD-NUM` da 0 a 1, modificando coerentemente XML e TSV | `C` | **1**, differenza dalla riesecuzione | 52,926 s |
| Nuova: rimossa `INTCALC/STEP15/SYSPRINT` da mapa | `C` | **1**, differenza dalla riesecuzione | 51,063 s |
| Nuova: cb2xml da “adottato” a “scartato” in `strumenti.md` | `C` | **1**, incoerenza con capacità disponibile | 53,391 s |
| Nuova: digest della base cb2xml sostituito con 64 zeri | `C` | **1**, fallisce la riesecuzione cb2xml | 49,367 s |
| Nuova: `out/scc/verdetto-scc.txt`, `pass → fail` | `C` | **0**, falso verde sui metadati | 55,067 s |
| Nuova: cobmix da “scartato” ad “adottato” in `strumenti.md` | `C` | **0**, falso verde documentale | 54,269 s |
| Controllo senza mutazioni, consecutivo 1 | `C` | 0 | 51,888 s |
| Controllo senza mutazioni, consecutivo 2 | `C` | 0 | 54,579 s |
| Verifica aritmetica delle annotazioni manuali sui sei campioni | `python3 .validazione/conta_manual.py` | 0 | 0,019 s |
| Perimetro, stato Git, hash legacy e container residui | `python3 .validazione/finale.py` | 0 | 0,369 s |

Il digest alterato viene intercettato perché Docker non riesce a costruire l’immagine durante la riesecuzione; il controllo statico delle versioni non ne certifica la validità.

Dopo la rigenerazione e dopo tutti i ripristini, nessuna differenza versionata: `git status --short` mostra soltanto `.validazione/`, già non tracciata all’inizio. `git status --short legacy/` è vuoto; anche gli hash di tutti i file sotto `legacy/` sono invariati.

Lo stato dei sei rilievi precedenti è:

| # | Rilievo del primo giro | Stato |
|---|---|---|
| 1 | Conteggi codice/commenti/vuote e copertura scc | **Non chiuso**: il falso verde delle somme è corretto; resta l’adozione della capacità nonostante campioni semanticamente errati |
| 2 | Incoerenza fra grezzo e TSV | **Chiuso** |
| 3 | Tipo del passo JCL ignorato | **Chiuso** |
| 4 | Numero degli errori di compilazione non verificato | **Chiuso** |
| 5 | Negativo del manifesto con tipi differenti | **Chiuso**: la prova inclusa ora omette e duplica due copybook ed è stata eseguita |
| 6 | Affermazione assoluta sull’impossibilità dell’analisi statica | **Chiuso**: il testo limita l’affermazione agli strumenti provati e distingue le destinazioni possibili dalla scelta durante l’esecuzione |

Ho letto integralmente i sei sorgenti dei campioni scc, annotando commenti e righe vuote per numero di riga. Questi sono i miei conteggi, indipendenti dall’output scc:

| Sorgente sotto `app/` | Righe | Codice | Commenti | Vuote | scc: codice/commenti/vuote |
|---|---:|---:|---:|---:|---|
| `cpy/CVACT03Y.cpy` | 11 | 5 | 6 | 0 | 5 / 6 / 0 |
| `cpy/CVTRA05Y.cpy` | 21 | 15 | 6 | 0 | 15 / 6 / 0 |
| `cbl/COBSWAIT.cbl` | 41 | 13 | 22 | 6 | 13 / 22 / 6 |
| `jcl/POSTTRAN.jcl` | 45 | 22 | 23 | 0 | 22 / 23 / 0 |
| `cbl/CBACT01C.cbl` | 430 | 358 | 51 | 21 | **379 / 30 / 21** |
| `asm/MVSWAIT.asm` | 30 | 14 | 16 | 0 | **30 / 0 / 0** |

Per esempio, `CVACT03Y` ha commenti alle righe 1–3 e 9–11; `COBSWAIT` alle righe 1–21 e 29, con sei righe vuote; `MVSWAIT` ha 16 commenti iniziali e 14 righe di codice. In `CBACT01C`, le prime 21 righe sono commenti COBOL con numeri di sequenza.

La dichiarazione delle divergenze è **onesta e confermata dal sorgente**. Tuttavia, registrare come atteso l’errore dello strumento non dimostra la correttezza della misura richiesta. Il tempo della lettura manuale non è stato misurato; 0,019 s riguarda soltanto il controllo automatico delle mie annotazioni.

I rilievi nuovi o rimasti sono:

1. **Importante — `conteggi=available` certifica una capacità che fallisce due campioni indipendenti.**  
   Evidenza: `analysis/tools/expected/scc_files.tsv:10` e `:11` contengono sia i conteggi manuali corretti sia quelli errati di scc. In [compare.py:126](analysis/tools/glue/compare.py:126), questi ultimi sostituiscono gli attesi manuali. `capabilities.tsv:5` e `strumenti.md:101` mantengono la capacità disponibile. La specifica richiede il confronto contro il sorgente, non soltanto la stabilità dell’errore noto.  
   **Correzione richiesta:** ottenere conteggi corretti con strumenti esistenti oppure registrare la capacità completa come `unavailable`, conservando l’eventuale uso limitato di scc per file e righe. Una capacità ristretta richiede una modifica esplicita della specifica.

2. **Minore — l’adozione documentale di un candidato insufficiente può restare verde.**  
   Ho cambiato soltanto il verdetto di cobmix in `strumenti.md:58` da “scartato” ad “adottato”: codice 0, mentre il controllo COPY continua a dimostrarne l’insufficienza. [check_docs.py:108](analysis/tools/glue/check_docs.py:108) verifica l’adozione solo degli strumenti indicati nelle capacità disponibili.  
   **Correzione richiesta:** verificare anche i verdetti degli altri candidati rispetto alle prove. La specifica richiede adozioni motivate; non prescrive esplicitamente questo controllo automatico inverso. Lo considero una lacuna di robustezza aggiuntiva.

3. **Minore — i verdetti versionati degli strumenti adottati possono contraddire il controllo corrente.**  
   Ho cambiato `analysis/tools/out/scc/verdetto-scc.txt:4` in `VERDETTO: fail`: codice 0. [check.sh:125](analysis/tools/check.sh:125) esclude tutti i `verdetto-*` dal confronto.  
   **Correzione richiesta:** riconciliare almeno il risultato finale dei verdetti salvati con quello ricalcolato. La specifica non impone esplicitamente la verifica di questi file derivati: questa prova riguarda la coerenza delle evidenze, senza invalidare i campioni sottostanti.

Non ho osservato falsi rossi nelle due esecuzioni consecutive: entrambe rieseguono tutte le prove e trovano output identici ai versionati. Questa verifica riguarda l’ambiente e le cache presenti; non ho eseguito build senza cache.

Il diff effettivo comprende **128 file**, coincide con `file-modificati.txt` e tocca esclusivamente i percorsi autorizzati. Dalla lettura dei sette Dockerfile e degli script risultano basi fissate per digest, strumenti fissati per versione, temporanei host dentro il repository e nessun parser COBOL/JCL/copybook scritto in proprio. `CopyLister.java` usa il parser di ProLeap. Non ho eseguito un tracciamento delle scritture a livello di sistema.

Tutti i container delle prove sono stati rimossi automaticamente; la verifica finale trova **zero container propri residui**. Nessun `prune`, commit o push.