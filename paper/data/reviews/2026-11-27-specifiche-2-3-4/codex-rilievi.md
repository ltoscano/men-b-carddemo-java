1. **04 — bloccante. `CBSTM03A` ha un impedimento all’esecuzione che non riguarda i TAB.**  
   **Evidenza:** [prima/04.md:17](prima/04.md:17) ammette soltanto normalizzazioni di spazi bianchi; [CBSTM03A.CBL:266](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03A.CBL:266) attraversa invece PSA, TCB e TIOT tramite puntatori, prima ancora dell’apertura dei file. Gli stub richiesti non intercettano questi accessi alla memoria z/OS. Compilare non rende eseguibile questo percorso nel container.  
   **Correzione proposta:** decidere prima dell’assegnazione come trattare questa dipendenza. Separare compilabilità e compatibilità d’esecuzione; qualsiasi adattamento richiede un’autorizzazione ulteriore rispetto alla normalizzazione ammessa.

2. **03 — bloccante. Il record sentinella richiesto non è realizzabile letteralmente per le aree ridefinite.**  
   **Evidenza:** [prima/03.md:35](prima/03.md:35) impone un valore distinto per ogni campo nello stesso record. In [CVEXPORT.cpy:24](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVEXPORT.cpy:24), e nelle successive ridefinizioni, cliente, conto e transazione occupano gli stessi byte, con interpretazioni numeriche diverse. Non sono campi valorizzabili indipendentemente.  
   **Correzione proposta:** richiedere una famiglia di sentinelle, una per vista compatibile; verificare separatamente gli alias e definire quali campi partecipano a ciascun caso.

3. **03 — importante. Il perimetro FD/01 perde proprio il contenuto dei record variabili citati come esempio.**  
   **Evidenza:** [prima/03.md:6](prima/03.md:6) identifica i record interni con FD e relative `01`. L’FD variabile espone soltanto `VBR-REC PIC X(80)`; i campi effettivi sono in `WORKING-STORAGE`, [CBACT01C.cbl:123](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT01C.cbl:123). I due record vengono trasferiti nell’FD con lunghezze 12 e 39, [CBACT01C.cbl:287](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT01C.cbl:287).  
   **Correzione proposta:** includere esplicitamente le strutture usate per comporre i record, con relazione struttura → FD → lunghezza scritta. Un contratto composto solo da `X(80)` deve fallire.

4. **04 — importante. L’accettazione può certificare programmi che non si avviano.**  
   **Evidenza:** [prima/04.md:34](prima/04.md:34) verifica la produzione di eseguibili o moduli; il test dei parametri può restare sintetico. `CBACT04C` apre cinque file prima di usare il parametro, [CBACT04C.cbl:180](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT04C.cbl:180), e non contiene il `DISPLAY` del parametro evocato dal criterio. `CBSTM03B` richiede inoltre una propria area di chiamata, [CBSTM03B.CBL:99](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03B.CBL:99).  
   **Correzione proposta:** fissare modalità d’invocazione e caricamento per ogni programma e aggiungere smoke test reali con fixture minime, distinguendoli dai golden successivi.

5. **02, 03, 04 — importante. Un comando `--check` può essere verde perché il controllo manca.**  
   **Evidenza:** [analysis/run.sh:100](analysis/run.sh:100) restituisce successo quando lo script richiesto non esiste; [analysis/run.sh:39](analysis/run.sh:39) scopre anche cartelle con il solo `run.sh`. Quindi i criteri basati sul solo successo del dispatcher non provano la presenza dei nuovi controlli. Il dispatcher di 04 deve seguire la «stessa convenzione».  
   **Correzione proposta:** aggiungere ai comandi di accettazione una verifica esplicita degli script obbligatori; nel nuovo dispatcher oracle rendere l’assenza di un controllo richiesto un errore.

6. **02, 03 — importante. Il riuso delle funzioni esistenti è descritto con un percorso e un comportamento sbagliati.**  
   **Evidenza:** [prima/02.md:18](prima/02.md:18) e [prima/03.md:14](prima/03.md:14) attribuiscono il volume sensibile alle maiuscole a `common.sh`. `ensure_legacy_volume` e `tool_run` sono invece in [analysis/tools/lib.sh:28](analysis/tools/lib.sh:28); `glue_run` usa direttamente il bind mount del legacy, [common.sh:54](analysis/lib/common.sh:54). Inoltre `OUT` predefinito punta a `analysis/tools/out`.  
   **Correzione proposta:** prescrivere l’inclusione delle due librerie, output privati tramite `TOOLS_OUT` e mount espliciti per documenti e volume. È fattibile nel perimetro dichiarato, ma non usando soltanto `common.sh`.

7. **04 — importante. Il contratto di chiamata di `CEE3ABD` non è unico.**  
   **Evidenza:** [CBACT01C.cbl:410](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBACT01C.cbl:410) passa `ABCODE, TIMING`; [CBSTM03A.CBL:923](legacy/aws-mainframe-modernization-carddemo/app/cbl/CBSTM03A.CBL:923) chiama la stessa routine senza argomenti. [prima/04.md:39](prima/04.md:39) richiede genericamente un test dello stub, che potrebbe coprire una sola firma.  
   **Correzione proposta:** richiedere entrambi i casi tramite chiamanti COBOL, fissare il codice osservabile dal processo padre e verificare gli effetti persistenti anche con file ancora aperti al momento dell’arresto.

8. **03 — importante. Manca una verifica di completezza dei tracciati.**  
   **Evidenza:** [prima/03.md:33](prima/03.md:33) controlla «ogni tracciato» senza definire l’insieme atteso. [CVTRA07Y.cpy:4](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVTRA07Y.cpy:4) contiene più record `01`; [CSSETATY.cpy:18](legacy/aws-mainframe-modernization-carddemo/app/cpy/CSSETATY.cpy:18) contiene invece logica eseguibile. Il manifesto dei file non basta a distinguere questi casi.  
   **Correzione proposta:** produrre un censimento verificato delle radici record, degli FD e delle esclusioni motivate. Cancellare un contratto o una radice deve far fallire il controllo. Separare censimento/estrazione dalla successiva PR dei codec e delle sentinelle.

9. **03 — importante. Il round-trip sentinella può confermare un contratto sbagliato.**  
   **Evidenza:** [prima/03.md:35](prima/03.md:35) non specifica da quale fonte indipendente costruire il record. Se codifica e decodifica usano lo stesso contratto, uno scambio iniziale resta coerente. Il caso è concreto: [CVACT01Y.cpy:7](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVACT01Y.cpy:7) ha più importi consecutivi della stessa lunghezza.  
   **Correzione proposta:** fissare byte e valori attesi indipendentemente dal contratto sotto test. La mutazione deve alterare soltanto il contratto, lasciando invariati record e attesi; applicarla anche fuori dai tre copybook campionati.

10. **03 — importante. La rigenerazione richiesta può partire da XML obsoleti.**  
    **Evidenza:** [prima/03.md:37](prima/03.md:37) richiede di rigenerare «dagli output di cb2xml», senza imporre di rieseguire cb2xml sul legacy corrente. Gli output esistenti vengono prodotti soltanto per quattro copybook, [40-cb2xml.sh:19](analysis/tools/trials/40-cb2xml.sh:19). Un contratto e un XML entrambi obsoleti possono coincidere.  
    **Correzione proposta:** durante `--check` eseguire estrazione e cb2xml su tutti i sorgenti censiti, in una directory temporanea privata; confrontare poi contratti e viste Markdown con i file versionati.

11. **02 — importante. I controlli richiesti lasciano intere classi di dipendenze senza verifica.**  
    **Evidenza:** [prima/02.md:41](prima/02.md:41) controlla programmi, `EXEC PGM`, `COPY`, alcuni trasferimenti CICS e l’esistenza di un arco da `CORPT00C`. Non richiede controlli completi su transazioni, mappe, modalità dei file, DD, code o `RETURN TRANSID`. Esempi reali sono [CORPT00C.cbl:199](legacy/aws-mainframe-modernization-carddemo/app/cbl/CORPT00C.cbl:199) e [CORPT00C.cbl:517](legacy/aws-mainframe-modernization-carddemo/app/cbl/CORPT00C.cbl:517).  
    **Correzione proposta:** definire copertura e attesi per ciascun tipo di arco; introdurre mutazioni che eliminino un’intera categoria, non soltanto un arco campionato.

12. **02 — importante. Gli strumenti adottati non forniscono tutta la provenienza obbligatoria.**  
    **Evidenza:** [prima/02.md:21](prima/02.md:21) impone file e riga per ogni arco. Il risultato CMT contiene soltanto nomi delle chiamate, [inventory.json:17](analysis/tools/out/cmt/inventory.json:17); la normalizzazione mapa conserva passi e DD senza righe, [normalize.py:86](analysis/tools/glue/normalize.py:86). Il ripiego autorizzato non esplicita la localizzazione di `CALL`, `EXEC` e DD.  
    **Correzione proposta:** autorizzare e specificare un localizzatore delle occorrenze, con test su ripetizioni e continuazioni. Non accettare righe inventate, convenzionali o ricavate dalla prima corrispondenza.

13. **02 — importante. Cardinalità e identità del grafo restano decisioni dell’esecutore.**  
    **Evidenza:** [prima/02.md:25](prima/02.md:25) richiede destinazioni variabili, mentre il criterio confronta numero di archi e numero di istruzioni. Un solo `XCTL`, [COMEN01C.cbl:185](legacy/aws-mainframe-modernization-carddemo/app/cbl/COMEN01C.cbl:185), seleziona diverse destinazioni dalla tabella di menu. Inoltre mappa e mapset sono simboli distinti, [CORPT00.bms:19](legacy/aws-mainframe-modernization-carddemo/app/bms/CORPT00.bms:19).  
    **Correzione proposta:** fissare uno schema JSON con identificatori, occorrenze, insiemi di destinazioni, provenienza e distinzione mappa/mapset. Confrontare le occorrenze delle istruzioni, non indiscriminatamente gli archi espansi.

14. **02, 03, 04 — importante. Le cartelle disgiunte non isolano le risorse Docker.**  
    **Evidenza:** [analysis/tools/lib.sh:31](analysis/tools/lib.sh:31) usa un volume globale basato sul commit; inizializzazione e marker non sono protetti da lock. Due processi possono copiare contemporaneamente e uno può leggere dopo il marker dell’altro mentre una copia è ancora attiva. I tag degli strumenti sono anch’essi globali; 04 non assegna un namespace all’immagine oracle.  
    **Correzione proposta:** concordare inizializzazione seriale prima dei tre esecutori, oppure volumi distinti per esecuzione. Vietare normalizzazioni nel volume condiviso e riservare tag oracle diversi da quelli di analisi.

15. **04 — importante. La semantica degli stub è lasciata all’agente e la PR contiene più lavori autonomi.**  
    **Evidenza:** [prima/04.md:24](prima/04.md:24) chiede genericamente semantica originale e test. [CSUTLDTC.cbl:116](legacy/aws-mainframe-modernization-carddemo/app/cbl/CSUTLDTC.cbl:116) dipende da data lilliana e feedback strutturato di `CEEDAYS`; [CSUTLDTC.cbl:128](legacy/aws-mainframe-modernization-carddemo/app/cbl/CSUTLDTC.cbl:128) distingue numerosi errori. Uno stub sempre positivo può rispettare una semantica dichiarata dall’esecutore ma falsificare l’oracle.  
    **Correzione proposta:** fissare firme, casi supportati, risultati attesi e rifiuto esplicito dei casi non supportati. Dividere infrastruttura/compilazione, avviatore e compatibilità delle routine in PR separate.

16. **03 — importante. Il contratto non distingue sufficientemente contenuto logico e rappresentazione fisica.**  
    **Evidenza:** [prima/03.md:17](prima/03.md:17) richiede byte e rappresentazione del segno senza fissare codifica o profilo. [CVTRA05Y.cpy:10](legacy/aws-mainframe-modernization-carddemo/app/cpy/CVTRA05Y.cpy:10) contiene un numerico DISPLAY con segno. Per i variabili, [READACCT.jcl:47](legacy/aws-mainframe-modernization-carddemo/app/jcl/READACCT.jcl:47) dichiara `LRECL=84`, mentre l’FD arriva a 80 byte.  
    **Correzione proposta:** distinguere payload, lunghezza effettiva, capacità massima e intestazioni fisiche; dichiarare profili EBCDIC e oracle. Precisare anche se i numerici invalidi conservano i byte, producono un errore o ricevono un valore: oggi la scelta cambia i risultati.

17. **04 — importante. Togliere gli spazi non dimostra l’equivalenza di un sorgente COBOL fisso.**  
    **Evidenza:** [prima/04.md:36](prima/04.md:36) verifica soltanto l’identità dopo la rimozione di spazi e TAB. Nel formato fisso, spostare caratteri tra colonne può cambiare istruzioni, commenti e testo ignorato. Il problema originario è visibile in [CUSTREC.cpy:6](legacy/aws-mainframe-modernization-carddemo/app/cpy/CUSTREC.cpy:6).  
    **Correzione proposta:** fissare esattamente tabulazioni e trasformazione ammessa; confrontare l’output con quella trasformazione deterministica. Aggiungere mutazioni di soli spazi che spostino colonne significative e pretendere che siano respinte.

18. **02 — importante. «Inventario completo» di tutti i moduli eccede il lavoro delimitato e i mezzi prescritti.**  
    **Evidenza:** [prima/02.md:6](prima/02.md:6) include anche i moduli opzionali, assembler, macro e controlli; gli archi specificati coprono soprattutto COBOL/CICS/JCL. Nei moduli opzionali esistono dipendenze SQL, [COTRTUPC.cbl:286](legacy/aws-mainframe-modernization-carddemo/app/app-transaction-type-db2/cbl/COTRTUPC.cbl:286), e IMS, [COPAUS1C.cbl:439](legacy/aws-mainframe-modernization-carddemo/app/app-authorization-ims-db2-mq/cbl/COPAUS1C.cbl:439), senza criteri di rappresentazione o copertura.  
    **Correzione proposta:** dividere inventario strutturale/COPY/CALL, collegamenti CICS e JCL generato, approfondimento dei moduli opzionali. Nella prima PR censire esplicitamente le categorie rinviate, evitando di chiamare completo un grafo che le omette.