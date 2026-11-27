**BOCCIATA — restano falsi verdi nel perimetro, incluso un rapporto dell’oracle infedele ai file realmente prodotti.**

Il diff fornito coincide con `git diff origin/main...HEAD`: otto file, tutti ammessi. **File fuori perimetro: nessuno.** Legacy e attesi preesistenti non risultano modificati.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Build normale | `./oracle/run.sh build` | **0** |
| Suite, prima corsa | `./oracle/run.sh --all --check` | **0** |
| Suite, seconda corsa consecutiva | `./oracle/run.sh --all --check` | **0** |
| Analisi | `./analysis/run.sh --all --check` | **0** |
| Acquisizioni fallite | `./oracle/run.sh build`, con wrapper miei, un punto alla volta | **52/52 prove valide**: codice 1, nessuna `IMPRONTA`, diagnostica pertinente, bersaglio raggiunto. Coperti entrambi i `cobc --info`, entrambi i `cobcrun`, gli ambienti e tutti i 40 hash, compreso `acu.conf` non ultimo. [Registro consolidato](file locale del Validatore, non conservato) |
| Conteggi zero ed errore operativo | Build normale; build con `grep -c` autentico seguito da ritorno 2 | 23 compilazioni con zero avvertimenti/errori restano verdi; ritorno 2 provoca codice 1, diagnostica `grep, codice 2`, nessuna impronta |
| Configurazione alternativa | Build con una cartella mia; verifica del risultato | Build **0**; manifesto integralmente identico all’atteso indipendente; nessun `can't cd`; verifica **1**, con tre difetti pertinenti |
| Esiti persi citati nell’issue | Wrapper su entrambe le `ls`, entrambe le `cat` di `esegui.sh`; `git hash-object` di `image_tag` | Propagati: `esegui.sh` **2**, `image_tag` **1** |
| Compatibilità delle interfacce | `compile.sh uno`, caso sano e sorgente inesistente; `esegui.sh`; confronto delle funzioni di `lib.sh` | Esiti **0/1** e log identici a `main`; rapporti, ambiente, nomi delle funzioni e tag dell’immagine identici |
| Invarianti rispetto a `origin/main` | Suite completa su `origin/main`; confronto degli attesi e dei log delle prove | Main **0**; tutte le **167 righe** preesistenti di prove negative/controprove ricompaiono identiche in entrambe le corse |
| CI sulla mutazione | `gh run view 46055162057 --log` e metadati | **Failure** nel passo «Controlli di oracle/», SHA `f8ffb3a8fdb9d29e2da160b7f649efbd2ca4f013`, per l’hash alterato di `ibm.conf`; costruzione dell’immagine riuscita |
| CI sul ripristino | `gh run view 46055309848 --log` e metadati | **Success**, SHA `6f4a6138d2ad3fe04e1357f55056b07ec5319ddd`. Contenuto finale identico a `97cc47e`, anche come tree Git |
| Ricerca dello stesso schema | Ispezione e ulteriori mutazioni indipendenti | **Non soddisfatto completamente:** rilievi 1–5 |

Il workflow dichiara push e pull request, submodule ricorsivi, limite di 45 minuti per il job e 40 per i controlli. I conteggi CI coincidono con **entrambe** le corse locali: build 119, abend 7, adattamenti 54, avviatore 5, avvio 14, dialetto 3, routines 25, segno 5, selftest 3; sei controprove complessive. Le prove con file illeggibili sono eseguite: cinque in build e una in adattamenti. UID effettivo: 1001 in CI, 501 in locale. [Confronto](file locale del Validatore, non conservato)

La copia usata dalle prove attraversa gli stessi `build/run.sh`, `lib.sh` e `compile.sh`, salvo gli involucri inseriti. Disattivando temporaneamente il controllo di `cobc --version`, la prova A01 diventa rossa: non ho trovato una divergenza corrente che renda queste prove vuote.

L’anticipo delle acquisizioni conserva identici gli otto file testuali dichiarati, tutti i 27 log e le copie adattate. **L’impronta non è identica:** cambia l’hash degli input per `compile.sh`; cambia anche quello degli artefatti, i cui binari incorporano timestamp e nomi temporanei già variabili su `main`.

1. **Bloccante — `esegui.sh` perde ancora l’esito del produttore nelle pipeline.**  
   In [esegui.sh:70](oracle/esegui.sh:70) e riga 73 viene controllato l’esito di `printf | sort` o `printf | tr`, ma lo script non abilita `pipefail`. Con output autentico e ritorno 42 di `printf`, termina comunque con **0**.

   Ho anche riprodotto un effetto concreto: elenco troncato seguito da ritorno 42, file `ZZ_INATTESO` realmente presente nella cartella di lavoro, rapporto che lo omette ed è **identico al rapporto sano**, uscita **0**. [Evidenza](file locale del Validatore, non conservato)

   **Schema:** controllare una pipeline non controlla automaticamente ogni suo comando. **Correzione richiesta:** propagare gli errori di ciascun produttore nelle due pipeline e aggiungere prove negative con output completo e parziale. **Falso verde: sì. Oracle infedele: dimostrato.**

2. **Bloccante — `verifica.sh` ignora ancora acquisizioni fallite.**  
   `pipefail` non basta quando il risultato della pipeline viene ignorato. Restano pipeline di preparazione senza controllo alle righe 42–60, estrazioni con `cut` e `awk` alle righe 65–67 e sostituzioni con `basename` alle righe 89 e 119. Si veda [verifica.sh:45](oracle/build/verifica.sh:45).

   Ho sostituito separatamente `ls`, l’`awk` delle righe TSV, `cut`, il `grep` dell’elenco e `basename`: output autentico, poi 42. **In tutti e cinque i casi la verifica termina con 0.** [Registro](file locale del Validatore, non conservato)

   **Schema:** assegnazioni o pipeline fallite vengono seguite da confronti riusciti che ne cancellano l’esito. **Correzione richiesta:** controllare esplicitamente tutte le acquisizioni di queste sezioni, con prove negative per ciascun punto funzionale; aggiornare la dichiarazione del README secondo cui resterebbero soltanto sostituzioni diagnostiche. **Falso verde: sì; affidabilità dell’oracle compromessa, variazione semantica non dimostrata da questa prova.**

3. **Bloccante — restano sostituzioni mascherate nella build di produzione.**  
   [build/run.sh:24](oracle/build/run.sh:24) inserisce ancora `$(in_container "$elenco")` negli argomenti di `orun`; [compile.sh:218](oracle/build/compile.sh:218) inserisce `$(printf '\t')` nell’assegnazione di IFS del comando `read`.

   In entrambe le controprove il produttore restituisce l’output autentico e poi **42**: `./oracle/run.sh build` termina con **0 e scrive `IMPRONTA`**.

   **Schema:** il comando contenitore restituisce successo e maschera la sostituzione fallita. **Correzione richiesta:** acquisire prima i valori, verificarne l’esito e aggiungere entrambe le prove sulla build di produzione, verificando anche l’assenza dell’impronta. **Falso verde: sì; viene certificata una build con un’operazione fallita.**

4. **Importante — il controllo dei codici di `cobc` accetta evidenze incomplete.**  
   In [verifica.sh:106](oracle/build/verifica.sh:106), l’assenza di righe `== codice ...` è trattata come un normale caso senza corrispondenze.

   Eliminando **tutte** queste righe dai log, la verifica restituisce **0**. Anche `stamp_problem` restituisce 0, perché i log non entrano nell’hash degli artefatti. [Evidenza](file locale del Validatore, non conservato)

   **Schema:** «nessun codice errato trovato» viene scambiato per «codici presenti e corretti». **Correzione richiesta:** verificare presenza e cardinalità dei codici rispetto alle invocazioni attese, con prove di cancellazione totale e parziale. Conservare l’esito 1 di `grep` soltanto nei contesti in cui l’assenza è ammessa. **Falso verde: sì; evidenza dell’oracle incompleta accettata.**

5. **Importante — il censimento fuori perimetro è incompleto.**  
   Non sono elencati, fra gli altri:

   - `routines/coerenza.sh:23`, `routines/run.sh:23`, `routines/check.sh:47,179`;
   - `abend/check.sh:44`, `dialetto/check.sh:36`, `segno/check.sh:45`;
   - `adattamenti/check.sh:62,133,158,265`;
   - `adattamenti/verifica-copie.sh:58,84,114,136,234`;
   - `adattamenti/verifica-carico.sh:21,22,29,34`, `adattamenti/verifica-uscite.sh:36`;
   - `avvio/check.sh:38`, `selftest/scenari.sh:22,73`.

   Ho riprodotto il caso di `routines/coerenza.sh`: `ls` autentico seguito da 42 lascia il controllo **verde**.

   **Schema:** ricerca parziale delle sostituzioni funzionali, aggravata dall’affermazione che quelle rimaste sarebbero solo diagnostiche. **Correzione richiesta:** completare il censimento nella PR e il rinvio alla issue #45, distinguendo i casi funzionali da quelli diagnostici, senza modificare qui gli script esclusi. **Il censimento non altera direttamente l’oracle; le occorrenze omesse possono produrre falsi verdi.**

Le sostituzioni nei messaggi già emessi dopo un difetto — per esempio `verifica.sh:57,60,73,151,164,167,180` — e il conteggio finale di `build/run.sh:33` sono diagnostiche. Non ho trovato `echo … | grep -q` sotto `pipefail`.

I riscontri sul legacy comprendono il PARM di [CBACT04C:180](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:180), l’interfaccia di [CBSTM03B:114](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03B.CBL:114), il blocco adattato di [CBSTM03A:266](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03A.CBL:266), il campo importo in [CVTRA06Y:10](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVTRA06Y.cpy:10) e il ramo credito/debito in [CBTRN02C:548](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBTRN02C.cbl:548). I quattro valori citati di `dailytran.txt` e le righe con TAB di `CUSTREC.cpy` coincidono con il sorgente.

Nessuna correzione o commit effettuato. Modifiche di prova ripristinate; risorse Docker `menb-val49-` rimosse, senza rimuovere immagini o volumi condivisi.