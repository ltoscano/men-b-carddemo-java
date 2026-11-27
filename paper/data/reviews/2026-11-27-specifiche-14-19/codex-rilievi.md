1. **Specifica 14 — bloccante: l’avvio con PostgreSQL è incompatibile con la verifica attuale.**  
   **Evidenza:** [verify.sh:21](verify.sh:21) crea un container senza database, rete Compose o credenziali; alle righe 95 e 126 avvia direttamente entrambi i jar. La [14:19](bozze/14.md:19) impone contemporaneamente verifica verde, divieto di modificarla e arresto con `needs-spec-update`. La 19 autorizza soltanto la correzione dell’arresto, quindi non risolve questa incompatibilità. Un profilo predefinito senza database sarebbe una scelta architetturale non specificata, potenzialmente l’aggiramento vietato.  
   **Correzione proposta:** decidere prima l’architettura di verifica e autorizzare l’adattamento di `verify.sh`, oppure definire esplicitamente profili, garanzie e controlli della modalità senza database.

2. **Specifica 14 — bloccante: richiede un job ma vieta i file necessari a definirlo.**  
   **Evidenza:** la [14:6](bozze/14.md:6) consente nei moduli soltanto POM, risorse e test esistenti; la riga 14 richiede l’esecuzione di un job vuoto. [BatchApplication.java:6](carddemo-batch/src/main/java/io/github/ltoscano/carddemo/batch/BatchApplication.java:6) contiene solo l’avviatore; [docs/sviluppo.md:31](docs/sviluppo.md:31) conferma che attualmente non viene eseguito alcun job.  
   **Correzione proposta:** includere nel perimetro una configurazione Java minima con job e step senza logica di business, precisandone nome e comportamento.

3. **Specifica 19 — importante: il parallelismo con la 14 viola le regole e cambia il presupposto delle prove.**  
   **Evidenza:** [19:8](bozze/19.md:8) e [14:6](bozze/14.md:6) autorizzano entrambe modifiche a `docs/sviluppo.md`; [CLAUDE.md:76](CLAUDE.md:76) vieta issue contemporanee sulla stessa cartella. Inoltre la 19 prova l’arresto dopo un avvio senza database, mentre la 14 modifica proprio quel presupposto. Due PR verdi separatamente non garantiscono una combinazione verde.  
   **Correzione proposta:** imporre una sequenza, preferibilmente 19 prima della 14 corretta, e rieseguire le prove della 19 sulla configurazione risultante.

4. **Specifica 19 — importante: cinque arresti lenti non verificano la corsa richiesta.**  
   **Evidenza:** la [19:16](bozze/19.md:16) richiede di gestire la terminazione tra controllo e SIGKILL; il criterio alla riga 25 esercita soltanto un arresto tra nove e dieci secondi. Aggiungere un controllo dopo l’ultima attesa di [verify.sh:43](verify.sh:43) può superare tutte e cinque le ripetizioni lasciando intatta la corsa successiva.  
   **Correzione proposta:** aggiungere una prova deterministica che faccia terminare il processo dopo l’ultimo controllo positivo ma prima di SIGKILL, verificando esito 0 e assenza di arresto forzato.

5. **Specifica 19 — importante: manca la prova che distingua processo scomparso ed errore reale del segnale.**  
   **Evidenza:** [verify.sh:45](verify.sh:45) invia SIGKILL e poi esegue `wait` senza limite autonomo. La [19:17](bozze/19.md:17) richiede errore per arresto fallito, ma i criteri provano soltanto un processo che ignora SIGTERM. Una correzione come «SIGKILL fallito ⇒ successo» può superare quelle prove e mascherare un errore con processo ancora vivo; mantenere `wait` può invece bloccare.  
   **Correzione proposta:** aggiungere una prova controllata di SIGKILL fallito con processo ancora presente, imponendo esito nonzero e durata massima esplicita.

6. **Specifica 14 — importante: codice batch 0 e tabelle presenti possono certificare un job mai eseguito.**  
   **Evidenza:** lo smoke descritto nella [14:17](bozze/14.md:17) controlla solo il codice del batch; il criterio alla riga 29 parla genericamente di metadati presenti. L’avviatore attuale termina già senza job, come documentato in [docs/sviluppo.md:31](docs/sviluppo.md:31). Creare le tabelle senza eseguire alcunché può quindi soddisfare una lettura debole dei criteri.  
   **Correzione proposta:** fare verificare allo smoke una nuova esecuzione del job previsto con stato `COMPLETED` e relativo step completato in PostgreSQL; aggiungere una prova con lancio del job disabilitato.

7. **Specifica 14 — importante: il nome di progetto non isola le porte pubblicate.**  
   **Evidenza:** la [14:13](bozze/14.md:13) richiede una porta HTTP sull’host; la riga 18 sostiene che un progetto Compose proprio eviti interferenze con lo stack dello sviluppatore. Due progetti che pubblicano la stessa porta collidono comunque: lo smoke può fallire soltanto perché l’applicazione è già avviata.  
   **Correzione proposta:** assegnare allo smoke una porta host dinamica, ricavarla da Compose e interrogare quella; provare esplicitamente lo smoke mentre lo stack ordinario è attivo.

8. **Specifica 14 — importante: lascia all’esecutore quanto della copertura esistente eliminare.**  
   **Evidenza:** [OnlineApplicationTest.java:6](carddemo-online/src/test/java/io/github/ltoscano/carddemo/online/OnlineApplicationTest.java:6) e [BatchApplicationTest.java:6](carddemo-batch/src/test/java/io/github/ltoscano/carddemo/batch/BatchApplicationTest.java:6) avviano realmente i contesti con `@SpringBootTest`. La [14:15](bozze/14.md:15) permette di renderli indipendenti dal database o rinviarli, senza fissare verifiche sostitutive minime. La build può diventare verde perché i test significativi sono stati disabilitati.  
   **Correzione proposta:** prescrivere quali controlli restano nei test e quali passano allo smoke, vietare esclusioni globali dei test e identificare precisamente le verifiche rinviate alla 15.

9. **Specifica 14 — importante: non definisce la seconda esecuzione del batch sul volume persistente.**  
   **Evidenza:** la [14:12](bozze/14.md:12) introduce un volume persistente; la riga 14 presenta `docker compose run --rm batch` come comando ordinario. Mancano parametri identificativi, comportamento alla riesecuzione e criterio dopo un secondo lancio. L’agente deve decidere autonomamente se creare una nuova istanza, riavviare quella precedente o accettare un errore.  
   **Correzione proposta:** definire la politica delle istanze del job e richiedere due lanci consecutivi sullo stesso database, senza cancellare il volume, con esiti e metadati attesi.

10. **Specifica 19 — importante: “jar residuo ⇒ errore” omette le condizioni essenziali della regressione.**  
    **Evidenza:** la [19:21](bozze/19.md:21) elenca genericamente il jar residuo tra le prove negative, tutte richieste nonzero alla riga 27. Ma [verify.sh:74](verify.sh:74) deve normalmente cancellare i residui e proseguire con successo. La prova storica comprendeva anche rimozione di `repackage` e impedimento effettivo della cancellazione: [giro-3-codex.md:10](paper/data/reviews/pr-17/giro-3-codex.md:10).  
    **Correzione proposta:** riportare preparazione e risultato atteso di ogni mutazione, distinguendo residuo eliminabile, cancellazione fallita ed eseguibile non prodotto dalla nuova build.

11. **Specifica 14 — importante: i comandi di accettazione della pulizia non dimostrano la pulizia richiesta.**  
    **Evidenza:** la [14:17](bozze/14.md:17) richiede rimozione di container, rete e volumi; il criterio alla riga 28 controlla soltanto `docker compose ls` e `docker volume ls`. Non verifica le reti residue né enumera tutti i container arrestati. Inoltre nessuna prova forza un errore della pulizia, benché debba propagarsi nel codice finale.  
    **Correzione proposta:** controllare container anche arrestati, reti e volumi tramite le etichette del progetto; aggiungere una prova di fallimento della pulizia che verifichi esito nonzero e diagnostica del passo fallito.