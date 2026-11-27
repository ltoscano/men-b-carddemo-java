BOCCIATA

Validato lo SHA `96e384c` in un clone pulito. **File fuori perimetro: nessuno** sui 35 modificati. Nessuna modifica a `legacy/` o `analysis/`.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Build | `./oracle/run.sh build` | **0**: 26 programmi, di cui 12 legacy, 4 stub e 10 programmi di prova |
| Adattamenti | `./oracle/run.sh adattamenti --check` | **0**: tutte le **41 prove negative** dichiarate eseguite |
| Script eseguibili | `test -x oracle/adattamenti/run.sh && test -x oracle/adattamenti/check.sh && test -x oracle/adattamenti/deps` | **0** |
| Controlli completi, prima corsa | `./oracle/run.sh --all --check` | **0** |
| Controlli completi, seconda corsa consecutiva | `./oracle/run.sh --all --check` | **0** |
| Pulizia | `git status --short`; `git -C legacy/aws-mainframe-modernization-carddemo status --short` | Entrambi vuoti nel clone. Nella cartella ricevuta resta soltanto `.validazione/`, già presente inizialmente |
| Perimetro | `git diff --name-only origin/main...HEAD` | Solo file ammessi |
| Analisi | `./analysis/run.sh --all --check` | **0** |
| CI | `gh api repos/ltoscano/men-b-carddemo-java/commits/96e384c/check-runs` con filtro sui risultati | Sei risultati completati con `success`: `verify`, `smoke`, `analysis-check`, per push e PR |

I log delle due corse sono disponibili: [prima](file locale del Validatore, non conservato), [seconda](file locale del Validatore, non conservato). Il [log di adattamenti](file locale del Validatore, non conservato) riporta singolarmente le 41 prove negative.

Ho eseguito anche queste mutazioni indipendenti, su copie:

| Mutazione | Esito |
|---|---|
| Secondo movimento attribuito alla carta `0683586198171516` | Verifica manuale **1**, 37 differenze; provenienza **1** |
| Terzo e quarto movimento d’ingresso scambiati | Caricamento **1**, stato COBOL `21` |
| Ordine dei due movimenti scambiato negli output testo e HTML | Verifica manuale **1**, 12 differenze |
| `ALTER` alla riga 306 reindirizzato a `8400-ACCTFILE-OPEN` | Programma termina con **99**, `ERROR READING CUSTFILE`, stato `47`; controllo **1** |
| Riga 269 lasciata non commentata | Controllo copie **1**: 22 byte diversi anziché 23 |
| Espansione a 8 colonne della sola riga 9 di `CUSTREC` | Controllo **1**: identità violata e testo oltre colonna 72 |
| Caricatore che altera il primo carattere del nome | Caricamento **1**, differenza in posizione 10; `CBSTM03A` non viene eseguito |
| Totale atteso cambiato da 136,00 a 137,00 | Verifica manuale **1** |

Per i fatti sul legacy, i riferimenti seguenti sono relativi a `legacy/aws-mainframe-modernization-carddemo/`.

- L’espansione indipendente con Python `bytes.expandtabs(4)` coincide con la copia generata. Ho ricostruito dalle `PIC` i 19 campi di `app/cpy/CUSTREC.cpy:5–23`: 500 byte, posizioni e lunghezze coincidenti con l’atteso.
- Originale e copia di `CBSTM03A.CBL` hanno 924 righe e differiscono soltanto nei 23 indicatori di colonna 7 previsti. La ricerca dei dati z/OS trova esclusivamente dichiarazioni alle righe 235–260 e usi alle 266–291.
- Gli argomenti di compilazione e le dipendenze confermano che soltanto `CBSTM03A` usa la cartella adattata; `CBSTM03B` resta compilato dall’originale.
- Ho ricostruito tutti i **72 campi dinamici**. Per esempio: Aniya Alba Von; `1588 Nienow Cape`, `Suite 187`, `New OR USA 04257`; conto `00000000050`, saldo +492,00, FICO 623; movimenti `0000000058866561`, “Purchase at Blick-Rippin”, +183,88 e `0000000577826814`, “Return item at DuBuque, Wuckert and Mraz”, −47,88; totale +136,00. Derivazione: `CUSTREC.cpy:5–22`, `CVACT01Y.cpy:5–7`, `CBSTM03A.CBL:462–485`, `676–716`, `429–434`. Coincide con gli attesi.
- Le quattro trasformazioni delle righe 21, 184, 24 e 87 di `dailytran.txt` coincidono con `CREASTMT.JCL:53–54`, incluso il riempimento dichiarato.
- `verifica-a-mano.tsv` è nel commit `15f6c08`, invariato successivamente; gli output registrati vengono aggiunti in `6ece30b`. Git dimostra questo ordine, non l’orario della prima esecuzione.
- Dichiarare le righe `implicit CLOSE` e il loro ordine come **osservazioni di libcob** è corretto: non sono istruzioni del sorgente COBOL né una garanzia di comportamento z/OS.

I rilievi sono:

1. **Bloccante — La verifica manuale accetta copertura incompleta e metadati malformati.**  
   Evidenza: `oracle/adattamenti/verifica-uscite.sh:28–54` controlla soltanto che esista almeno una riga; non verifica copertura, unicità o sintassi rigorosa dei metadati. Eliminando la riga del FICO HTML del terzo estratto, **l’intero `adattamenti --check` termina ancora con 0**, dichiarando 116 valori e 71 campi: [riproduzione](file locale del Validatore, non conservato). Il controllo isolato accetta anche una sola riga, 117 duplicati dello stesso marcatore e una lunghezza `75junk`. Eliminando le verifiche FICO e alterando gli output a `999`, restituisce 0.  
   **Schema del difetto:** un insieme parziale o duplicato viene trattato come verifica completa.  
   **Correzione richiesta:** validare schema, tipi numerici, unicità e presenza di tutti i campi richiesti in entrambi gli output; aggiungere controprove per omissioni, duplicazioni e metadati malformati. Il solo conteggio totale non basta.  
   **Falso verde: sì. Oracle infedele: possibile**, perché un campo sbagliato registrato nell’output può perdere la verifica indipendente richiesta.

2. **Importante — La verifica manuale ignora una parte del file dopo `0x01`.**  
   Evidenza: `verifica-uscite.sh:20–25` imposta `RS="\001"` e legge soltanto il primo segmento. Appendendo `0x01GARBAGE` a entrambi gli output, il controllo restituisce **0**, continuando a dichiarare 61 e 236 record: [riproduzione](file locale del Validatore, non conservato).  
   **Schema del difetto:** la lunghezza verificata è quella di un prefisso, non del file completo.  
   **Correzione richiesta:** verificare la dimensione reale e consumare integralmente l’input, oppure rifiutare esplicitamente il separatore; aggiungere controprove con byte aggiuntivi e separatori interni.  
   **Falso verde: sì, nel controllo indipendente.** Il confronto integrale con `cmp` oggi intercetta questa mutazione; **non ho dimostrato un falso verde del comando completo con questa sola alterazione**.

3. **Importante — Il calcolo dell’impronta nasconde errori reali di lettura degli artefatti.**  
   Evidenza: `oracle/lib.sh:215–217` inserisce `git hash-object` dentro gli argomenti di `printf`, perdendone l’esito. Con una copia di `CUSTREC.cpy` resa illeggibile mediante permessi, Git stampa `Permission denied`, ma `artifacts_hash` e **`build_stamp` restituiscono 0** e producono un’impronta. Due contenuti diversi, entrambi illeggibili, producono lo stesso hash: [riproduzione](file locale del Validatore, non conservato). Nessuno strumento è stato sostituito con risposte false.  
   **Schema del difetto:** una sostituzione di comando fallita viene mascherata dal successo del comando esterno; lo stesso problema riguarda l’enumerazione nei cicli.  
   **Correzione richiesta:** controllare esplicitamente l’esito di ogni hash e dell’enumerazione, propagando il fallimento fino alla build e alla verifica dell’impronta.  
   **Falso verde: sì, nel calcolo dell’impronta. Oracle infedele: possibile**, se un’impronta parziale viene accettata come completa.

4. **Minore — Prefisso dei temporanei non conforme alla specifica.**  
   Evidenza: `verifica-copie.sh:37`, `verifica-carico.sh:17` e `origine.sh:18` creano directory `/tmp/verifica-copie.*`, `/tmp/verifica-carico.*` e `/tmp/origine.*`, mentre la specifica prescrive `issue25-` per i temporanei fuori repository.  
   **Schema del difetto:** il vincolo di denominazione non è applicato ai temporanei nel container.  
   **Correzione richiesta:** uniformare i tre prefissi.  
   **Falso verde: no. Oracle infedele: no.**

Tutte le modifiche di prova sono state ripristinate. Nessun commit. Risorse temporanee `menb-val44-*` rimosse; immagini e volumi condivisi non rimossi.