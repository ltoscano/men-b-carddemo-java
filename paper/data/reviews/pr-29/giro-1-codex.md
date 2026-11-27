**BOCCIATA — riprodotto un falso verde sulle opzioni effettive di compilazione; confermata l’infedeltà del segno sui dati ASCII forniti.**

Ho eseguito le prove sul ramo `811660ebc42202d79b6158e1d4838029dbd8616c`. Tutte le mutazioni sono state ripristinate; la ricostruzione finale è riuscita. Nessun commit o push. Il legacy è rimasto pulito.

Comandi completi, codici d’uscita e tempi sono nel registro delle esecuzioni (file locale del Validatore, non conservato). Ogni esecuzione di prova aveva un timeout esterno mio; per i comandi completi dell’oracle: 600 s. Non ho eseguito operazioni Docker globali.

| Criterio | Comando eseguito | Esito osservato | Durata |
|---|---|---|---:|
| Perimetro | `git diff --name-only origin/main...HEAD`; controllo dello stato del submodule | Solo `oracle/`; legacy pulito | 0,184 s¹ |
| Build iniziale | `./oracle/run.sh build` | **0**, 20 artefatti complessivi | 3,793 s |
| Primo giro completo | `./oracle/run.sh --all --check` | **0**, 45 prove negative superate | 42,179 s |
| Secondo giro consecutivo | `./oracle/run.sh --all --check` | **0**, 45 prove negative superate | 123,431 s |
| Compilazione degli 11 | `./oracle/run.sh build --check` | **0** | 73,475 s |
| Avvio degli eseguibili e chiamanti dei moduli | `./oracle/run.sh avvio --check` | **0**; otto uscite 99, `COBSWAIT` e `DTCCALL` 98, `M03BCALL` 0 | 31,264 s |
| Area PARM | `./oracle/run.sh avviatore --check` | **0**; byte `00 0a 32 30 32 32 30 37 31 38 30 30` | 15,240 s |
| CEE3ABD, entrambe le forme | `./oracle/run.sh abend --check` | **0**; uscita 99 e record precedente conservato | 22,937 s |
| Dipendenze, cicli, controllo mancante | `./oracle/run.sh selftest --check` | **0** | 1,798 s |
| Ripristino finale | `./oracle/run.sh build` | **0** | 20,480 s |
| Stato finale | `git diff --exit-code`; stato legacy e verifica perimetro | Nessuna modifica tracciata residua | 0,180 s |

¹ Durata della riesecuzione misurata del controllo di perimetro.

Le mutazioni seguenti sono mie, oltre a quelle automatiche della PR. Non ho falsificato output di Docker, compilatore o strumenti.

| Mutazione | Comando di controllo eseguito | Esito osservato | Durata |
|---|---|---|---:|
| Lunghezza PARM diminuita di uno, poi ricompilazione | `./oracle/run.sh avviatore --check` | **1**: legge 9 anziché 10 | build 5,128 s; controllo 2,472 s |
| Testo PARM troncato di un byte, poi ricompilazione | `./oracle/run.sh avviatore --check` | **1**: byte e testo diversi | build 8,982 s; controllo 3,787 s |
| CEE3ABD termina con 0, poi ricompilazione | `./oracle/run.sh abend --check` | **1**: codice diverso per entrambi i chiamanti | build 9,255 s; controllo 7,093 s |
| `-fbinary-truncate` tolto da `cobc.opts` | `./oracle/run.sh build --check` | **1**: opzioni diverse da quelle fissate | 13,143 s |
| `avvio/check.sh` rimosso temporaneamente | `./oracle/run.sh --all --check` | **1**: `passo avvio: manca check.sh` | 20,564 s |
| `CBACT03C` sostituito con `CBACT02C` | `./oracle/run.sh avvio --check` | **1**: impronta degli artefatti diversa | 1,943 s |
| Stesso scambio, verifica diretta dei simboli nel container | `sh /oracle/build/verifica.sh …` | **1**: manca il simbolo `CBACT03C` | 2,016 s |
| Input dell’avviatore cambiato dopo la build | `./oracle/run.sh avvio --check` | **1**: build non aggiornata | 1,613 s |
| **`-fno-binary-truncate` aggiunto ai comandi reali e ai relativi log** | **`./oracle/run.sh --all --check`** | **0: falso verde**, incluse tutte le 45 prove negative | **106,789 s** |

Gli script riproducibili delle mutazioni sono mutations.py (file locale del Validatore, non conservato) ed extra-option.py (file locale del Validatore, non conservato).

1. **Bloccante — il controllo accetta opzioni aggiuntive che annullano quelle obbligatorie. Impatto: falso verde; può produrre un oracle infedele.**

   Evidenza: `oracle/build/verifica.sh:67–68` controlla soltanto che il primo comando inizi con:

   ```sh
   "comando: cobc $attese "
   ```

   Tutto ciò che segue viene accettato dal carattere jolly. Ho modificato `oracle/build/compile.sh:42–50` aggiungendo `-fno-binary-truncate` sia alle invocazioni effettive sia ai messaggi che le registrano. Il log reale di CBACT04C (file locale del Validatore, non conservato) contiene quindi:

   ```text
   cobc -std=ibm -fbinary-truncate -fsingle-quote -Wall -I/legacy/app/cpy -fno-binary-truncate -c …
   ```

   Il comando completo resta verde. Una sonda compilata attraverso lo stesso script alterato (file locale del Validatore, non conservato) conserva **12345** in `PIC S9(4) COMP`; con la configurazione originale ottengo **2345**.

   Non è uno strumento che mente: compilatore e log riportano un lavoro realmente diverso da quello richiesto. È falsa, come garanzia dei controlli, l’affermazione del README sulle opzioni effettive conformi (`oracle/README.md:33`).

   **Correzione richiesta:** confrontare l’intero insieme delle opzioni di ogni invocazione COBOL, ammettendo soltanto gli argomenti strutturali previsti per tipo, sorgente e destinazione. Aggiungere una prova negativa reale con un’opzione aggiuntiva che sovrascrive quella richiesta.

2. **Importante — il default del segno interpreta importi negativi come positivi. Impatto: oracle infedele quando legge i dati ASCII forniti.**

   Evidenza: `oracle/README.md:56,132` riconosce il problema ma lo rinvia; `oracle/cobc.opts` non imposta `-fsign=EBCDIC`.

   Ho eseguito una sonda (file locale del Validatore, non conservato) che legge la seconda riga di `app/data/ASCII/dailytran.txt` utilizzando **il copybook originale `CVTRA06Y`**:

   | Configurazione | Importo letto | Ramo della condizione `DALYTRAN-AMT >= 0` |
   |---|---:|---|
   | Opzioni della PR | **+919,00** | credito |
   | Aggiunta di `-fsign=EBCDIC` | **−919,00** | debito |

   Esecuzione nel container: **0, 1,007 s**; log (file locale del Validatore, non conservato). È una sonda, non un’esecuzione completa di `CBTRN02C`. Il collegamento al comportamento del programma è però diretto: `CBTRN02C.cbl:547–551` usa quella condizione per scegliere quale saldo aggiornare. La distinzione del segno è documentata anche da [IBM](https://www.ibm.com/docs/en/SS6SG3_6.4.0/pdf/pgmvs.pdf) e l’opzione è descritta dal [manuale GnuCOBOL](https://gnucobol.sourceforge.io/doc/gnucobol.html).

   L’elaborazione completa dei dati appartiene a #5; la rappresentazione numerica scelta dal compilatore appartiene a questo ambiente. **Il default attuale è già dimostrabilmente incompatibile con i dati presenti: non è una scelta ancora neutra.**

   **Correzione richiesta:** fissare `-fsign=EBCDIC` nel file unico, aggiornare il controllo delle opzioni e introdurre una regressione automatica con importi positivi e negativi. Un eventuale contratto alternativo deve specificare e verificare la conversione dei dati prima di usarli come riferimento.

Ho verificato separatamente gli altri punti di fedeltà richiesti. Le sonde sono in probes.sh (file locale del Validatore, non conservato), linkage.sh (file locale del Validatore, non conservato) e index-probe.sh (file locale del Validatore, non conservato); le invocazioni Docker complete sono nel registro.

| Tema | Eseguito e osservato | Valutazione |
|---|---|---|
| `-fbinary-truncate` | `MOVE 12345` verso `S9(4) COMP`: 2345; senza troncamento: 12345 | Giustificato rispetto al default IBM `TRUNC(STD)`. Il default dell’installazione originale resta ignoto, come dichiarato. [IBM TRUNC](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=options-trunc) |
| Dimensione e byte dei `COMP` | `S9(4) COMP` occupa due byte; 2345 produce `09 29`; PARM correttamente big-endian | Nessun difetto osservato |
| `-fsingle-quote` | `QUOTE` produce il byte ASCII 39 | Coerente con `APOST` nel JCL letto. Nessun uso di `QUOTE` rilevato negli undici programmi. [IBM APOST](https://www.ibm.com/docs/en/cobol-zos/6.5.0?topic=guide-option-comparison) |
| `arithmetic-osvs` | Con `A=1,239`, `B=8`, `C=100`, risultato a due decimali di `A / B * C`: **15,40**; disabilitando l’opzione: **15,48** | L’opzione cambia davvero i risultati. Il primo risultato è coerente con le regole documentate IBM per questo caso; disabilitarla automaticamente non sarebbe una correzione. La parità generale resta non dimostrata. [Precisione IBM](https://www.ibm.com/docs/en/SS6SG3_6.5/pdf/pgmvs.pdf) |
| Collazione | Confronto fra `'0'` e `'A'`: ordine invertito aggiungendo `-fdefault-colseq=EBCDIC` | Differenza reale. I confronti ordinati letti nei batch riguardano soprattutto date; non ho dimostrato un ramo errato su un loro input valido |
| Collazione degli indici | BDB restituisce le chiavi `0`, `A` in quest’ordine **anche con** `-fdefault-colseq=EBCDIC` | Quell’opzione da sola non risolve l’ordine degli indici |
| Chiave alternativa unica | Sonda BDB: inserimento con alternativa duplicata → stato **22** | Conferma il lato GnuCOBOL; non risolve la discordanza con `NONUNIQUEKEY` del JCL |
| Campi senza `VALUE` | Byte iniziali X'00'; con `-fdefaultbyte=init`: spazio per `PIC X`, `'0'` per `PIC 9` | Il default dichiarato è reale. Non dimostra fedeltà a z/OS: IBM definisce imprevedibile il valore non specificato. [IBM VALUE](https://publibfp.dhe.ibm.com/epubs/pdf/igy6lr40.pdf) |
| Record variabili | Record `ABC`: `00 03 00 00 41 42 43` | Confermata la descrizione del formato GnuCOBOL nel README |
| `NEXT SENTENCE` | La sonda salta oltre il punto successivo | Confermato per il caso provato |

La sonda combinata delle opzioni è terminata in **1,091 s**; quella BDB in **1,604 s**.

L’avviatore C costruisce l’interfaccia di avvio e non contiene calcoli di business. Le sue mutazioni di lunghezza e contenuto sono state intercettate. Il riempimento oltre il PARM con X'00' rimane una scelta locale dichiarata, rilevante per parametri corti.

Gli stub **alterano intenzionalmente l’esecuzione**: i tre segnaposto la interrompono con 98; `CEE3ABD` usa una terminazione normale di libcob con 99 e chiusura dei file. È quanto richiede questa specifica, ma non equivale all’abend z/OS, specialmente per cleanup e buffer. Il test dimostra la conservazione del record nelle condizioni provate; l’affermazione generale del README sull’assenza di buffering va letta più strettamente di quanto sia formulata.

Ho inoltre compilato e confrontato `M03BCALL`/`CBSTM03B` con collegamento statico e dinamico: **output identico, 3,255 s**. Le chiamate dinamiche non reinizializzano automaticamente lo stato a ogni invocazione, nemmeno secondo la [documentazione IBM](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=program-making-dynamic-calls). Cambiano risoluzione e disponibilità dei moduli; non ho osservato una divergenza di business nei percorsi provati.

Nel README sono quindi **dimostrati dai controlli della PR** compilazione, avvio, PARM, stato 35 sotto GnuCOBOL e le due forme dello stub. **Restano dichiarazioni o verifiche rinviate** la parità generale dell’aritmetica, i dettagli VSAM, l’inizializzazione originale e gli effetti dell’abend z/OS. La garanzia sulle opzioni effettivamente usate è invece smentita dal rilievo 1.

Non considero mancanti l’elaborazione completa dei dati, le routine esterne o la CI: la specifica li esclude o li rinvia esplicitamente. La consegna mancante qui è un controllo capace di respingere la configurazione di compilazione sbagliata che ho riprodotto.