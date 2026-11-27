1. **Gravità: bloccante — L’oracle può essere accettato senza compilare alcun batch.**  
   **Dove:** [0A-4, criteri di accettazione](bozze-v1/04.md:22).  
   **Evidenza:** `compile` deve fallire solo quando l’esito differisce dal README; è quindi conforme registrare tutti i programmi come «non compila» e ottenere verde. Le issue #5 e #6 richiedono invece programmi eseguibili.  
   **Correzione proposta:** fissare un insieme obbligatorio di programmi che devono compilare, collegarsi agli stub ed essere invocabili; ogni esclusione deve bloccare esplicitamente le dipendenze interessate.

2. **Gravità: bloccante — Manca il contratto di invocazione del parametro mainframe.**  
   **Dove:** [0A-4, compilazione](bozze-v1/04.md:15) e [0A-6, riferimento a `PARM`](bozze-v1/06.md:9).  
   **Evidenza:** [CBACT04C.cbl:175](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:175) riceve mediante `PROCEDURE DIVISION USING` una struttura con lunghezza binaria e dieci caratteri. Non legge un argomento della shell. Quel valore entra direttamente nella costruzione degli ID delle transazioni a [riga 476](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:476).  
   **Correzione proposta:** prescrivere un launcher che costruisca esattamente la struttura attesa, con test sui byte ricevuti e sugli ID prodotti. Compilare il programma non verifica questo requisito.

3. **Gravità: bloccante — Il contratto dell’AIX xref contraddice quello dichiarato dal batch.**  
   **Dove:** [0A-3, chiavi](bozze-v1/03.md:16) e [0A-5, caricamento](bozze-v1/05.md:17).  
   **Evidenza:** [XREFFILE.jcl:74](legacy/aws-mainframe-modernization-carddemo/app/jcl/XREFFILE.jcl:74) definisce la chiave conto con `NONUNIQUEKEY`; [CBACT04C.cbl:38](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:38) dichiara l’alternate key senza `WITH DUPLICATES`. Il programma legge proprio attraverso quella chiave a [riga 394](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:394).  
   **Correzione proposta:** risolvere esplicitamente la compatibilità nell’oracle e aggiungere una fixture con due carte per conto. Occorre verificare anche quale carta venga restituita: una query SQL arbitraria può produrre interessi associati alla carta sbagliata.

4. **Gravità: bloccante — La seconda esecuzione può arrestarsi dopo avere già modificato i saldi.**  
   **Dove:** [0A-6, riesecuzione](bozze-v1/06.md:16) e [limite sugli abend](bozze-v1/06.md:32).  
   **Evidenza:** [CBTRN02C.cbl:440](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBTRN02C.cbl:440) aggiorna categoria e conto prima di scrivere la transazione. La scrittura con chiave già presente segue il percorso di abend a [riga 562](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBTRN02C.cbl:562). Ripresentare un ID precedentemente accettato esercita quindi un percorso con effetti parziali.  
   **Correzione proposta:** distinguere esito del comando di verifica ed esito del programma; registrare arresto, codice, ultimo passo ed effetti persistenti. Stabilire prima quando un abend è risultato atteso e quando richiede `needs-spec-update`.

5. **Gravità: bloccante — Il report richiede un input che il ciclo non costruisce.**  
   **Dove:** [0A-6, sorgenti e riproduzione delle DD](bozze-v1/06.md:9).  
   **Evidenza:** [TRANREPT.jcl:73](legacy/aws-mainframe-modernization-carddemo/app/jcl/TRANREPT.jcl:73) legge `AWS.M2.CARDDEMO.DATEPARM`; [CBTRN03C.cbl:166](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBTRN03C.cbl:166) lo apre e lo legge obbligatoriamente. Il percorso online costruisce invece un override in-stream in [CORPT00C.cbl:116](legacy/aws-mainframe-modernization-carddemo/app/cbl/CORPT00C.cbl:116). Le bozze non scelgono quale invocazione riprodurre né definiscono questa fixture.  
   **Correzione proposta:** includere nel manifesto del ciclo tutti gli input esterni, date comprese, e distinguere il job statico dal job generato dall’online.

6. **Gravità: importante — Il contratto dati omette proprio gli output del pilota.**  
   **Dove:** [0A-3, sorgenti considerate](bozze-v1/03.md:9) e [pilota batch](docs/piano-wave.md:93).  
   **Evidenza:** [CBACT01C.cbl:56](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT01C.cbl:56) definisce direttamente nelle FD output con `COMP-3`, array e record variabili: non provengono dai copybook elencati. [READACCT.jcl:37](legacy/aws-mainframe-modernization-carddemo/app/jcl/READACCT.jcl:37) assegna tre dataset, con formati FB e VB.  
   **Correzione proposta:** includere FD, `RECORD DEPENDING`, DCB e rappresentazione dei prefissi dei record variabili. Definire quali byte siano confrontabili fra GnuCOBOL e z/OS: «byte per byte» senza tale contratto è ambiguo.

7. **Gravità: importante — Il “ciclo giornaliero” fissato nel piano non è condiviso dalle fonti.**  
   **Dove:** [piano, Wave 4](docs/piano-wave.md:111) e [0A-7, accettazione](bozze-v1/07.md:23).  
   **Evidenza:** [CardDemo.controlm:3](legacy/aws-mainframe-modernization-carddemo/app/scheduler/CardDemo.controlm:3) descrive un flusso giornaliero `CLOSEFIL → TRANBKP → WAITSTEP → OPENFIL`; il flusso interessi è denominato mensile a [riga 65](legacy/aws-mainframe-modernization-carddemo/app/scheduler/CardDemo.controlm:65). [run_full_batch.sh:61](legacy/aws-mainframe-modernization-carddemo/scripts/run_full_batch.sh:61) passa a `TRANIDX` senza eseguire `CREASTMT`. #7 può comunque passare dichiarando discordanze o ordine non determinato.  
   **Correzione proposta:** aggiungere una decisione obbligatoria dopo #7 che selezioni e motivi gli scenari eseguibili. Un DAG aciclico non dimostra che l’ordine scelto sia quello corretto.

8. **Gravità: importante — La chiave export è già incoerente fra JCL e COBOL.**  
   **Dove:** [0A-3, derivazione delle chiavi](bozze-v1/03.md:16).  
   **Evidenza:** [CBEXPORT.jcl:32](legacy/aws-mainframe-modernization-carddemo/app/jcl/CBEXPORT.jcl:32) dichiara `KEYS(4 28)`. In [CVEXPORT.cpy:10](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVEXPORT.cpy:10), `EXPORT-SEQUENCE-NUM` comincia invece all’offset 27: un byte di tipo più 26 di timestamp. Inoltre [CBEXPORT.cbl:68](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBEXPORT.cbl:68) lo usa come record key, ma il campo è in working-storage, fuori dalla FD.  
   **Correzione proposta:** confrontare obbligatoriamente `DEFINE`, `SELECT`, FD e copybook. Registrare una decisione specifica sull’export prima di derivarne loader o schema.

9. **Gravità: importante — I glob indicati escludono programmi richiesti.**  
   **Dove:** [0A-1, diagnostica](bozze-v1/01.md:21), [0A-2, conteggio](bozze-v1/02.md:33), [0A-4, perimetro](bozze-v1/04.md:9).  
   **Evidenza:** gli estratti conto sono [CBSTM03A.CBL:2](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03A.CBL:2) e [CBSTM03B.CBL:2](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03B.CBL:2), con estensione maiuscola. Anche tre programmi opzionali usano `.CBL`. In un container Linux `*.cbl` e `CB*.cbl` li perdono.  
   **Correzione proposta:** prescrivere enumerazione senza distinzione di maiuscole e verificare un manifesto esplicito dei programmi, non due conteggi derivati dallo stesso glob sbagliato.

10. **Gravità: importante — La fixture iniziale delle transazioni contiene dati numericamente invalidi.**  
    **Dove:** [0A-5, decodifica e controlli](bozze-v1/05.md:14).  
    **Evidenza:** [TRANFILE.jcl:70](legacy/aws-mainframe-modernization-carddemo/app/jcl/TRANFILE.jcl:70) carica `DALYTRAN.PS.INIT`. Il file fornito contiene esattamente 350 byte tutti `0x00`, compresi gli intervalli dichiarati numerici in [CVTRA05Y.cpy:8](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVTRA05Y.cpy:8). Non equivale a un file vuoto né a un record con importo zero.  
    **Correzione proposta:** includerlo esplicitamente nelle fixture e definire come conservare byte invalidi, rappresentarli nel contratto e trattarli nei totali. Convertirli silenziosamente a zero falsifica la baseline.

11. **Gravità: importante — Il controllo del contratto dati non verifica il contratto campo per campo.**  
    **Dove:** [0A-3, accettazione](bozze-v1/03.md:24).  
    **Evidenza:** somma delle lunghezze e posizione delle chiavi restano corrette anche scambiando due campi non chiave della stessa lunghezza o perdendo la scala. Per esempio i tre importi consecutivi in [CVACT01Y.cpy:7](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVACT01Y.cpy:7) possono essere permutati senza fare fallire i controlli richiesti.  
    **Correzione proposta:** verificare elenco completo dei campi, offset progressivi, sovrapposizioni, espansione degli `OCCURS`, scala e rappresentazione; aggiungere record sentinella con valori distinti per ogni campo.

12. **Gravità: importante — Le fixture possono essere sbagliate e superare tutti i controlli.**  
    **Dove:** [0A-5, accettazione](bozze-v1/05.md:25).  
    **Evidenza:** non sono fissati valori attesi per conteggi o totali. Due decodifiche che condividono lo stesso errore di contratto possono coincidere campo per campo; gli output generati da quei dati possono poi rigenerarsi identici. Nessuno di questi controlli dimostra che il valore originario sia stato preservato.  
    **Correzione proposta:** aggiungere valori di riferimento verificati indipendentemente, campioni con byte e valore atteso, e round-trip verso i record originali, conservando filler e varianti ammesse del segno.

13. **Gravità: importante — La copertura della matrice online è aggirabile con citazioni decorative.**  
    **Dove:** [0A-8, accettazione](bozze-v1/08.md:27).  
    **Evidenza:** citare tutti i paragrafi e tutti gli `EXEC CICS` non verifica i rami richiesti. Una matrice può omettere password errata e utente inesistente, pur citando `READ-USER-SEC-FILE`, che contiene entrambi in [COSGN00C.cbl:221](legacy/aws-mainframe-modernization-carddemo/app/cbl/COSGN00C.cbl:221).  
    **Correzione proposta:** enumerare decisioni e alternative con identificatori stabili; imporre un caso per ciascuna alternativa e verificare le asserzioni attese. Fare approvare la matrice prima dell’implementazione che dovrà soddisfarla.

14. **Gravità: importante — Mancano input necessari a rendere deterministico l’oracle online.**  
    **Dove:** [0A-8, formato dei casi](bozze-v1/08.md:15).  
    **Evidenza:** il formato non comprende clock, APPLID, SYSID o risposte simulate delle operazioni CICS. [COSGN00C.cbl:179](legacy/aws-mainframe-modernization-carddemo/app/cbl/COSGN00C.cbl:179) legge l’ora; a riga 198 legge identificativi del runtime; a riga 110 esegue `RECEIVE` con `RESP` e `RESP2`. Record presenti nei file e AID non determinano tutti gli esiti.  
    **Correzione proposta:** aggiungere questi valori agli input e modellare una sequenza di risposte CICS. Un esito «non determinabile» deve impedire di dichiarare coperta quella parte della parità.

15. **Gravità: importante — Stato conversazionale e ordine delle operazioni non bastano a preservare le transazioni CICS.**  
    **Dove:** [contratti condivisi](docs/piano-wave.md:75) e [formato della matrice](bozze-v1/08.md:16).  
    **Evidenza:** [COBIL00C.cbl:345](legacy/aws-mainframe-modernization-carddemo/app/cbl/COBIL00C.cbl:345) usa `READ UPDATE`; [COCRDUPC.cbl:469](legacy/aws-mainframe-modernization-carddemo/app/cbl/COCRDUPC.cbl:469) esegue `SYNCPOINT`; [COACTUPC.cbl:4100](legacy/aws-mainframe-modernization-carddemo/app/cbl/COACTUPC.cbl:4100) esegue rollback. Questi effetti non sono rappresentati dal formato proposto.  
    **Correzione proposta:** definire confini della transazione, lock, rilascio, commit, rollback e comportamento concorrente. Aggiungere casi con errore fra due aggiornamenti e richieste simultanee.

16. **Gravità: importante — Il prodotto “di base” espone già funzioni rinviate alla Wave 6.**  
    **Dove:** [separazione base/opzionali](docs/piano-wave.md:14).  
    **Evidenza:** [COMEN02Y.cpy:86](legacy/aws-mainframe-modernization-carddemo/app/cpy/COMEN02Y.cpy:86) contiene l’opzione verso `COPAUS0C`; [COADM02Y.cpy:46](legacy/aws-mainframe-modernization-carddemo/app/cpy/COADM02Y.cpy:46) espone `COTRTLIC` e `COTRTUPC`. Sono programmi opzionali, raggiungibili dai menu di base.  
    **Correzione proposta:** decidere esplicitamente cosa accade selezionando queste opzioni nella release base e registrare l’eventuale esclusione come deviazione di comportamento. La semplice separazione per directory non chiude il perimetro funzionale.

17. **Gravità: importante — Il grafo dinamico non può ricavare tutti i bersagli dai soli menu.**  
    **Dove:** [0A-2, trasferimenti CICS](bozze-v1/02.md:17).  
    **Evidenza:** [COCRDSLC.cbl:318](legacy/aws-mainframe-modernization-carddemo/app/cbl/COCRDSLC.cbl:318) assegna il bersaglio anche da `CDEMO-FROM-PROGRAM`, poi esegue `XCTL` a riga 332. Inoltre `CORPT00C` genera JCL nel COBOL e lo invia mediante [WRITEQ TD:517](legacy/aws-mainframe-modernization-carddemo/app/cbl/CORPT00C.cbl:517): questa dipendenza online→batch non rientra negli archi prescritti.  
    **Correzione proposta:** rappresentare provenienza dei valori, bersagli irrisolti, code TD e job generati. Verificare la completezza di queste categorie: gli attuali conteggi possono passare anche con tutti questi archi mancanti.

18. **Gravità: importante — Alcune issue richiedono comandi senza autorizzare i file che li implementano.**  
    **Dove:** [0A-7, perimetro](bozze-v1/07.md:10) e [0A-8, perimetro](bozze-v1/08.md:10).  
    **Evidenza:** entrambe consentono solo documentazione, ma richiedono nuovi sottocomandi di `analysis/run.sh`. Analogamente #5 e #6 richiedono estensioni di `oracle/run.sh`, fuori dalle rispettive cartelle modificabili. Non è richiesto alle issue iniziali un sistema di estensione che eviti queste modifiche.  
    **Correzione proposta:** assegnare prima dispatcher e interfaccia dei controlli, oppure autorizzare esplicitamente i file condivisi e serializzarne le modifiche. Il vincolo «diff solo nelle cartelle dichiarate» deve restare soddisfacibile.

19. **Gravità: importante — Il ripiego ammesso da #1 è vietato da #3.**  
    **Dove:** [0A-1, nessun candidato adottabile](bozze-v1/01.md:33) e [0A-3, limiti](bozze-v1/03.md:33).  
    **Evidenza:** #1 può chiudersi scartando tutti gli strumenti di estrazione dei tracciati e indicando soltanto un ripiego. #3 pretende invece che offset e lunghezze provengano dallo strumento adottato e vieta di ricavarli manualmente. Il suo prerequisito non garantisce quindi la capacità necessaria.  
    **Correzione proposta:** richiedere in #1 un percorso effettivamente utilizzabile per ogni capacità obbligatoria, oppure inserire un’issue di ripiego implementato e verificato prima di sbloccare #3.

20. **Gravità: importante — Il golden degli interessi non discrimina una politica decimale sbagliata.**  
    **Dove:** [0A-6, requisito minimo del golden](bozze-v1/06.md:24).  
    **Evidenza:** basta un conto con interessi calcolati. [CBACT04C.cbl:464](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:464) assegna il risultato della divisione a un campo con due decimali, senza `ROUNDED`, e successivamente lo accumula. Un’implementazione Java che arrotonda anziché troncare può passare su valori senza frazioni residue.  
    **Correzione proposta:** aggiungere fixture mirate per frazioni di centesimo positive e negative, limiti di capacità e accumuli; verificare il risultato dopo ciascuna assegnazione rilevante, non soltanto il totale finale.

21. **Gravità: importante — Il pilota signon non è una fetta completa con le dipendenze attuali.**  
    **Dove:** [Wave 2](docs/piano-wave.md:91) e [menu nella Wave 3](docs/piano-wave.md:102).  
    **Evidenza:** il login riuscito termina con `XCTL` verso `COADM01C` o `COMEN01C` in [COSGN00C.cbl:230](legacy/aws-mainframe-modernization-carddemo/app/cbl/COSGN00C.cbl:230). Entrambi arrivano nella wave successiva, che dipende dal pilota.  
    **Correzione proposta:** anticipare il minimo comportamento necessario dei menu oppure definire esplicitamente un test del solo confine di trasferimento. Aggiungere semplicemente una dipendenza dai menu creerebbe un ciclo fra Wave 2 e Wave 3.

22. **Gravità: importante — Due perimetri concentrano troppe incognite indipendenti in una sola issue.**  
    **Dove:** [0A-6, specifica](bozze-v1/06.md:13) e [regola “un programma completo”](docs/piano-wave.md:100).  
    **Evidenza:** #6 comprende equivalenti di SORT, IDCAMS, GDG, controllo del tempo, più programmi e riesecuzioni. La successiva issue di `COACTUPC` dovrebbe costruire contemporaneamente oracle documentale, servizio, endpoint e schermata per oltre quattromila righe, con numerose `COPY REPLACING` a partire da [riga 3208](legacy/aws-mainframe-modernization-carddemo/app/cbl/COACTUPC.cbl:3208) e rollback multipli.  
    **Correzione proposta:** separare compatibilità delle utility, esecuzione dei singoli job e concatenazione del ciclo; per i programmi grandi, approvare prima comportamento e contratti, poi suddividere implementazione e interfaccia con verifiche autonome.

23. **Gravità: minore — Le istruzioni operative conservano due numerazioni incompatibili.**  
    **Dove:** [CLAUDE.md:37](CLAUDE.md:37), [piano:33](docs/piano-wave.md:33), [0A-6:5](bozze-v1/06.md:5).  
    **Evidenza:** `CLAUDE.md` prescrive 0A e 0B in sequenza e colloca batch nella Wave 3 e opzionali nella Wave 4; il piano parallelizza 0A/0B e usa Wave 4 e 6. #6 continua a dichiararsi riferimento per tutta la Wave 3; #3 rinvia Db2/IMS alla Wave 4.  
    **Correzione proposta:** riallineare istruzioni, bozze ed etichette e dichiarare una sola fonte autorevole per numerazione e dipendenze.