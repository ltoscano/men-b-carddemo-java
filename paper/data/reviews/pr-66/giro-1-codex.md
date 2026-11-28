**BOCCIATA**

| Criterio | Comando eseguito | Esito osservato |
|---|---|---|
| 1. Build e suite obbligatorie | `MENB_BUILD_CACHE_VOLUME=menb-val66-m2 ./verify.sh` | **0**. domain 399, loader 1, online 1, batch 1, parity 39; nessun salto. Le 16 prove nuove risultano eseguite. Conteggi identici alla CI. |
| 2. Smoke | `MENB_SMOKE_PROJECT=menb-val66-smoke ./smoke.sh` | **0**. Caricamento, migrazioni, `online-primo`, secondo avvio e pulizia completati. Con caricatore fallito: **1**, passo `avvio`. |
| 3. Regressioni | `./quality/regressioni-verify.sh` | **0**, tutti i casi rilevati. |
| 3. Regole | `./quality/regressioni-regole.sh` | **0**, 44 casi su 44. |
| 3. Copertura, sottoinsieme consentito | `./quality/regressioni-copertura.sh controprova-lecita` | **0**, base e controprova lecita. |
| 3. Codec, solo base | `bash ./quality/regressioni-codec-base.sh` — estratto invariato del blocco base | **0**. Nessuna esecuzione integrale della suite. Nessun atteso delle due suite è cambiato nel diff. |
| 4. Prove negative | Harness indipendenti `data.py`, `mutations.py`, `fullgreens.py`, `gates.py`, `transactions.py` | Rifiuti e mutazioni dettagliati nelle [evidenze complete](/tmp/menb-val66-evidence/prove.txt). **Tre mutazioni superano anche `verify.sh` completo**, descritte sotto. |
| 5. Perimetro e stato | `git diff origin/main...HEAD`, `cmp` con il patch fornito, `git status --short` | Patch identico; **nessun file fuori perimetro**. Nessuna modifica versionata residua. Resta soltanto `.validazione/`, già presente inizialmente; copie di prova pulite. |
| 6. CI sullo SHA finale | `gh pr checks 66` | Tutti i controlli verdi su `c59038807379fd03a70b3409a3109e8efeb00c8d`. [Corsa CI](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46114434563). |

Il confronto indipendente dei 50 conti, caricati con l’immagine reale in PostgreSQL dell’immagine fissata da Compose, coincide per ogni colonna, scala, spazio finale e ordine di chiave. La ricomposizione restituisce gli stessi 15.000 byte. Il file nell’immagine ha SHA-256 `591952211bfa94397d633a6f6553cf6dda29051f978ec8c0459ed036431dd700`, identico al repository.

Zero negativo e segno alternativo sono rifiutati in tutti e cinque gli importi; sono rifiutati anche filler alterato nelle tre posizioni, numerico con spazi, chiave non numerica, duplicato non adiacente e file da 299/301 byte: codice 1, zero righe, diagnosi pertinente. File vuoto: codice 0, zero righe. Nei sei campi testuali, nullo rifiutato; tabulazione, `0x7F`, `0x80`, `0xFF` accettati e riletti via JDBC rispettivamente come U+0009, U+007F, U+0080, U+00FF, con ricodifica identica. Database UTF8.

Errore al record 50: zero righe. `SIGTERM` durante il record 25: uscita 143, zero righe. Secondo avvio e tabella con una riga estranea: codice 1 e diagnosi di tabella non vuota, dati conservati, coerentemente con il comportamento dichiarato.

Le prove sui rapporti obbligatori rilevano assenza, salto e rinomina con codice 1. Sono state eseguite sul blocco invariato estratto da `verify.sh`; un precedente tentativo integrale ha superato il limite di 400 secondi del mio harness e non è conteggiato come prova riuscita.

1. **Bloccante — confronto del tracciato dipendente dal codificatore dei test.**  
   [TracciatoContoTest.java:26](/tmp/menb-val66-repo/carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/TracciatoContoTest.java:26) costruisce gli attesi attraverso `ContiDiProva.tracciato()` e gli stessi accessori usati dal codificatore. Ho scambiato gli offset 48 e 58 nel caricatore e nell’accessore del modello dei test, senza modificare TSV o asserzioni: **16 prove verdi e `verify.sh` completo con 0**. Il jar così prodotto carica realmente il conto 1 con apertura `2025-05-20` e scadenza `2014-11-20`; il file contiene il contrario. [Valori osservati](/tmp/menb-val66-evidence/drift-values.txt).  
   **Schema generale:** implementazione e oracle condividono l’interpretazione che dovrebbero controllare. **Correzione richiesta:** confronto dei campi elementari direttamente con le righe TSV, indipendente dal modello del codificatore; verificare separatamente anche quest’ultimo.  
   **Effetto:** falso verde, oracle infedele e dati caricati infedeli, dimostrati. **Riproduzione:** modifica di due file versionati; nessuna falsificazione di artefatti generati.

2. **Bloccante — controllo della tabella vuota non protetto dalla concorrenza.**  
   Tra controllo e inserimento non esiste una serializzazione: [CaricatoreConti.java:74](/tmp/menb-val66-repo/carddemo-loader/src/main/java/io/github/ltoscano/carddemo/loader/CaricatoreConti.java:74). Due file distinti, ciascuno con un solo conto, caricati insieme sullo stesso database vuoto terminano **entrambi con 0** e lasciano due righe. Ho forzato l’interleaving con un trigger temporaneo di attesa. La tabella risultante non corrisponde a nessuno dei due file accettati.  
   **Schema generale:** precondizione verificata senza proteggerla fino al commit. **Correzione richiesta:** serializzare controllo e caricamento nella transazione; aggiungere prove concorrenti con chiavi coincidenti e disgiunte. La limitazione documentata non impedisce il risultato osservato.  
   **Effetto:** dati infedeli e successo ingannevole; nessuna alterazione dell’oracle necessaria. **Riproduzione:** ingressi propri e sincronizzazione temporanea nel database, senza modificare sorgenti né falsificare output.

3. **Importante — PostgreSQL nasconde la violazione della scala.**  
   Sul binding in [CaricatoreConti.java:139](/tmp/menb-val66-repo/carddemo-loader/src/main/java/io/github/ltoscano/carddemo/loader/CaricatoreConti.java:139), sia `setScale(3)` sia l’aggiunta di `0.001` agli importi superano le 16 prove. Con `+0.001`, **anche `verify.sh` completo termina con 0**: PostgreSQL elimina il millesimo e la rilettura non vede la perdita.  
   **Schema generale:** verifica soltanto successiva a una normalizzazione silenziosa del database. **Correzione richiesta:** controllare valore e scala dei parametri effettivamente passati a JDBC, oltre alla rilettura; la controprova del millesimo deve fallire.  
   **Effetto:** falso verde su una conversione con perdita; nella controprova i valori persistiti coincidono grazie all’arrotondamento. Nessun oracle infedele dimostrato. **Riproduzione:** modifica di un file versionato, senza falsificare artefatti.

4. **Importante — il controllo del bytecode monetario non copre `loader`.**  
   [NoFloatingPointBytecodeTest.java:264](/tmp/menb-val66-repo/carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/NoFloatingPointBytecodeTest.java:264) individua esclusivamente le classi di `domain`. Nel caricatore ho introdotto `valore.multiply(BigDecimal.valueOf(Math.pow(1, 1)))`: conversione implicita attraverso `double`, invisibile al controllo testuale. **`verify.sh` completo termina con 0.**  
   **Schema generale:** una regola globale è verificata soltanto in un modulo. **Correzione richiesta:** estendere l’ispezione alle classi di produzione del caricatore, comprese conversioni con perdita e pacchetti aggiuntivi.  
   **Effetto:** falso verde sulla regola monetaria; questa specifica mutazione non altera i valori finali né l’oracle. **Riproduzione:** modifica del sorgente versionato del caricatore; nessun artefatto falsificato.

5. **Importante — `batch` non rispetta la dipendenza richiesta dalla specifica.**  
   In [compose.yaml:106](/tmp/menb-val66-repo/compose.yaml:106) manca la dipendenza da `loader`. Avviato da solo, `batch` termina con 0 lasciando `account` vuota. Ho confermato la motivazione dichiarata su Compose v5.6.1: aggiungendo la dipendenza, `compose run` rilancia il caricatore già terminato e fallisce con `service "loader" didn't complete successfully: exit 1`. Il fatto tecnico è corretto; la scelta resta uno scostamento dal requisito «i servizi applicativi dipendono dal caricatore».  
   **Schema generale:** un problema del ciclo di avvio viene risolto eliminando la precondizione richiesta. **Correzione richiesta:** riallineare dipendenza, comandi e smoke alla politica di riesecuzione concordata.  
   **Effetto:** falso verde sulla disponibilità dei conti per il servizio; il batch attuale non li legge, quindi non ho osservato dati caricati infedeli o un oracle infedele. **Riproduzione:** comandi ordinari, senza modifiche versionate o artefatti falsificati; la correzione richiede file versionati.

Le altre mutazioni richieste — date scambiate, testi senza spazi finali, record saltato, ultimo campo memorizzato troncato, canonicità resa tautologica e commit per record — sono rosse, con nomi e diagnosi nelle evidenze.

Le affermazioni sul legacy trovano riscontro in `CVACT01Y.cpy:5–17` e `ACCTFILE.jcl:25,36,40–41,61`; anche il file EBCDIC originale, decodificato CP037, coincide integralmente con `ACCTFILE.rec`. Nuove immagini fissate per tag e digest, dipendenze gestite dal BOM; nessun nuovo profilo Maven, database in memoria, percorso locale o segreto rilevato.

Risorse Docker della validazione rimosse, incluse etichette immagine e volumi propri; nessuna modifica versionata residua, commit o push.