**BOCCIATA**

Validato lo SHA `5ee7956`. File fuori perimetro: **nessuno**, su 34 file modificati. Gli attesi preesistenti cambiano soltanto in `oracle/avvio/expected/COBSWAIT.txt`.

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| Build | `./oracle/run.sh build` | **0**, 27 artefatti |
| Routine | `./oracle/run.sh routines --check` | **0**, 126 prove negative e 2 controprove |
| Suite, prima corsa | `./oracle/run.sh --all --check` | **0**, nel clone pulito |
| Suite, seconda corsa consecutiva | `./oracle/run.sh --all --check` | **0** |
| Analisi | `./analysis/run.sh --all --check` | **0**, compreso `data-codec` |
| Pulizia | `git status --short` | Vuoto nel clone; nella cartella fornita rimane solo `.validazione/`, già presente inizialmente |
| Legacy | `git -C legacy/aws-mainframe-modernization-carddemo status --porcelain` | Vuoto; HEAD `59cc6c2fd7eb…` |
| Perimetro | `git diff --name-only origin/main...HEAD` | Solo file ammessi; rispettate anche le restrizioni sugli elenchi di build |
| CI | `gh pr view 52 --json number,url,headRefOid,statusCheckRollup,commits`; `gh run view 46075207975 --log` | `oracle-check`, `analysis-check`, `verify`, `smoke` verdi sullo SHA esaminato |

Conteggi identici nella [CI della PR](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46075207975) e in entrambe le corse locali:

| Passo | Negative | Controprove | Con file illeggibili |
|---|---:|---:|---:|
| build | 172 | 4 | 5 |
| abend | 7 | 0 | 0 |
| adattamenti | 54 | 0 | 1 |
| avviatore | 5 | 0 | 0 |
| avvio | 14 | 1 | 0 |
| dialetto | 3 | 1 | 0 |
| routines | 126 | 2 | 0 |
| segno | 5 | 0 | 0 |
| selftest | 3 | 0 | 0 |

Il confronto con la CI di `main` conserva tutte le 288 prove negative preesistenti, senza esiti cambiati.

Ho ricostruito il contratto da `app/asm/MVSWAIT.asm:19–28`, `app/maclib/ASMWAIT.mac:19`, `app/cbl/COBSWAIT.cbl:30–40` e `app/jcl/WAITSTEP.jcl:20–26`:

| Argomento | Legacy | Oracle richiesto |
|---|---|---|
| `00000000` | Intervallo ammesso, ritorno 0; trattamento temporale speciale non specificato nei documenti consultati | Nessuna attesa, diagnostica su stderr, ritorno 0 |
| `00000001`…`7FFFFFFF` | Attesa in centesimi di secondo, poi ritorno 0 | Nessuna attesa, diagnostica su stderr, ritorno 0 |
| `80000000`…`FFFFFFFF` | Abend `12F`, nessun ritorno | Diagnostica dell’arresto e codice 97 |

L’argomento è letto per riferimento e copiato in `BINLBL`, senza modificarlo; la scrittura nell’area di salvataggio è invece a `MVSWAIT.asm:25`. `COBSWAIT` legge otto caratteri; la scheda JCL richiede 3600 centesimi. Casi e attesi corrispondono a questa ricostruzione. Le citazioni corrispondono al [manuale IBM SA23-1370-40, capitolo 97, pp. 915–920](https://www.ibm.com/docs/en/SSLTBW_2.4.0/pdf/ieaa900_v2r4.pdf). Neppure la [guida SA23-1368-40, pp. 342–343](https://www.ibm.com/docs/en/SSLTBW_2.4.0/pdf/ieaa600_v2r4.pdf) specifica un ritardo minimo per zero.

Le sonde indipendenti hanno coperto `00000002`, `00000063`, `00000100`, `01020304`, `05F5E101`, `7FFFFFFE`, `7FFFFFFF`, `80000000`, `80000001`, `DEADBEEF`, `FFFFFFFF`: valori riportati corretti, stdout vuoto, codici 0/97; nei casi con ritorno, argomento e sentinelle adiacenti invariati.

Senza `--sysin`, rapporti e ambiente coincidono byte per byte con lo script di `origin/main` per `COBSWAIT`, `PARMECHO`, `CBACT01C`, `ABDUSING`, usando gli stessi moduli. File inesistente, percorso relativo e opzione ripetuta producono errore 2. File vuoto, senza fine riga, lungo e binario sono stati eseguiti verificando anche dimensione e SHA-256.

Git mostra attesi e previsioni in `e06d1e8`, prima dell’implementazione e delle osservazioni in `f6ec476`, senza successivi ritocchi agli attesi. Non può provare l’assenza di esecuzioni non committate. Le osservazioni sugli ingressi vuoti/non numerici e l’avvio di `COBSWAIT` sono dichiarate separatamente dalla parità.

1. **Bloccante — Un’attesa reale di un secondo produce un falso verde.**  
   **Evidenza:** `oracle/routines/mvswait-run.sh:20` imposta 3 secondi. Ho inserito nella copia della routine `CALL 'SYSTEM' USING Z'sleep 1'`, ricompilato ed eseguito l’intero `routines --check`: **codice 0**, comprese le prove negative. Misure interne al container: circa **1,02 secondi** per chiamata valida. [Log](</tmp/menb-val52-evidence/mutant-1s-check.log>).  
   **Schema generale:** il watchdog intercetta attese lunghe, ma non verifica l’assenza dell’attesa richiesta dalla specifica, che esige esplicitamente di respingere anche un secondo.  
   **Correzione richiesta:** controllo temporale capace di respingere un ritardo fisso di un secondo sull’artefatto reale, con relativa prova negativa; verificare anche gli altri lanci di `COBSWAIT`.  
   **Falso verde:** sì, dimostrato. **Riproduzione:** modifica del sorgente versionato in una copia e normale ricompilazione; nessun artefatto falsificato. **Correzione:** file versionati.

2. **Bloccante — SYSIN può essere sovrascritto dallo script prima di essere letto.**  
   **Evidenza:** in `oracle/esegui.sh:69–90` l’impronta precede le scritture dei file d’uscita. Con `--sysin /out/COBSWAIT.ambiente`, contenente `12349876\n`, lo script restituisce **0**, passa invece valore **0** alla routine e registra l’impronta dei nove byte originali. Il file d’ingresso viene sovrascritto. Riprodotto anche con `.stdout` e `.stderr`, poi rimossi dallo script. [Risultati](</tmp/menb-val52-evidence/probes.log>).  
   **Schema generale:** alias tra ingresso e file modificati dallo strumento; impronta e contenuto consumato non descrivono più gli stessi byte.  
   **Correzione richiesta:** proteggere l’ingresso prima delle operazioni distruttive, oppure rifiutare esplicitamente tutti gli alias interessati, inclusi quelli tramite collegamenti; aggiungere controprove.  
   **Falso verde/oracle infedele:** sì. **Riproduzione:** nessuna modifica versionata e nessun artefatto falsificato, basta un SYSIN regolare in uno dei percorsi accettati. **Correzione:** file versionati.

3. **Bloccante — Un’apertura fallita può diventare un rapporto riuscito con output residui.**  
   **Evidenza:** ho predisposto stdout/stderr autentici di un’esecuzione precedente, calcolato il vero SHA del nuovo SYSIN e cancellato quest’ultimo prima della redirezione a `oracle/esegui.sh:90`. Il programma non parte: compare `cannot open`. Lo script restituisce però **0** e scrive un rapporto con codice programma **2**, vecchio stderr e impronta del nuovo ingresso. [Controesempio](</tmp/menb-val52-evidence/race-real.log>).  
   **Schema generale:** errore della redirezione classificato come risultato del programma, combinato con temporanei residui. Non riguarda strumenti che restituiscono dati falsi.  
   **Correzione richiesta:** controllare separatamente l’apertura dell’ingresso, impedire il riuso dei temporanei e fallire come strumento senza produrre un rapporto corrente apparentemente valido.  
   **Falso verde/oracle infedele:** sì. **Riproduzione:** nessuna modifica versionata né falsificazione di output; servono residui autentici e la perdita del file d’ingresso. **Correzione:** file versionati.

4. **Importante — La prova automatica sul segno non isola il difetto dichiarato.**  
   **Evidenza:** `oracle/routines/mvswait-check.sh:231–237` sottrae `4294967296` da `WS-VALORE` prima del controllo del limite. Per `80000000` cambia quindi anche codice **97→0**, ramo diagnostico e ritorno al chiamante. Ho verificato che un confronto alterato per ignorare il meno continua a respingere questa variante per gli altri errori, mentre accetta una variante che cambia soltanto il segno stampato, mantenendo l’arresto 97.  
   **Schema generale:** mutazione con più violazioni; la prova può risultare verde senza dimostrare l’asserzione nominata.  
   **Correzione richiesta:** mutare soltanto la rappresentazione stampata, conservando classificazione, arresto e codice; riesaminare le altre mutazioni secondo lo stesso schema.  
   **Falso verde:** sì, della prova negativa specifica; non dimostrato nel confronto attuale dell’oracle. **Riproduzione:** copie del sorgente e della logica di confronto versionati; nessun output falsificato. **Correzione:** file versionati.

5. **Minore — Il nuovo caricamento dei casi rompe i percorsi del repository contenenti spazi.**  
   **Evidenza:** `oracle/routines/mvswait-run.sh:22,36` costruisce una lista di percorsi separata da spazi e usa `for f in $casi`. Con radice `/tmp/menb-val52 repo`, termina con **1**, `elenco dei casi assente: /tmp/menb-val52`. La parte preesistente di `routines`, nello stesso percorso, termina con **0**.  
   **Schema generale:** suddivisione di nomi di file tramite espansione non quotata.  
   **Correzione richiesta:** conservare distinti i percorsi, anche per i valori predefiniti, e aggiungere una prova con radice contenente spazi.  
   **Falso verde/oracle infedele:** no, fallisce esplicitamente. **Riproduzione:** nessuna modifica versionata o falsificazione di artefatti. **Correzione:** file versionati.

Le altre mutazioni indipendenti richieste vengono rilevate, compresa l’alterazione dell’atteso `3600→3601`. Nessuna correzione o commit effettuato. Sorgenti originali e legacy invariati; rimosse le dieci immagini e i due volumi `menb-val52-`, senza rimuovere risorse condivise.