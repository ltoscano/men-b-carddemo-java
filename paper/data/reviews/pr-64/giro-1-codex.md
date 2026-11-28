BOCCIATA

| Criterio | Comando/verifica eseguita | Esito osservato |
|---|---|---|
| Preparazione | `./oracle/run.sh build` | **0**, 29 programmi compilati |
| Preparazione | `./oracle/run.sh dati` | **0**, 50 conti caricati e riletti |
| 1 | `./oracle/run.sh golden` | **0**, nessuna differenza nei versionati |
| 1 | `./oracle/run.sh golden --check` | **0**, 101 prove negative e 5 controprove |
| 2 | `./oracle/run.sh --all --check` | **0**, inclusa la seconda `golden --check` |
| 2 | `./analysis/run.sh --all --check` | **0** |
| 3 | Confronto automatico dei log locali con la CI sullo stesso SHA | Tutti gli 11 passi coincidono: **607 prove negative, 27 controprove, 6 prove con file illeggibili**. [Conteggi per passo](/private/tmp/menb-val64-logs/counts.csv) |
| 4 | Rigenerazione e verifica del documento | Identico al versionato; contiene però l’affermazione falsa del rilievo 2 |
| 5 | Diff, `git status --short`, stato del submodule | Nessun file fuori perimetro; nella build cambia soltanto `PASSI`. Legacy e attesi preesistenti invariati. Rimane soltanto `?? .validazione/`, presente all’avvio |
| 6 | Lettura dei check GitHub sullo SHA `5f2132658baae82a7bb57c867532dea5342f9bf9` | Tutti verdi, compresi [oracle](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46113053893) e [analysis](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46113053934) |
| 7 | Storia Git di attesi e tabelle | Attesi presenti in `64c1ee4` e mai modificati successivamente. `console.tsv` riceve in `6f07a9c` una modifica descrittiva alla motivazione di `VBRC-REC1`; la classe resta `a`. Le correzioni sono introdotte dopo il fermo dichiarato |

1. **Bloccante — I riferimenti finali VB e console possono essere sbagliati mentre tutti i controlli di generazione passano.**

   `oracle/golden/verificatore.sh:144–155` verifica il **VBRCFILE fisico**, senza leggere `VBRCFILE.riferimento.txt`. `coerenza.sh:42–55` confronta invece il riferimento con `VBRCFILE.logici.txt`, prodotto dallo stesso estrattore usato nella generazione. Analogamente, il verificatore controlla la console nel rapporto, senza leggere `console.riferimento.txt`.

   Ho sostituito temporaneamente l’estrattore di progetto con una variante che cambia il **byte 12 del record logico 70**, conto `00000000035`, da **`30` a `39`**, lasciando invariato il fisico: saldo da **166,00 a 9.000.000.166,00**. I controlli 2, 3, 4, coerenza e separazione passano; `run.sh` **pubblica il riferimento infedele ed esce con 0**, in entrambi gli scenari. [Log](/private/tmp/menb-val64-logs/wrong-vb.log)

   Una variante temporanea di `maschera.sh` cambia nella console di riferimento il primo conto da `00000000001` a `99999999999`: anche questa generazione **pubblica ed esce con 0**. [Log](/private/tmp/menb-val64-logs/wrong-console.log)

   **Schema generale:** verifica del dato precedente alla trasformazione, anziché del riferimento finale; gli attesi a mano coprono soltanto un campione.

   **Correzione richiesta:** verificare indipendentemente tutti i riferimenti finali, compresi contenuto, lunghezze, numerazione e ordine dei record VB e righe/marcature della console. Aggiungere mutazioni su conti non campionati.

   **Falso verde: sì. Golden infedele: sì, dimostrato.** Per il verde del controllo 4 basta falsificare gli artefatti generati; la pubblicazione infedele è stata dimostrata alterando temporaneamente gli script di progetto. La correzione richiede file versionati.

2. **Importante — L’errore di lettura dichiarato “non provocabile” è raggiungibile senza modificare il programma.**

   Basta copiare `oracle/dati/out/ACCTFILE.dat` e cambiare, nella copia, il byte allo **scostamento 8224, da `80` a `00`**. Eseguendo il normale `CBACT01C` con `oracle/esegui.sh` ho ottenuto:

   ```text
   ERROR READING ACCOUNT FILE
   FILE STATUS IS: NNNN0043
   ABENDING PROGRAM
   MENB-ORACLE CEE3ABD: ARRESTO ANOMALO ABCODE=+0000000999 TIMING=+0000000000
   ```

   Codice del programma: **99**. Il ramo corrisponde a `app/cbl/CBACT01C.cbl:192–195`; gli argomenti sono quelli delle righe 406–410. [Rapporto](/private/tmp/menb-val64-logs/read-error-confirm.log)

   Ho verificato anche la propagazione attraverso il passo, con selezione temporanea del DD corrotto per il programma: fallimento del passo, risultato precedente rimosso, nessun golden pubblicato. [Log](/private/tmp/menb-val64-logs/actual-read-error.log)

   Sono quindi false le affermazioni in `oracle/README.md:250`, `documento.sh:223` e documento generato:215.

   **Schema generale:** alcuni tentativi non riusciti vengono trasformati in una dichiarazione generale di impossibilità, omettendo una prova obbligatoria raggiungibile.

   **Correzione richiesta:** aggiungere la prova del ramo di lettura con diagnostica, 999/0, codice 99 e mancata pubblicazione; correggere README, generatore del documento e documento.

   **Falso verde sulla copertura: sì. Golden regolari infedeli: non dimostrati da questo difetto.** La riproduzione altera soltanto un DB generato; la correzione richiede file versionati.

3. **Importante — `check.sh` perde esiti non zero nelle sostituzioni di comando.**

   Ho eseguito isolatamente i blocchi reali dello script, con `set -euo pipefail`:

   - Alla riga **139**, `cat "$tmp/n6"` stampa realmente `3` ma restituisce **42**: il controllo 6 annuncia successo e il blocco termina con **0**. [Prova](/private/tmp/menb-val64-logs/check6-lost-status.log)
   - Alla riga **52**, `wc` esegue il lavoro e restituisce **42**: `c1` stampa comunque “file identici byte per byte” e restituisce **0**. [Prova](/private/tmp/menb-val64-logs/check1-lost-status.log)

   Lo stesso schema compare nel messaggio con `$(awk …)` alla riga 346.

   **Schema generale:** l’esito della sostituzione viene coperto da quello di `[` oppure `echo`/`log`. `pipefail` non propaga quell’errore al comando esterno.

   **Correzione richiesta:** acquisire e controllare separatamente questi risultati; cercare lo schema in tutti gli script nuovi e aggiungere prove sugli involucri dei controlli sull’host.

   **Falso verde operativo: sì. Golden infedele diretto: non dimostrato.** Le prove non modificano versionati né golden: iniettano esiti 42 dopo il lavoro reale. La correzione richiede `check.sh` e relativi test versionati.

4. **Importante — Il lettore VB indipendente accetta byte malformati come zero.**

   In `verificatore.sh:134` i token di `od` vengono acquisiti senza la verifica di appartenenza a `VAL` presente invece per l’ingresso alla riga 131. Alla riga 147, una chiave inesistente della tabella AWK viene convertita numericamente in zero.

   Ho fatto restituire a `od` il token malformato **`zz`** nel primo byte dell’intestazione VB: il controllo 4 termina con **0**. Ho poi cambiato realmente quel byte del fisico da `00` a `01`: con `od` normale il controllo fallisce con **4**; con quel byte reso `zz` dal lettore, torna a passare con **0**. [Prova](/private/tmp/menb-val64-logs/malformed-header.log)

   **Schema generale:** conversione numerica di token non validati, con ripiego implicito a zero. È una risposta malformata, non un dato falso ma ben formato.

   **Correzione richiesta:** validare ogni token prima di usarlo, in tutte le letture del verificatore, e aggiungere una prova negativa autonoma sul flusso VB.

   **Falso verde sull’integrità del fisico: sì. Golden logico infedele diretto: non dimostrato.** La prova usa una copia generata e un lettore temporaneo; la correzione richiede codice e test versionati.

5. **Minore — Eccezione alla restrizione aggiuntiva sui `DISPLAY` di gruppo.**

   `console.tsv:34` classifica come riferimento `DISPLAY 'VBRC-REC1:' VBRC-REC1`, benché `VBRC-REC1` sia un gruppo (`CBACT01C.cbl:123–125,283`). La motivazione cita una decisione dell’Approvatore; resta uno scostamento dal vincolo aggiuntivo di questo mandato, che esclude i `DISPLAY` di gruppo.

   **Correzione richiesta:** spostare la riga fra le osservazioni e rigenerare i riferimenti, oppure risolvere esplicitamente il contrasto con il mandato.

   **Non ho dimostrato differenze di formato per questo gruppo di 12 byte, né un golden infedele.** È uno scostamento di classificazione. La correzione coinvolge tabella e riferimenti versionati; non occorre falsificare artefatti per rilevarlo.

Ho ricostruito da zero **tutti i 100 conti** dei due scenari, superando gli otto richiesti per `esempio`: 107 byte OUTFILE, 110 ARRYFILE e record VB di 12/39 byte. **Zero differenze nei 26.600 byte determinati** dei riferimenti attuali. [Record ricostruiti](/private/tmp/menb-val64-logs/independent-records.json)

Le posizioni 77–78 sono giustificate da `CODATECN.cpy:39–51`, `COBDATFT.asm:51–53` e `CBACT01C.cbl:223–233`, coerentemente con IBM [VALUE clause](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=entry-value-clause). Non ho individuato ulteriori posizioni non determinate nei due scenari regolari: inizializzazione dell’array a riga 169, copertura completa di VBRC-REC2 alle righe 277–282, lunghezze effettivamente scritte alle righe 288–305. Il debito non zero resta soltanto osservazione, coerentemente con l’indisponibilità dell’area dopo WRITE descritta da IBM in [Common processing facilities](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=operations-common-processing-facilities).

Ho verificato IBM **INITIALIZE statement rules**, regola 2 — “ZERO is the implied sending item…” — e **Sign representation**, sezioni NUMPROC. La sonda compilata nell’oracle produce **`30` con INITIALIZE**, **`7B` con MOVE ZERO**, e **`0C` per lo zero COMP-3**. Non sono emerse altre correzioni necessarie nei dati di riferimento. Fonti: [INITIALIZE](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=statement-initialize-rules), [Sign representation](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=arithmetic-sign-representation-zoned-packed-decimal-data). Ho controllato anche [DISPSIGN](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=options-dispsign) e [DISPLAY](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statements-display-statement).

Le mie altre mutazioni sono state respinte: C→F nel packed, `7B`→`30` ai byte 80/99, limiti scambiati, mese/giorno scambiati, 1005→1050, saldo negativo reso positivo, record aggiunto o scambiato. Le alterazioni concordi golden/atteso passano il controllo 3 e falliscono il 4. Respinti anche tabella correzioni vuota, maschera aggiuntiva, oracle già a `7B`, scenario sbagliato realmente eseguito, DB vecchio e variante COBDATFT realmente caricata. Byte order VB inverso, ultimo record perso e divisione 39→12+27 sono respinti. [Esiti delle mutazioni](/private/tmp/menb-val64-logs/mutations.json)

Ho contato **505 invocazioni** e iniettato **15 fallimenti**, tutti rilevati, compresi `rm@19` in `maschera.sh` e comandi di `documento.sh`. [Esiti](/private/tmp/menb-val64-logs/injections.json) La prova con tmpfs pieno dà stato **34**, CEE3ABD **999/0**, codice **99**, nessuna pubblicazione e file parziali di **107/110/0 byte**. Considero accettabile la rimozione preventiva documentata dei risultati come comportamento che impedisce il riuso dei residui; dopo un errore i versionati restano da ripristinare con Git.

Nessuna modifica finale ai file versionati, nessun commit. Nessun container o volume Docker della validazione rimasto; risorse condivise non rimosse.