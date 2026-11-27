BOCCIATA

Ho riprodotto falsi verdi dopo la rigenerazione delle fixture, pur lasciando invariati legacy e attesi a mano.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Generazione | `./analysis/run.sh data-fixtures` | **0**; 22 file, 1.813 record, 55 record attesi; nessuna differenza nei versionati. `run.sh`, `check.sh`, `deps` eseguibili. |
| Primo controllo | `./analysis/run.sh data-fixtures --check` | **0**; 62 prove negative riportate con nome e diagnosi. |
| Secondo controllo consecutivo | `./analysis/run.sh data-fixtures --check` | **0**, stessi conteggi. |
| Conteggi per file | Sezione conteggi del precedente comando; `cat analysis/data-fixtures/out/conteggi.tsv` | Tutte le 22 righe coerenti: dimensione/righe fisiche = record decodificati; 55 record complessivi negli attesi. |
| Suite completa | `./analysis/run.sh --all --check` | **0 nella corsa conclusiva**; tutte le nove analisi concluse. |
| Perimetro | `git diff --name-only origin/main...HEAD` | 93 file, tutti ammessi. **File fuori perimetro: nessuno.** |
| Integrità | `git diff --exit-code`; `git status --short`; stato del submodule | Diff dei versionati vuoto; legacy pulito a `59cc6c2`. Rimane soltanto `?? .validazione/`, già presente inizialmente. |
| CI | `gh pr checks 56`, lettura dei log tramite `gh` | Tutti i job verdi sullo SHA `488621b`, compreso [analysis-check](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46079624802/job/140775323920). |

Due precedenti corse complete sono uscite con 1: la prima per un errore nel mio wrapper dei nomi Docker, corretto fuori dal repository; la seconda perché Docker ha interrotto un container con `unexpected EOF` e temporaneamente perso il socket. La ripetizione conclusiva è nel [log completo](/tmp/menb-val56-logs/all-check3.log).

I rilievi sono:

1. **Bloccante — il round-trip non verifica indipendentemente la conservazione del file sorgente.**  
   In `analysis/data-fixtures/glue/fixture.py:363–370`, i campi vengono confrontati con `buf` e `riga`, entrambi prodotti dalla stessa lettura della colla. Nella copia privata ho alterato quella lettura: byte assoluto **88072** dell’export, record 177, da `D7` a `C2`; la descrizione passa da `Purchase…` a `Burchase…`. Legacy e attesi restano invariati. Prima della rigenerazione fallisce X01; dopo la normale rigenerazione, **`--check` termina con 0 e tutte le 62 prove passano**.  
   **Schema generale:** confronto circolare fra rappresentazioni derivate dallo stesso buffer alterato. **Correzione richiesta:** verificare indipendentemente numero, ordine e byte ricostruiti contro `ing.dati`, includendo terminatori e distinguendo il riempimento; aggiungere una mutazione della lettura nella colla che fallisca anche dopo la rigenerazione.  
   **Falso verde: sì. Oracle infedele: sì**, riprodotto su un valore testuale. Richiede modificare la **colla versionata e rigenerare normalmente**, senza falsificare manualmente artefatti. [Esito della verifica mutata](/tmp/menb-val56-logs/mutant-check.log).

2. **Importante — manca la verifica dell’insieme completo delle corrispondenze.**  
   `glue/verificatore.py:50–57` controlla soltanto la simmetria delle coppie dichiarate. Ho sostituito con `-` entrambe le corrispondenze di `ASCII/tcatbal.txt` e `EBCDIC/…TCATBALF.PS`. Dopo la rigenerazione, i confronti scendono **da 10 a 9**, ma **`--check` e tutte le 62 prove restano verdi**.  
   **Schema generale:** una relazione omessa in entrambe le direzioni scompare anche dall’insieme usato per verificarla. **Correzione richiesta:** pretendere l’insieme esatto delle coppie dovute, non soltanto la coerenza di quelle presenti; provare omissioni bilaterali, compresi gli alias dei conti.  
   **Falso verde: sì. Oracle infedele: possibile per differenze occultate.** Richiede modificare l’**inventario versionato**, seguito da normale rigenerazione; nessuna falsificazione manuale degli output. [Controesempio](/tmp/menb-val56-logs/unpair-check.log).

3. **Importante — esiti operativi persi negli script shell.**  
   In `lib.sh:33`, lo stato della pipeline `tail | cut` dentro `[` viene perso. Ho fatto stampare a `tail` il testo reale e poi terminare con **7**: `run.sh` termina comunque con **0**. In `check.sh:60`, `grep` con uscita **2** viene trattato come assenza di corrispondenze: anche questo `--check` termina con **0**.  
   **Schema generale:** sostituzioni di comando e condizioni che consumano l’output senza distinguere errore operativo e risultato negativo. **Correzione richiesta:** acquisire e controllare separatamente gli stati; per `grep`, distinguere 0, 1 e valori superiori. Aggiungere entrambe le prove e cercare lo stesso schema negli script nuovi.  
   **Falso verde: sì. Oracle infedele: non dimostrato da queste due prove.** La riproduzione non richiede modificare versionati né artefatti: basta l’iniezione di errori non nulli nei comandi. La correzione riguarda gli **script versionati**. [Tail](/tmp/menb-val56-logs/tail-failure.log), [grep](/tmp/menb-val56-logs/grep-failure.log).

4. **Importante — l’inventario copre codici diagnostici, non ogni asserzione; la prova del residuo non esercita la pulizia dichiarata.**  
   Ho disabilitato soltanto la guardia su codifica/provenienza in `glue/verificatore.py:40`: **tutte le 62 prove passano ancora**. I03 risulta coperto grazie alla diversa asserzione sui duplicati. Il conteggio in `glue/negativi.py:466–479` non dimostra quindi la copertura richiesta.  
   Inoltre `check.sh:78–87` prepara il residuo in `res/out`, ma fa generare in `res/nuova/out`: il vecchio `res/out` resta presente e il test passa. Non viene esercitata `dfx_genera` con un residuo nella sua destinazione effettiva.  
   **Schema generale:** nome/codice della prova usato come surrogato dell’asserzione e del percorso realmente esercitati. **Correzione richiesta:** censire le guardie logiche separatamente, provarne la rimozione e correggere il test del residuo affinché attraversi la funzione di produzione e la stessa destinazione.  
   **Falso verde dei test: sì. Oracle infedele: possibile per regressioni non rilevate**, non dimostrato dalla sola rimozione di questa guardia. Servono modifiche ai **test versionati**; nessuna falsificazione di artefatti. [Guardia rimossa](/tmp/menb-val56-logs/guard-removed-check.log).

5. **Minore — riferimento al legacy errato nell’inventario scritto a mano.**  
   `inventario.tsv:36` colloca i dati in linea di `DUSRSECJ.jcl` alle righe **34–43**. La riga 34 è `SYSUT1 DD *`; i dieci record sono alle **35–44**, compreso `USER0005` alla 44.  
   **Schema generale:** riferimenti nelle note testuali non verificati dal controllo della provenienza strutturata. **Correzione richiesta:** correggere l’intervallo e ricontrollare gli altri riferimenti scritti a mano.  
   **Nessun oracle infedele dimostrato; il check accetta una citazione documentale falsa.** Serve modificare **`inventario.tsv`, versionato**; nessun artefatto generato da falsificare.

6. **Minore — il rapporto generato omette osservazioni rilevanti sui dati.**  
   `docs/legacy-map/fixture.md` non riporta il salto della sequenza **450→460**, né la coda non nulla di INIT; non qualifica come non spiegate le due differenze di valore. L’elenco anomalie dell’export contiene soltanto l’intestazione.  
   Ho inoltre trovato NUL in ZIP e gruppo anche al **record 100**, oltre al 51 citato nella PR: offset assoluti **49628–49647**, venti byte `00`. I campi restano correttamente validi come `X(10)`: questa è un’osservazione sui dati, non una richiesta di cambiarne lo stato. Il sorgente incrementa la sequenza di uno in `app/cbl/CBEXPORT.cbl:529–530`; il FILLER di INIT è definito in `app/cpy/CVTRA05Y.cpy:18`.  
   **Schema generale:** osservazioni conservate nei byte o nel testo della PR, ma perse nel rapporto versionato. **Correzione richiesta:** riportarle nel documento generato, con record/offset e limiti delle spiegazioni, conservando stati e valori.  
   **Falso verde sulla completezza del rapporto: sì; oracle infedele nei valori: non osservato.** Serve modificare il **generatore versionato** e rigenerare.

7. **Minore — tabella Markdown delle differenze malformata.**  
   In `docs/legacy-map/fixture.md:53`, i due `|` della chiave composta non sono escapati: la riga ha **nove colonne invece delle sette dichiarate**. I backtick non proteggono i separatori nelle tabelle GFM. La costruzione avviene in `glue/documento.py:69`.  
   **Schema generale:** interpolazione dei valori senza escaping del formato di destinazione. **Correzione richiesta:** escapare le celle e controllare la struttura delle tabelle generate.  
   **Nessun falso verde sui dati o oracle infedele diretto; la rappresentazione documentale è errata.** Serve modificare il **generatore versionato**, poi rigenerare il documento.

Per le otto mutazioni richieste ho osservato:

| Mutazione propria | Esito |
|---|---|
| Record 23 tolto da CARDDATA, con intestazione e conteggio aggiornati | Fallisce X01, X03 |
| Due record ASCII scambiati | Fallisce X01 |
| Byte legacy letto diversamente dalla colla | X01 iniziale; **verde dopo rigenerazione**, rilievo 1 |
| Segno negativo COMP-3 letto positivo | Fallisce D02, X01, X02 |
| Riga ASCII corta riempita con zeri | Fallisce D02, X01, X03 |
| USRSEC omesso da inventario, fisica e attesi insieme | Fallisce I01, X03 |
| Anomalia della riga 19 tolta dall’elenco | Fallisce X03 |
| Atteso e fixture alterati entrambi da −919,00 a +919,00 | Fallisce D02, X01 |

[Log delle mutazioni](/tmp/menb-val56-logs/mutations.log).

Il campione letto con `xxd`, applicando i contratti e le tabelle di codifica, comprende **17 record fuori dagli attesi**, più INIT. Nei nomi EBCDIC sotto abbrevio il prefisso `AWS.M2.CARDDEMO.`.

| File | Record | Alcuni riscontri |
|---|---:|---|
| ASCII/acctdata.txt | 17 | Conto 17, saldo 33,00 |
| ASCII/carddata.txt | 23 | Conto 46, CVV 196 |
| ASCII/cardxref.txt | 19 | Cliente/conto 34; 36 byte originali, 14 aggiunti |
| ASCII/custdata.txt | 27 | Cliente 27, Ward Henri Jones |
| ASCII/dailytran.txt | 37 | Importo 777,33 |
| ASCII/discgrp.txt | 20 | DEFAULT/01/0003, tasso 25,00 |
| ASCII/tcatbal.txt | 33 | Conto 33, saldo 0,00 |
| ASCII/trancatg.txt | 9 | Tipo 03, categoria 1 |
| ASCII/trantype.txt | 4 | Tipo 04, Authorization |
| EBCDIC/ACCTDATA.PS | 18 | Saldo 144,00 |
| EBCDIC/DALYTRAN.PS | 7 | DISPLAY con ultimo byte `D7`: −56,77 |
| EBCDIC/USRSEC.PS | 6 | USER0001, LAWRENCE |
| EBCDIC/EXPORT.DATA.PS | 23 C; 72 A; 123 X; 157 T; 477 D | FICO 337; saldo 55,00; conto 46; COMP-3 `00 00 00 05 67 7D` = −56,77; CVV 21 |
| EBCDIC/DALYTRAN.PS.INIT | 1 | 342 byte nulli, poi `F0 F0 F0 F0 F0 F1 F0 F0` |

INIT è necessariamente già negli attesi: contiene un solo record. Il [riscontro completo campo per campo](/tmp/menb-val56-logs/audit-byte.log), affiancato da una decodifica indipendente senza importare codec o adattatore della PR, coincide con le fixture per **1.813 record e 23.470 campi**.

Ho riconciliato tutte le dimensioni e i terminatori: nessun ulteriore record troncato, eccedenza ignorata o file dati omesso. Confermati i 50 record corti di `cardxref.txt`, CRLF/LF **49/1** in `tcatbal.txt`, **6/1** in `trantype.txt`, CRLF **18/18** in `trancatg.txt`, le due differenze di valore e l’identità SHA-256 dei due file conti.

Le scelte dichiarate risultano così:

| Scelta | Riscontro sul sorgente | Dichiarata e distinguibile nella fixture |
|---|---|---|
| Riempimento ASCII con spazi | Nessun caricatore dei `.txt` trovato nei JCL, PROC o COBOL del manifesto; non determinato dal sorgente | Sì: colonne byte originali/aggiunti e origine `riempimento` |
| Chiave `DALYTRAN-ID` | File sequenziale: `CBTRN02C.cbl:29–32` | Sì, dichiarata come scelta; nessun byte aggiunto |
| Contratto INIT | Caricamento nel KSDS: `TRANFILE.jcl:70–74`, layout `CVTRA05Y` | Sì; tutti i 350 byte provengono dal file |
| KEYS export `@28+4` | `CBEXPORT.jcl:32`; taglia il campo definito in `CVEXPORT.cpy:16` e il successivo | Sì; usata come intervallo di byte originali |

La storia Git colloca attesi e inventari in `3850b38`, prima della colla in `488621b`. `177cefc` modifica soltanto i riferimenti dei `WHEN`: **273, 275, 277, 279, 281**, confermati in `app/cbl/CBIMPORT.cbl`. Non ho trovato valori attesi che ripetano un errore del contratto.

I conteggi locali coincidono con quelli della CI:

| Analisi | Locale e CI |
|---|---|
| data-contract | 69 righe `ok` |
| data-codec | 249 righe `ok`; 741 vettori, 6.656 casi esaustivi, 3.355 campi incompleti, 1.654 osservazioni |
| data-sentinelle | 2.792 prove negative superate, 98 non applicabili |
| data-fixtures | 62 prove negative; 68 righe `ok` complessive |

Nessuna modifica alle analisi importate, nessun nuovo prerequisito applicativo sull’host, percorso locale o segreto rilevato nel codice aggiunto. Nessun commit o push effettuato. Le risorse Docker `menb-val56-` sono state rimosse e la pulizia verificata; immagini e volumi condivisi non sono stati rimossi.