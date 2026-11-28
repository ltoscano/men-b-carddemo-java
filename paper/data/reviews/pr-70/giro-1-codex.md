BOCCIATA

La verifica di base passa, ma `verify.sh` accetta tre alterazioni del codice di produzione e lo smoke accetta una console malformata.

Ho lavorato su copie temporanee dello SHA `f3f02fd`, adattando soltanto nomi e allocazione delle risorse Docker. Sorgenti ripristinati, copie rimosse, nessun commit. Nessun container, rete, volume o tag immagine `menb-val70-*` rimasto.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| 1 | `./verify.sh`, con cache Docker `menb-val70-m2` | **0**. Quattro casi `ReadacctParitaTest` eseguiti, zero saltati/falliti/errori; zero ricevute di fallimento atteso. Nessuna riga READACCT nell’elenco. |
| 2 | `MENB_SMOKE_PROJECT=menb-val70-smoke ./smoke.sh` | **0**. OUTFILE 5350 byte, ARRYFILE 5500, VBRCFILE 2950; 752 righe di console. |
| 3 | `./quality/regressioni-verify.sh` | **0**, base riuscita e nove guasti riconosciuti. |
| 3 | `./quality/regressioni-regole.sh` | **0**, tutti i 44 casi riconosciuti. |
| 3 | `./quality/regressioni-copertura.sh rapporto-senza-classe agente-spento-batch difetto-batch spotbugs-assente spotbugs-troncato spotbugs-altra-corsa spotbugs-senza-classe cancello-spotbugs-skip-batch` | **0**, base riuscita e tutti gli otto casi riconosciuti. |
| 4 | Ispezione della tabella della PR e riesecuzione delle alterazioni sotto riportate | Tabella presente. Le nove alterazioni richieste sono rilevate; tre ulteriori alterazioni superano anche `verify.sh` completo. |
| 5 | `git diff origin/main...HEAD`; confronto con `.validazione/diff.patch`; `git status --short` | Diff coincidenti. Parità modificata soltanto nei punti ammessi. File versionati puliti; unico elemento non tracciato: `.validazione/`, fornito per questa validazione. |
| 6 | API GitHub `check-runs` sullo SHA finale | **8/8 check conclusi con successo**. [Risultati dello SHA](https://api.github.com/repos/ltoscano/men-b-carddemo-java/commits/f3f02fd9348eb14ae37b052361bf4df1448cf3a2/check-runs). |

L’unico file fuori dal **perimetro letterale** del diff è `carddemo-batch/pom.xml`: la dipendenza dal test-jar di domain serve a riusare l’ispezione del bytecode, è minima, ha versione del progetto e scope `test`. Giudico motivato questo scostamento. Il cambiamento di `compose.yaml` è soltanto il commento necessario a indicare il job; non modifica il prodotto.

`legacy/`, `verify.sh`, golden, comparatore e tabelle delle esclusioni sono invariati. La tabella compare nel commit `bf8413c`, prima del codice introdotto da `929ade2`.

Ho letto integralmente i cinque sorgenti richiesti. Destinazioni e costanti dei MOVE corrispondono a `legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT01C.cbl:216–239,254–260,277–305`; i 24 letterali sono identici alle rispettive righe sorgenti, compreso `EXPIRAION`. Il record di 300 byte e il filler derivano da `app/cpy/CVACT01Y.cpy:4–17`; la conversione della data da `app/asm/COBDATFT.asm:51–53`; PREDEL e disposizione dei file da `app/jcl/READACCT.jcl:22–48`, tutti sotto lo stesso percorso legacy. Entrambi i COPY hanno un corrispondente dichiarato.

L’oracle con ingresso vuoto restituisce **0**, START/END e tre file vuoti. I byte convenzionali sono dichiarati correttamente; la sostituzione con spazio è rilevata dai test.

Le prove sui guasti attraversano `Cbact01c` di produzione; `Prove.Uscite` avvolge le aperture reali su disco. La lacuna sul codice di uscita è descritta nel rilievo 3.

Le alterazioni sono state applicate singolarmente e ripristinate. I comandi Maven mirati sono stati eseguiti nel container; per i tre falsi verdi ho eseguito anche `./verify.sh` completo.

| Alterazione | Esito reale e diagnosi |
|---|---|
| Limiti di credito scambiati in OUTFILE | **Rosso, 1**: OUTFILE, record 1, posizione 31, `32 → 31`. |
| `-2500.00 → -250.00` | **Rosso, 1**: ARRYFILE, record 1, posizione 65, `02 → 00`. |
| `7B → 30` nell’occorrenza inizializzata 4 | **Rosso, 1**: ARRYFILE, record 1, posizione 80. |
| Lettura decrescente | **Rosso, 1**: OUTFILE, record 1, posizione 10, `30 → 35`. |
| Lettura senza ORDER BY | **Rosso, 1**: `laLetturaDichiaraLOrdineCrescentePerAcctId`, ordine non dichiarato. |
| Conto 5 saltato | **Rosso, 1**: OUTFILE, record 5, posizione 11, `35 → 36`. |
| Tutta la console del conto prima delle scritture | **Rosso, 1**: `ordineDegliEffettiPerConto`; sei test falliti. |
| Sentinelle conservate dopo fine anomala | **Rosso, 1**: `OUTFILE rimasto`. |
| DISPLAY ACCOUNT-RECORD senza filler | **Rosso, 1**: confronto della console, 122 byte anziché 300. |
| **Nuova:** saldo di VBRC-REC2 preso dal limite di credito | **Rosso, 1**: contenuto di VBRC-REC2 diverso. |
| **Nuova:** byte convenzionale della data scritto come spazio | **Rosso, 1**: OUTFILE, posizione 77, atteso `00`, trovato `20`. |
| **Nuova:** `ARRAYFILE → ARRYFILE` nel messaggio d’errore | **Rosso, 1**: console diversa nel test di creazione di ARRYFILE. |
| **Nuova:** END dopo la chiusura delle uscite | **Rosso, 1**: nel guasto di chiusura manca END nel prefisso atteso. |
| **Nuova:** codice 99 soltanto per apertura/lettura conti | **Falso verde: `verify.sh` 0**. |
| **Nuova:** PREDEL dopo l’apertura dei conti | **Falso verde: `verify.sh` 0**. |
| **Nuova:** con debito negativo, `1005.00 → 1525.00` in ARRYFILE | **Falso verde: `verify.sh` 0**. |
| Metodo `double` aggiunto a una classe di produzione | **Rosso, 1**, anche disattivando Checkstyle: l’ispezione compilata rileva firma, costante `1.5` e istruzione 175. |

Gli avvii senza nome e con nome inesistente terminano con **1**, stdout vuoto e nessun job eseguito. `installationCheckJob` rimane il job degli avvii precedenti; la riesecuzione READACCT sostituisce le sentinelle. I log applicativi restano su stderr.

Lo smoke gira con **bash 3.2 dell’host**, usa `od`/`tr` nel container e applica limiti ai comandi esterni. Ho verificato:

- job che non scrive: **1**, `OUTFILE non copiato ... il job non l'ha scritto`;
- byte generato alterato: **1**, OUTFILE record 1 posizione 20, `31 → 58`;
- confronto con file vuoto o troncato: **1**;
- stdout con coda senza LF: **0**, smoke completo riuscito.

La mancata esecuzione di `regressioni-codec.sh` è motivata: codec, vettori, helper di ispezione e `verify.sh` non cambiano; nessun suo caso riguarda direttamente il nuovo modulo batch.

1. **Bloccante — Lo smoke accetta dati residui dopo l’ultima riga della console.**  
   Evidenza: `smoke.sh:749–751` controlla soltanto il successo di `read`. Appendendo `SPURIO-SENZA-LF` allo stdout generato, `read` restituisce errore per il terminatore mancante e il contenuto viene ignorato. Lo smoke completo termina con **0**.  
   **Schema generale:** confondere EOF senza dati con lettura parziale contenente dati. **Correzione richiesta:** pretendere EOF esatto e aggiungere prove negative per code terminate e non terminate da LF. **Falso verde: sì; oracle infedele: no.** Riproduzione mediante alterazione di un artefatto generato; correzione nel file versionato `smoke.sh`.

2. **Bloccante — Il caso con addebito non nullo successivo al primo non verifica tutti i byte richiesti.**  
   Evidenza: `carddemo-batch/src/test/java/io/github/ltoscano/carddemo/batch/readacct/Cbact01cTest.java:189–190` verifica soltanto le dimensioni di ARRYFILE e VBRCFILE. Ho fatto scrivere `1525.00` invece di `1005.00` nel primo importo compresso di ARRYFILE quando il debito è negativo: test mirati e **`verify.sh` completo restano verdi**. Il sorgente prescrive sempre `1005.00` in `CBACT01C.cbl:256`.  
   **Schema generale:** controllare la forma anziché il contenuto nei casi particolari. **Correzione richiesta:** confrontare integralmente tutti e tre i file, conto interessato e conti successivi, con addebiti positivi e negativi in posizione iniziale e successiva. **Falso verde: sì, con byte errati; oracle infedele: no.** La prova modifica codice versionato; il rimedio richiede test versionati, senza cambiare golden o parità.

3. **Importante — Il codice di uscita non è verificato per ciascuna riga della tabella degli errori.**  
   Evidenza: `carddemo-batch/src/test/java/io/github/ltoscano/carddemo/batch/readacct/ReadacctJobTest.java:69–94` verifica 99 soltanto per apertura e lettura dei conti. Creazione, scrittura e chiusura verificano l’eccezione del programma, console e cancellazione, ma non l’esito applicativo. Limitando `EsitoReadacct` alle due fasi testate, le altre ricadono nel codice generico 5 e **`verify.sh` termina con 0**.  
   **Schema generale:** verificare il guasto interno senza verificare il contratto esterno del processo. **Correzione richiesta:** esercitare tramite l’applicazione reale ogni fase della tabella, pretendendo lo stesso codice dedicato, console esatta e assenza di tutte le uscite, anche con sentinelle. **Falso verde: sì; oracle infedele: no.** Prova e rimedio riguardano file versionati; nessun artefatto falsificato.

4. **Importante — L’ordine di PREDEL non è protetto dai test.**  
   L’ordine attuale è corretto in `Cbact01c.java:146–148`. Spostando PREDEL dopo `p0000AcctfileOpen()`, quindi dopo la prima interrogazione dei conti, **`verify.sh` continua a terminare con 0**. I controlli sulle sentinelle osservano soltanto lo stato finale.  
   **Schema generale:** verificare gli effetti finali senza verificarne il momento. **Correzione richiesta:** con sentinelle preesistenti, verificare che siano già assenti al primo DISPLAY e all’apertura della sorgente conti. **Falso verde: sì; oracle infedele: no.** La prova modifica codice versionato; il rimedio richiede test versionati.

5. **Minore — La tabella non rispetta la granularità prescritta.**  
   Evidenza: `docs/programmi/CBACT01C.md:189–202` accorpa istruzioni distinte e paragrafi diversi: MOVE delle righe 288/303, MOVE 289/304, WRITE 290/305, controlli e DISPLAY dei rami d’apertura/chiusura. Altri accorpamenti compaiono alle righe 130 e 171.  
   **Schema generale:** copertura dichiarata per intervalli anziché per istruzione osservabile. **Correzione richiesta:** separare sistematicamente le righe, con riferimento Java ed esito per ciascuna istruzione, come richiede la specifica. **Falso verde: non dimostrato; oracle infedele: non rilevato.** Difetto già presente nel documento versionato; non richiede falsificare artefatti.