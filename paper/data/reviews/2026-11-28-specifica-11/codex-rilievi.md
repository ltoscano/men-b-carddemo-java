I percorsi `app/…` qui sotto sono relativi a `legacy/aws-mainframe-modernization-carddemo/`.

1. **Bloccante — I controlli non verificano che gli attesi descrivano il COBOL.**  
   **Evidenza:** `.contestazione/11.md:29–34` richiede schema, riferimenti esistenti, copertura dichiarata e presenza dei comandi. Una matrice con messaggi scambiati, destinazioni amministratore/utente invertite o una lettura aggiuntiva può soddisfare questi controlli. Il conteggio indipendente verifica quantità, non comportamento. Il riferimento batch dispone invece di attesi manuali e di una seconda derivazione degli esiti (`oracle/golden/readacct/attesi-a-mano.tsv:1–25`, `oracle/golden/verificatore.sh:1–37`).

   **Correzione proposta:** richiedere un confronto semantico indipendente, con prove negative che alterino messaggio, chiave, destinazione, sequenza dei comandi e maschere. Per questo programma è realisticamente circoscrivibile una seconda via: copia generata del sorgente, sostituzione dei dieci blocchi CICS con adattatori minimi, ingressi controllati per `RECEIVE`, `READ`, `ASSIGN`, e arresto della prova su `RETURN`/`XCTL`. GnuCOBOL eseguirebbe le decisioni originali, senza riscriverle. Occorrono definizioni minime dei simboli CICS mancanti e un controllo delle trasformazioni ammesse: l’originale non compila direttamente (`analysis/tools/out/gnucobol/log/COSGN00C.log:1–45`). Tutto può stare in `analysis/behavior/`. Questa via verificherebbe la logica COBOL condizionata agli adattatori, non il runtime BMS; gli indeterminati non devono diventare gli zeri iniziali dell’oracle (`oracle/README.md:280`).

2. **Bloccante — COMMAREA ricevuta e COMMAREA di lavoro sono confuse nel modello d’ingresso.**  
   **Evidenza:** `.contestazione/11.md:16–17` parla genericamente di COMMAREA in ingresso e uscita. Ma `COCOM01Y` è in `WORKING-STORAGE` (`COSGN00C.cbl:48`), mentre `DFHCOMMAREA` è un’area distinta nella `LINKAGE SECTION` (`65–67`). L’intera procedura non copia né legge quest’ultima: usa soltanto `EIBCALEN` come discriminante (`80`). I campi della COMMAREA di lavoro non hanno `VALUE` (`COCOM01Y.cpy:19–44`).

   **Correzione proposta:** distinguere esplicitamente area ricevuta, area di lavoro e area trasmessa. Vietare attesi che conservino automaticamente i campi ricevuti. Richiedere un controesempio con due COMMAREA ricevute diverse ma stessa lunghezza non nulla: il contenuto ricevuto non deve cambiare la logica del programma. Anche una lunghezza positiva diversa da 160 entra nel ramo di rientro: il sorgente non verifica la lunghezza attesa.

3. **Bloccante — Manca un contratto verificabile delle transizioni pseudo-conversazionali.**  
   **Evidenza:** con `EIBCALEN = 0` il programma visualizza la schermata senza esaminare `EIBAID` (`COSGN00C.cbl:80–96`), quindi anche F3 al primo ingresso non esegue l’uscita. Il normale `RETURN` specifica `CC00` e 160 byte di COMMAREA (`98–102`; contratto `COCOM01Y.CARDDEMO-COMMAREA.tsv:2`). F3 esegue invece `SEND TEXT` e `RETURN` senza opzioni (`164–172`). Il trasferimento tra task riguarda la COMMAREA esplicitamente trasmessa, non tutta la memoria di lavoro: [regole IBM sulla COMMAREA](https://www.ibm.com/docs/en/cics-ts/6.x?topic=programs-commarea).

   **Correzione proposta:** prevedere scenari a più invii, distinguendo memoria del task, stato del terminale e COMMAREA trasportata. Richiedere almeno ingresso iniziale → errore → nuovo invio e ingresso iniziale → F3. Specificare nuova attivazione, lunghezza ricevuta e assenza di persistenza implicita della mappa simbolica. Il solo elenco di casi indipendenti non verifica questo comportamento.

4. **Bloccante — Il contenuto trasmesso dopo l’accesso riuscito non è vincolato abbastanza.**  
   **Evidenza:** `COSGN00C.cbl:224–239` assegna soltanto provenienza `CC00`/`COSGN00C`, utente normalizzato, tipo letto dal record e contesto zero. Non assegna destinazione, cliente, conto, carta o ultima mappa. Solo il tipo esattamente `'A'` seleziona `COADM01C`; qualunque altro valore seleziona `COMEN01C` (`COCOM01Y.cpy:26–31`). Non esiste un controllo che ammetta esclusivamente `'U'`.

   **Correzione proposta:** fissare gli attesi dei cinque campi assegnati e classificare separatamente tutti gli altri byte. Aggiungere un tipo diverso sia da `'A'` sia da `'U'`. Il bersaglio va registrato come programma di un `XCTL`, senza inventare valorizzazioni dei campi `CDEMO-TO-*` o l’avvio di una nuova transazione. L’omissione di `LENGTH` negli `XCTL` va trattata con il default documentato del traduttore, non interpretata come COMMAREA assente.

5. **Bloccante — Il conteggio di `IF`/`EVALUATE`/`WHEN` non ricostruisce i percorsi.**  
   **Evidenza:** il programma contiene quattro `IF` (`80`, `138`, `223`, `230`), tre `EVALUATE` (`85`, `117`, `221`) e nove `WHEN`, inclusi tre `WHEN OTHER`. L’`IF` di riga 138 ha un’alternativa falsa implicita. Le condizioni di righe 118 e 123 contengono ciascuna due confronti. Il conteggio richiesto da `.contestazione/11.md:30` non controlla associazioni, priorità o continuazioni.

   Inoltre, F3 termina a riga 171 e un `XCTL` riuscito termina l’esecuzione di questo programma: non seguono il `RETURN` di riga 98. Il programma cedente viene rilasciato dal [comando XCTL](https://www.ibm.com/docs/en/cics-ts/6.x?topic=summary-xctl).

   **Correzione proposta:** verificare una tabella di controllo con alternative esplicite, complementi dei `WHEN OTHER`, continuazioni e nodi terminali. Richiedere tracce ordinate complete, con assenza dei comandi vietati dopo un trasferimento terminale. I diciassette esiti strutturali dei quattro `IF` e dei nove `WHEN` sono un controllo supplementare, non una prova sufficiente.

6. **Bloccante — Una “risposta simulata” di `RECEIVE` non determina l’ingresso effettivo della logica.**  
   **Evidenza:** `RECEIVE MAP` scrive `RESP` e `RESP2` (`COSGN00C.cbl:110–115`), ma il programma non li verifica prima di leggere `USERIDI` e `PASSWDI` (`117–136`). Successivamente `READ` sovrascrive le stesse variabili (`217–218`). Un errore di ricezione non seleziona quindi automaticamente un ramo d’errore applicativo. L’uso di `RESP` impedisce la gestione predefinita delle condizioni: [documentazione IBM](https://www.ibm.com/docs/en/cics-ts/5.5.0?topic=conditions-handling-exception-by-inline-code).

   **Correzione proposta:** associare a ogni risposta simulata anche gli effetti sulle aree dati: byte scritti, conservati o indeterminati. Distinguere risultati del runtime documentati da ingressi sintetici al confine della mappa simbolica. Richiedere un caso di ricezione non normale che dimostri l’assenza del controllo su `RESP`, senza inventare un messaggio “errore CICS” che il programma non produce.

7. **Importante — Il perimetro delle condizioni CICS e delle assunzioni ambientali resta aperto.**  
   **Evidenza:** `.contestazione/11.md:16` richiede risposte simulate solo per comandi con `RESP`; `SEND`, `ASSIGN`, `RETURN` e `XCTL` ne sono privi. Non esistono `HANDLE CONDITION`, `HANDLE AID` o `HANDLE ABEND` in questo programma. L’inventario dichiara esplicitamente di non descrivere gli effetti di queste opzioni (`inventario-cics.md:474`).

   La CSD collega `CC00` a `COSGN00C`, con `PROFILE(DFHCICST)` e `STORAGECLEAR(NO)` (`app/csd/CARDDEMO.CSD:378–387`), ma non definisce quel profilo o un terminale. La procedura di compilazione è un esempio da adattare all’installazione (`samples/proc/BUILDONL.prc:19–22`, `39–40`).

   **Correzione proposta:** fissare il profilo minimo: ingresso come programma iniziale di `CC00`, terminale compatibile, risorse disponibili, condizioni normali assunte e condizioni eccezionali incluse o escluse con fonte. Per queste ultime distinguere comando richiesto, effetto completato e arresto del runtime. Non serve un emulatore generale, ma non si può lasciare ogni esecutore libero di assumere che tutti i comandi ritornino normalmente.

8. **Bloccante — “Campi e attributi della mappa” confonde memoria simbolica e schermata.**  
   **Evidenza:** `COSGN0AO REDEFINES COSGN0AI` (`COSGN00.CPY:85`): dati ricevuti e dati inviati condividono memoria. Solo il primo ingresso riempie l’area con `LOW-VALUES` (`COSGN00C.cbl:81`). Nei normali errori dopo `RECEIVE`, utente e password non vengono cancellati prima di `SEND MAP ... ERASE CURSOR` (`149–157`).

   La BMS definisce utente modificabile con `IC`, password modificabile ma `DRK`, entrambi `FSET`, e password iniziale `'________'` (`COSGN00.bms:156–180`). `ERASE` agisce sul buffer del dispositivo, non cancella gli operandi COBOL: [controlli SEND MAP](https://www.ibm.com/docs/en/cics-ts/6.x?topic=command-send-map-control-options).

   **Correzione proposta:** separare snapshot dei byte inviati, proprietà della mappa fisica ed effetto sul terminale sotto assunzioni documentate. Specificare `L/F/A`, attributi estesi, `LOW-VALUES` contro spazi e cursore simbolico. Vietare deduzioni come “ERASE azzera la password in memoria”. Per i tasti non previsti non vengono eseguiti né `RECEIVE` né l’inizializzazione della mappa: non è lecito aspettarsi i valori conservati dal task precedente.

9. **Bloccante — Mancano casi che distinguano il confronto COBOL dalle normali convenzioni di autenticazione.**  
   **Evidenza:** mappa, variabili di lavoro, chiave utente e password nel record sono tutti campi di otto caratteri (`COSGN00.CPY:67–78`, `COSGN00C.cbl:45–46`, `CSUSR01Y.cpy:18–22`). Il programma applica `UPPER-CASE` sia all’utente sia alla password ricevuti (`132–136`), ma non alla password archiviata (`223`). Non esegue `TRIM`. Il record viene recuperato con chiave lunga otto byte (`211–219`); non segue un confronto separato tra `SEC-USR-ID` e utente digitato.

   **Correzione proposta:** richiedere valori esatti di otto byte e casi con minuscole nell’ingresso, minuscole nel record password, spazi iniziali/finali e lunghezze significative diverse. I due operandi del confronto password hanno la stessa lunghezza: l’eventuale riempimento avviene prima. I confronti con `SPACES` e `LOW-VALUES` riguardano l’intero campo; una miscela dei due non equivale automaticamente a vuoto. La conversione eventualmente effettuata da CICS prima della ricezione va distinta dalla funzione COBOL, perché dipende da profilo e terminale: [input BMS](https://www.ibm.com/docs/en/cics-ts/6.x?topic=data-formatted-screen-input).

10. **Importante — “Campi obbligatori vuoti” non definisce priorità, continuazione e messaggi verificabili.**  
    **Evidenza:** `COSGN00C.cbl:117–140` esamina prima l’utente, poi la password. Se entrambi sono vuoti produce soltanto `Please enter User ID ...`. Dopo aver inviato il messaggio continua alle conversioni di righe 132–136 e assegna comunque `CDEMO-USER-ID`; salta soltanto la lettura. Non controlla le lunghezze `USERIDL`/`PASSWDL`.

    I messaggi dei tasti vengono da `CSMSG01Y.cpy:18–21`, quelli di validazione e autenticazione sono letterali nel programma (`120`, `125`, `242–254`). Il ringraziamento di `COTTL01Y.cpy:23–24` è diverso e non viene usato per F3.

    **Correzione proposta:** richiedere utente vuoto, password vuota, entrambi vuoti, spazi e `LOW-VALUES`; fissare priorità, cursore e assenza della lettura. Registrare gli snapshot al momento del `SEND`, distinti dallo stato finale. Gli attesi devono contenere messaggi esatti e riempimenti: `WS-MESSAGE` è lungo 80, il campo mappa 78, mentre F3 invia 80 caratteri.

11. **Importante — “Ambiente” non definisce larghezze ed effetti delle risposte.**  
    **Evidenza:** la data proviene da `FUNCTION CURRENT-DATE` (`COSGN00C.cbl:179`), non da CICS; viene formattata `MM/DD/YY`, e l’ora `HH:MM:SS` (`186–196`, `CSDAT01Y.cpy:18–41`). Quest’ultima viene spostata in un campo di nove caratteri (`COSGN00.CPY:122`), quindi include uno spazio finale.

    `SYSIDO` è lungo otto caratteri (`COSGN00.CPY:134`), ma `ASSIGN SYSID` restituisce quattro caratteri: [riferimento IBM, ASSIGN](https://www.ibm.com/docs/SSGMCP_5.5.0/pdf/api-reference_pdf.pdf). Gli altri quattro non possono essere inventati come riempimento del comando.

    **Correzione proposta:** fissare il valore dell’orologio per ciascuna chiamata, formati e byte attesi; definire larghezza ed effetto di `APPLID` e `SYSID`. Per la coda di `SYSIDO` seguire la provenienza della memoria: al primo ingresso è stata azzerata con `LOW-VALUES`; negli altri percorsi dipende dalla ricezione o resta indeterminata.

12. **Bloccante — “Non determinabile dal sorgente” può diventare una maschera senza limiti.**  
    **Evidenza:** `.contestazione/11.md:21` permette questa classificazione, ma i criteri non verificano che sia corretta né quali osservazioni debbano restare determinate. Una matrice potrebbe escludere messaggi, chiave o destinazione pur citando righe esistenti. Viceversa, dati inizialmente indeterminati possono influire su attributi e cursore: escludere il singolo campo non basta a rendere determinato il resto dell’esito.

    **Correzione proposta:** introdurre esclusioni strutturate per campo o intervallo, con causa, dipendenze e fonte; verificarle indipendentemente. Distinguere indeterminato, condizionato a un ingresso simulato, dipendente da una regola runtime documentata e non osservabile. Rendere obbligatori gli attesi determinati per messaggi, chiave, destinazione e assegnazioni esplicite. Il precedente batch controlla che siano escluse **esattamente** le posizioni non determinate (`oracle/golden/verificatore.sh:34–35`).

13. **Bloccante — “Machine-readable” non è ancora un contratto consumabile senza reinterpretazione.**  
    **Evidenza:** `.contestazione/11.md:15–23` elenca concetti, ma non fissa rappresentazioni, valori omessi, default, sequenze, confronto o maschere. A riga 18 richiede identificatori delle *decisioni*, insufficienti a identificare le singole alternative. Due esecutori possono scegliere rispettivamente testo normalizzato o byte, schermata finale o snapshot dei `SEND`, casi singoli o conversazioni, e produrre formati entrambi conformi.

    **Correzione proposta:** fissare versione, schema chiuso, codifica, lunghezze, distinzione tra assente/spazio/zero/indeterminato, riferimenti a comando e alternativa, ordine degli eventi e regola di confronto. Richiedere un consumatore minimo che ricavi gli assert senza usare descrizioni narrative. La divisione formato/pilota richiede almeno un congelamento intermedio del contratto: l’approvazione unica dopo entrambi (`33`) arriva troppo tardi. Se tale passaggio non è gestibile nella stessa issue, separare contratto e compilazione del pilota mantenendo questi controesempi come requisiti.

14. **Importante — Il comando verde e il perimetro non garantiscono una consegna completa.**  
    **Evidenza:** `analysis/run.sh:95–103` restituisce successo se una cartella esiste ma manca `check.sh`; `--all` enumera soltanto cartelle con almeno uno script (`33–42`). Pertanto i comandi di `.contestazione/11.md:29,34` possono risultare verdi senza il verificatore richiesto.

    Inoltre il diff è ristretto a due cartelle (`9`, `32`), mentre `CLAUDE.md:124,156` richiede registrazione degli strumenti e dei comandi nel paper e in `paper/data/`; le misure passano per `paper/data/eventi.csv` (`179–183`). Il prompt dell’Esecutore vieta modifiche a `paper/` senza autorizzazione nella specifica (`paper/data/prompts/esecutore.md:16–20`).

    **Correzione proposta:** rendere obbligatori `analysis/behavior/run.sh`, `check.sh`, dipendenze e artefatti enumerati, verificandone esplicitamente l’esistenza e provando la rimozione del controllo. Precisare chi aggiorna paper e misure e se questi aggiornamenti spettano all’Esecutore o al coordinatore, fuori dal suo diff. Il perimetro attuale non assegna questa responsabilità in modo eseguibile.