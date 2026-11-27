BOCCIATA

Manca una dipendenza statica reale. Inoltre ho ottenuto un **falso verde del comando completo** introducendo un errore nella colla di costruzione del grafo, senza alterare sorgente né output degli strumenti.

**(b) Criteri e prove eseguite**

Durate wall-clock. Timeout: 600 s per ogni esecuzione di inventory, 1200 s per `--all --check`. Comandi completi, esiti e durate sono nel registro delle esecuzioni (file locale del Validatore, non conservato).

| Criterio | Comando eseguito da me | Esito osservato | Durata |
|---|---|---|---:|
| Perimetro | `git diff --name-only origin/main...HEAD` | 48 file, tutti nelle quattro destinazioni ammesse; nessuna modifica a `legacy/` | <1 s |
| Prima rigenerazione | `./analysis/run.sh inventory` | Exit 0 | 128,51 s |
| Seconda rigenerazione | `./analysis/run.sh inventory` | Exit 0; `graph.json` e `inventario.md` identici alla prima esecuzione tramite `cmp` | 139,39 s |
| Controllo inventory | `./analysis/run.sh inventory --check` | Exit 0; passano anche le prove negative automatiche della PR | 146,99 s |
| Controllo complessivo | `./analysis/run.sh --all --check` | Exit 0: manifest, inventory, selftest e tools | 317,13 s |
| Schema, verificatore mio | `<file locale del Validatore> <file locale del Validatore>` | Schema Draft 2020-12 valido; grafo con zero errori usando `jsonschema` | 0,41 s |
| Conteggio indipendente mio | `python3 <file locale del Validatore>` | 46 JCL, **119 EXEC, 480 DD, 44 programmi, 25 transazioni** | 0,11 s |
| Confronto con attesi ricavati da me | `python3 <file locale del Validatore>` | Una differenza: CALL mancante in CSUTLDPY | 0,06 s¹ |
| Robustezza su fixture mie | `python3 <file locale del Validatore>`; `python3 <file locale del Validatore>` | Errori riprodotti su continuazioni, `DD DATA` e commenti | 0,08 / 0,04 s |
| Errore introdotto nella colla | `./analysis/run.sh inventory`, con mutazione temporanea di `build.py` | Exit 0; genera un bersaglio COPY sbagliato | 133,90 s |
| Controllo del risultato sbagliato | `./analysis/run.sh inventory --check`, stessa colla alterata | **Exit 0, «tutti i controlli superati»** | **162,65 s** |
| Integrità finale | `python3 <file locale del Validatore>` | Diff del working tree e dell’indice vuoti; grafo ripristinato; 329 file legacy con hash iniziali identici | 0,29 s |

¹ È il tempo del confronto automatico degli attesi scritti da me; il tempo della lettura manuale non è stato misurato separatamente.

`git status --short` finale mostra soltanto `?? .validazione/`, già presente all’avvio. Lo status interno del submodule è vuoto. Nessun commit o push.

Ho eseguito ciascuna delle seguenti mutazioni separatamente, ripristinando dopo ogni prova. La colonna del comando completo riguarda sempre `./analysis/run.sh inventory --check`; la verifica diretta esegue `glue/verify.py` in Docker sui grafi mutati.

| Mutazione mia | Comando completo: exit / durata | `verify.py` diretto: exit / durata |
|---|---:|---:|
| Una COPY rimossa da COCRDUPC | 1 / 97,28 s | 1 / 0,91 s |
| COPY di COCRDUPC spostata dalla riga 268 alla 272, contenente un’altra COPY | 1 / 99,89 s | **0 / 1,03 s** |
| Dataset TCATBALF di INTCALC cambiato in LOADLIB, anche nei campi DSN | 1 / 115,64 s | **0 / 1,06 s** |
| Due DD di COMBTRAN scambiate fra passi, conservando i conteggi per passo | 1 / 107,33 s | **0 / 0,95 s** |
| Solo FREEPLN di CREADB21 marcato `fonte: mapa`, con file ancora B | 1 / 101,06 s | 1 / 1,74 s |
| CCUP deviata verso COTRN02C | 1 / 94,03 s | 1 / 2,53 s |
| Dataset alterato nell’intermedio `out/cards.tsv` | 1 / 109,56 s | Non eseguita |

I sette controlli completi falliscono al confronto con il rigenerato. Questo verifica l’integrità degli output salvati. L’esperimento sulla colla dimostra invece che **un risultato rigenerato sbagliato può passare**.

Ulteriori verifiche dirette accettate erroneamente: CCUP→COTRN02C con `riga_programma=440` appartenente a CT02 (1,61 s), bersaglio COPY cambiato (1,72 s), WAITSTEP deviato da COBSWAIT a CBACT01C (1,38 s).

**(c) Oggetti verificati manualmente contro il grafo**

I percorsi seguenti sono relativi a `legacy/aws-mainframe-modernization-carddemo/app/`. Il numero dopo il nome indica la riga sorgente. Il confronto completo (file locale del Validatore, non conservato) conserva attesi e valori del grafo.

| Oggetto e sorgente | Dipendenze ricavate dal sorgente | Differenze |
|---|---|---|
| `cbl/COCRDUPC.cbl` | COPY: CVCRD01Y:268, COCOM01Y:272, DFHBMSCA:327, DFHAID:328, COTTL01Y:332, COCRDUP:334, CSDAT01Y:337, CSMSG01Y:340, CSMSG02Y:343, CSUSR01Y:346, CVACT02Y:353, CVCUS01Y:359, CSSTRPFY:1528. CALL: nessuna | Nessuna nel grafo originale |
| `cbl/COTRN02C.cbl` | COPY: COCOM01Y:71, COTRN02:82, COTTL01Y:84, CSDAT01Y:85, CSMSG01Y:86, CVTRA05Y:88, CVACT01Y:89, CVACT03Y:90, DFHAID:92, DFHBMSCA:93. CALL CSUTLDTC:393 e :413 | Nessuna |
| `cbl/CBACT04C.cbl` | COPY: CVTRA01Y:97, CVACT03Y:102, CVTRA02Y:107, CVACT01Y:112, CVTRA05Y:117. CALL CEE3ABD:632 | Nessuna |
| `cpy/CSUTLDPY.cpy` | COPY: nessuna. **CALL CSUTLDTC:293** | **CALL completamente assente** |
| `jcl/COMBTRAN.jcl` | STEP05R:22→SORT; STEP10:41→IDCAMS; 10 DD, dettagli sotto | Nessuna |
| `app-transaction-type-db2/jcl/CREADB21.jcl` | FREEPLN:40→IKJEFT01; CRCRDDB:52→IKJEFT01; LDTTYPE:64→IEFBR14; RUNTEP2:65→IKJEFT01; LDTCCAT:77→IKJEFT01. 30 DD, comprese 3 del job | Nessuna; fonte `schede` |
| `jcl/WAITSTEP.jcl` | WAIT:22→COBSWAIT; 3 DD, dettagli sotto | Nessuna |
| CCUP, `csd/CARDDEMO.CSD` | DEFINE TRANSACTION:367; PROGRAM(COCRDUPC):369 | Nessuna |
| CT02, stesso CSD | DEFINE TRANSACTION:439; PROGRAM(COTRN02C):440 | Nessuna |
| INTCALC, controllo aggiuntivo | STEP15:22→CBACT04C, `PARM='2022071800'`; 9 DD | Nessuna |
| CDV1, controllo dell’anomalia dichiarata | DEFINE TRANSACTION:388; PROGRAM(COCRDSEC):390; programma assente dal manifesto | Nodo `external` coerente |

I primi nove oggetti comprendono più di sei campioni diversi dagli attesi manuali dell’Esecutore. INTCALC e CDV1 sono controlli aggiuntivi. Nei **62 copybook del manifesto non ho trovato COPY attive annidate**; CSUTLDPY contiene invece la CALL omessa.

Per le DD sotto, `D` significa `AWS.M2.CARDDEMO.`, `S` significa `DISP=SHR`, `N` significa `DISP=(NEW,CATLG,DELETE)`, `O` significa `SYSOUT=*`, `I` significa dati in-stream. Per O e I non è scritto alcun DSN o DISP. Le righe indicano l’inizio della scheda, comprese le sue continuazioni.

| File / passo | Tutte le DD ricavate manualmente | Confronto col grafo |
|---|---|---|
| INTCALC / STEP15 | STEPLIB:23=`DLOADLIB/S`; SYSPRINT:25=O; SYSOUT:26=O; TCATBALF:27=`DTCATBALF.VSAM.KSDS/S`; XREFFILE:29=`DCARDXREF.VSAM.KSDS/S`; XREFFIL1:31=`DCARDXREF.VSAM.AIX.PATH/S`; ACCTFILE:33=`DACCTDATA.VSAM.KSDS/S`; DISCGRP:35=`DDISCGRP.VSAM.KSDS/S`; TRANSACT:37=`DSYSTRAN(+1)/N` | 9/9; GDG +1 corretto |
| COMBTRAN / STEP05R | SORTIN:23=`DTRANSACT.BKUP(0)/S`; concatenata senza nome:25=`DSYSTRAN(0)/S`; SYMNAMES:27=I; SYSIN:29=I; SYSOUT:32=O; SORTOUT:33=`DTRANSACT.COMBINED(+1)/N` | 6/6; generazioni corrette |
| COMBTRAN / STEP10 | SYSPRINT:42=O; TRANSACT:43=`DTRANSACT.COMBINED(+1)/S`; TRANVSAM:45=`DTRANSACT.VSAM.KSDS/S`; SYSIN:47=I | 4/4 |
| WAITSTEP / WAIT | STEPLIB:23=`DLOADLIB/S`; SYSOUT:24=O; SYSIN:25=I | 3/3 |
| CREADB21 / job | JOBLIB:32=`OEM.DB2.&DB2S..SDSNLOAD/S`; concatenata:33=stesso DSN/S; concatenata:34=`CEE.SCEERUN/S` | 3/3, dal job |
| CREADB21 / FREEPLN | STEPLIB:41=`OEM.DB2.DAZ1.SDSNEXIT/S`; concatenata:42=`OEMA.DB2.VERSIONA.SDSNLOAD/S`; SYSPRINT:43=O; SYSTSPRT:44=O; SYSUDUMP:45=O; SYSTSIN:46=`&LBNM..CNTL(DB2FREE)/S` | 6/6 |
| CREADB21 / CRCRDDB | STEPLIB:53=`OEM.DB2.&DB2S..RUNLIB.LOAD/S`; concatenata:54=`OEMA.DB2.VERSIONA.SDSNLOAD/S`; SYSTSPRT:55=O; SYSUDUMP:56=O; SYSPRINT:57=O; SYSTSIN:58=`&LBNM..CNTL(DB2TIAD1)/S`; SYSIN:59=`&LBNM..CNTL(DB2CREAT)/S` | 7/7; membri conservati |
| CREADB21 / LDTTYPE | Nessuna DD | 0/0 |
| CREADB21 / RUNTEP2 | STEPLIB:66 e concatenata:67 con gli stessi DSN/S di CRCRDDB; SYSTSPRT:68=O; SYSUDUMP:69=O; SYSPRINT:70=O; SYSTSIN:71=`&LBNM..CNTL(DB2TEP41)/S`; SYSIN:72=`&LBNM..CNTL(DB2LTTYP)/S` | 7/7 |
| CREADB21 / LDTCCAT | STEPLIB:78 e concatenata:79 con gli stessi DSN/S di CRCRDDB; SYSTSPRT:80=O; SYSUDUMP:81=O; SYSPRINT:82=O; SYSTSIN:83=`&LBNM..CNTL(DB2TEP41)/S`; SYSIN:84=`&LBNM..CNTL(DB2LTCAT)/S` | 7/7 |

Il conteggio mio dei CSD è: CARDDEMO **18**, CRDDEMO2 **3**, CRDDEMOD **2**, CRDDEMOM **2**. Le due procedure aggiungono 4 EXEC e 20 DD ai totali dei JCL: questo spiega i 123 passi e le 500 DD complessive del grafo.

Ho inoltre verificato sul sorgente:

- I tre copybook mai copiati: CSDB2RPY, CSDB2RWY, UNUSED1Y.
- **Otto** nomi COPY non risolti: CMQGMOV, CMQMDV, CMQODV, CMQPMOV, CMQTML, CMQV, DFHAID, DFHBMSCA. Le occorrenze coincidono con la tabella dell’inventario.
- I passi duplicati: `TRANREPT.jcl:23,37` e `DEFCUST.jcl:22,32`.
- Il testo spurio in `CREASTMT.JCL:90`; la dichiarazione REPROC e il PEND in `proc/TRANREPT.prc:1,79`.
- I quattro copybook con codice eseguibile: CSDB2RPY:23, CSSETATY:18, CSSTRPFY:21, CSUTLDPY:19.
- Le categorie dichiarate non mappate: esempi reali sono `COCRDUPC.cbl:370` per CICS, `COTRTUPC.cbl:282` per SQL, `CBPAUP0C.cbl:223` per DLI. I tipi esclusi hanno i conteggi dichiarati e nessun nodo; nessun file dei tipi mappati manca come nodo.

**(d) Rilievi e correzioni richieste**

1. **Bloccante — CALL statica nascosta in un copybook completamente omessa.**  
   Evidenza: `cpy/CSUTLDPY.cpy:293` contiene `CALL 'CSUTLDTC'`; `cbl/COACTUPC.cbl:4232` include quel copybook. Il grafo perde il percorso `COACTUPC → CSUTLDPY → CSUTLDTC`. La scansione del localizzatore riguarda soltanto `of_type("cobol")` (`analysis/inventory/glue/locate_calls.py:46`); anche il conteggio CALL esclude i copybook (`counts.py:82`). Lo schema impedisce direttamente una CALL da copybook (`docs/legacy-map/graph.schema.json:159`). Sul sorgente fisico ci sono **63 CALL letterali: 62 nei programmi e una nel copybook**, contro 62 mappate.  
   **Falso verde: sì, osservato sul ramo originale. Mappa: incompleta.**  
   Correzione: rappresentare la CALL con file/riga reali, estendere scansione, schema e conteggi ai copybook eseguibili e aggiungere una prova negativa sulla dipendenza mancante.

2. **Bloccante — I controlli accettano collegamenti sbagliati quando i conteggi restano invariati.**  
   Evidenza: `verify.py:147–156` verifica soprattutto la presenza della parola chiave; non lega COPY/CALL/EXEC/DD al relativo operando e contesto. Le DD sono confrontate numericamente (`verify.py:109–113`). Per il CSD si verificano separatamente la transazione e una riga PROGRAM, senza imporre lo stesso blocco DEFINE (`verify.py:150–151`).  
   Ho alterato temporaneamente **la colla**, facendo puntare la COPY di COCRDUPC:268 a CVACT01Y. `inventory` ha generato il risultato sbagliato e il successivo **`inventory --check` è passato integralmente**. Tutti gli intermedi erano identici al commit, incluso ProLeap che riportava correttamente CVCRD01Y: prova di integrità (file locale del Validatore, non conservato), log del falso verde (file locale del Validatore, non conservato).  
   **Falso verde: sì, dimostrato end-to-end. Mappa prodotta nell’esperimento: sbagliata.**  
   Correzione: confrontare anche bersagli, attributi e associazioni alle occorrenze prodotte dagli strumenti; verificare l’appartenenza delle DD al passo e del PROGRAM al blocco della transazione. Aggiungere mutazioni che conservino conteggi e parole chiave.

3. **Importante — Il secondo conteggio non soddisfa il requisito sulle continuazioni.**  
   Evidenza: `analysis/inventory/crosscheck.sh:10–11` richiede operando e parola chiave sulla stessa riga. Sulla mia fixture con `COPY` seguito da `CVACT01Y` a capo e `CALL` seguito da `'CSUTLDTC'` a capo, Python conta **1/1**, awk **0/0**. Questo contraddice il punto 6 della modifica della specifica.  
   **Falso verde: no per questa prova; produce un falso rosso. Mappa attuale: nessun errore attribuito a questo caso.**  
   Correzione: gestire le continuazioni anche nel secondo conteggio e verificarle con attesi espliciti. I casi COACTUPC e COTRTLIC attuali provano nomi tra apici, non operandi sulla riga successiva.

4. **Importante — Indipendenza semantica insufficiente e ripieghi fragili su dati in-stream e commenti.**  
   Python e awk leggono il sorgente senza leggere il grafo: questa indipendenza esiste. Condividono però la stessa regola errata dell’estrattore per terminare i dati in-stream su qualsiasi `//`: `cards.py:66–68`, `counts.py:56–58`, `crosscheck.sh:16`. Con `DD DATA` contenente una falsa EXEC e una falsa DD, **tutti e tre restituiscono 2 EXEC e 3 DD, mentre le schede effettive sono 1 EXEC e 2 DD**. L’accordo dei conteggi replica l’errore.  
   Inoltre `csd.py:22–25` prende PROGRAM anche da una riga commentata; nella mia fixture sceglie FAKE invece di REAL. Il localizzatore e il conteggio CALL considerano codice il testo dopo `*>`, producendo una CALL aggiuntiva nella fixture COBOL. I commenti JCL `//*` e le continuazioni con virgola provati separatamente vengono gestiti.  
   **Falso verde: possibile per estrazioni errate condivise; dimostrato l’accordo su valori sbagliati nelle fixture, non un ulteriore falso verde sul legacy attuale. Mappa attuale: nessun errore attribuito a questi formati, assenti nei casi cercati.**  
   Correzione: distinguere `DD *` da `DD DATA`, escludere correttamente i commenti e aggiungere prove con contenuto che assomigli a istruzioni. Se un formato eccede il ripiego ammesso, fallire esplicitamente e applicare `needs-spec-update`.

5. **Importante — Alcune affermazioni dell’inventario eccedono quanto è stato realmente cercato.**  
   `inventario.md:135–149` elenca programmi «senza job». Esistono invece riferimenti di esecuzione: CBPAUP0C in `CBPAUP0J.jcl:24–25`, PAUDBLOD in `LOADPADB.JCL:26–27`, DBUNLDGS in `UNLDGSAM.JCL:27`, PAUDBUNL in `UNLDPADB.JCL:39`, COBTUPDT nel `SYSTSIN` di `MNTTRDB2.jcl:30`. La tabella deriva dall’assenza di archi diretti, non dall’assenza di un job sorgente.  
   `inventario.md:215` dichiara zero CALL non letterali, mentre `app-transaction-type-db2/cpy/CSDB2RPY.cpy:57` contiene `CALL LIT-DSNTIAC`. Anche la dichiarazione PR di nove nomi COPY non risolti è errata: sono otto.  
   **Falso verde: sì per le affermazioni inesatte dell’inventario. Mappa: i collegamenti IMS/SQL citati restano nelle categorie escluse; la CALL statica persa è trattata nel rilievo 1.**  
   Correzione: qualificare la tabella come assenza di collegamenti diretti nel grafo, annotare i lanci esclusi e precisare il perimetro dei conteggi CALL. Correggere il numero nella descrizione PR.

6. **Minore — L’analisi invoca build sulle immagini condivise, contro la regola operativa.**  
   Evidenza da lettura: `analysis/inventory/lib.sh:40–42` chiama `build_image` per ProLeap, CMT e mapa; `analysis/lib/common.sh:35–37` esegue `docker build -q -t`. La specifica richiede di riusare queste immagini senza ricostruirle. Non ho dimostrato un cambiamento materiale delle immagini.  
   **Falso verde: no. Mappa: nessun errore dimostrato.**  
   Correzione: verificare la presenza delle immagini condivise e riusarle; costruire soltanto immagini proprie dell’issue.

I ripieghi letti restano estrattori/localizzatori entro l’eccezione autorizzata dalla specifica modificata: non ho trovato espansione di procedure, valutazione di condizioni o un parser generale scritto in proprio. La bocciatura deriva dalle omissioni e dai falsi verdi riprodotti.

Nel `CLAUDE.md` del clone manca la sezione «Fin dove arriva la sfiducia negli script». Ho applicato il limite espresso nel mandato: **nessuna prova richiede che uno strumento restituisca dati falsi ma ben formati**.