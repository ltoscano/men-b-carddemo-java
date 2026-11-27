## Obiettivo
Da clone pulito, `docker compose up` deve portare su un'applicazione vuota ma sana: database, servizio online, runner batch. Da qui in poi esiste sempre qualcosa che gira, e la verifica dell'avvio passa dai jar isolati allo stack reale.

## Dipendenze e perimetro
- Dipende da: #13 (mergiata). Riallineata al suo esito: Spring Boot 4.2.0, Spring Batch 6.1.0, jar eseguibili con classificatore `exec`, `verify.sh`.
- Sostituisce #19: l'avvio dei jar esce da `verify.sh` (vedi "Architettura della verifica"), quindi la funzione di arresto che #19 doveva correggere viene rimossa.
- Cartelle e file coinvolti (i soli modificabili): `compose.yaml`, `docker/`, `smoke.sh`, `.env.example`, `.dockerignore`, `verify.sh`, `.github/workflows/ci.yml`, `docs/sviluppo.md`; in `carddemo-online/` e `carddemo-batch/`: `pom.xml`, `src/main/resources/`, `src/test/`; in `carddemo-batch/src/main/java/` solo la configurazione del job descritto sotto. `pom.xml` padre solo per fissare la versione di una dipendenza che Boot non gestisce.
- Fuori ambito: schema e dati di business (Wave 1); logica di business; Testcontainers e strumenti di qualità (#15); `carddemo-domain/`, `-loader/`, `-parity/`.

## Architettura della verifica (decisione presa, non da rimettere in discussione)
Con l'arrivo di PostgreSQL le applicazioni non partono più senza database, quindi `verify.sh` non può più avviare i jar da soli. La responsabilità si divide così:

- **`./verify.sh`** = build e test, senza servizi esterni: cancella gli output precedenti (fallendo se la cancellazione fallisce), esegue `mvn -B verify` in container, poi controlla che per `online` e `batch` esista **esattamente un** jar eseguibile `*-exec.jar`. Non avvia più alcun processo applicativo: la parte di avvio, controllo di salute e arresto va rimossa, insieme alle variabili che la configuravano. Restano il controllo della cancellazione, la restituzione della proprietà limitata alle cartelle `target/` e la propagazione dei codici di errore.
- **`./smoke.sh`** = avvio reale dello stack con Compose, salute, job batch, pulizia.
- **Test dei moduli:** i due test che caricano il contesto Spring (`OnlineApplicationTest`, `BatchApplicationTest`) restano e continuano a caricare il contesto, senza database: lo ottengono con una configurazione valida **solo per i test** che esclude l'autoconfigurazione della sorgente dati (per `batch`, anche il passaggio all'archivio dei metadati senza persistenza, se serve). È vietato un database in memoria o incorporato, è vietato disabilitare o saltare test, è vietato `-DskipTests` o equivalenti. La prova con il database vero è lo smoke test; i test di integrazione con PostgreSQL arrivano con #15.

## Specifica
- **Immagini dell'applicazione:** una per `online` e una per `batch`, con build multi-stage che compila dentro Docker (nessun jar costruito sull'host), immagini di base a versione fissata per tag e digest, processo eseguito da utente non-root.
- **Servizi in `compose.yaml`:**
  - `db`: PostgreSQL a versione fissata, volume nominato, healthcheck.
  - `online`: parte solo quando `db` è sano; pubblica la porta HTTP sull'host, con porta configurabile da variabile d'ambiente e valore predefinito dichiarato; healthcheck su `/actuator/health`, che deve comprendere lo stato del database.
  - `batch`: non parte con `docker compose up`; si esegue con `docker compose run --rm batch`, si collega a `db`, esegue il job `installationCheckJob` e termina con codice 0.
- **Job `installationCheckJob`:** un job Spring Batch con un solo passo, `installationCheckStep`, che non fa nulla e termina. Serve a dimostrare che il runner batch esegue davvero un job e ne registra l'esito. Nessuna logica, nessun accesso a tabelle.
- **Riesecuzione:** ogni lancio crea una nuova istanza del job, grazie a un parametro identificativo diverso a ogni esecuzione. Due lanci consecutivi sullo stesso database, senza cancellare il volume, terminano entrambi con 0 e lasciano due esecuzioni `COMPLETED` distinte.
- **Database:** `online` e `batch` si collegano a PostgreSQL. I metadati di Spring Batch stanno in PostgreSQL, nelle tabelle che Spring Batch crea per sé: unica eccezione a "nessuna tabella". Nessuna tabella di business.
- **Configurazione:** indirizzo, utente e password del database da variabili d'ambiente. `.env.example` contiene valori di sviluppo dichiarati come tali; nessun segreto reale; `compose.yaml` funziona da clone pulito senza che l'utente crei file.
- **`./smoke.sh`:**
  1. usa un nome di progetto Compose proprio e una **porta host scelta dinamicamente** (ricavata da Compose dopo l'avvio), così funziona anche mentre lo stack ordinario dello sviluppatore è attivo;
  2. costruisce le immagini e avvia lo stack; attende lo stato sano entro un tempo limite;
  3. interroga l'endpoint di salute dall'host, con timeout su ogni richiesta, e verifica leggendo il JSON che lo stato alla radice sia `UP` e che il componente del database sia presente e `UP`;
  4. lancia il job due volte e, interrogando PostgreSQL, verifica che esistano due esecuzioni di `installationCheckJob` create da questo smoke test, entrambe `COMPLETED`, ciascuna con `installationCheckStep` `COMPLETED`. Il solo codice di uscita 0 non basta;
  5. spegne e rimuove container, rete e volumi del proprio progetto **anche quando un passo fallisce**, poi verifica tramite le etichette del progetto Compose che non restino container (nemmeno arrestati), reti o volumi;
  6. termina con codice diverso da 0 se un passo qualsiasi fallisce, pulizia compresa, dicendo quale. Ogni attesa ha un limite.

## Invarianti da preservare
- Le dipendenze tra moduli restano quelle fissate in #13; i jar eseguibili e ordinari restano come sono.
- Le garanzie di `verify.sh` che non riguardano l'avvio: fallisce se la build fallisce, se un test fallisce, se la cancellazione degli output fallisce, se manca o è duplicato un jar eseguibile.

## Criteri di accettazione (verificabili)
- [ ] Da clone pulito, solo Docker: `./verify.sh` termina con 0 e non avvia processi applicativi; `./smoke.sh` termina con 0.
- [ ] `./verify.sh`, prove negative con esito diverso da 0: test rotto; `repackage` rimosso da un modulo (nessun jar eseguibile); cancellazione degli output impedita.
- [ ] `./smoke.sh`, prove negative, ciascuna con esito diverso da 0 in tempo limitato e senza lasciare risorse: `db` che non diventa sano; `online` con salute alla radice non `UP`; database irraggiungibile da `online`; job che termina con codice diverso da 0; **lancio del job disabilitato** (il runner termina con 0 senza eseguire il job: lo smoke deve fallire perché mancano le esecuzioni `COMPLETED`); pulizia che fallisce.
- [ ] `./smoke.sh` termina con 0 mentre lo stack ordinario è attivo (`docker compose up -d --wait` eseguito prima), e lo stack ordinario resta intatto.
- [ ] Dopo `./smoke.sh`, riuscito o fallito: nessun container (anche arrestato), rete o volume con l'etichetta del progetto di smoke (comando riportato nella PR).
- [ ] Nelle due immagini il processo non gira come root (comando ed esito nella PR).
- [ ] I due test di contesto esistono ancora, vengono eseguiti (non saltati) e passano; nessun database in memoria tra le dipendenze (`mvn dependency:tree`).
- [ ] La CI esegue `./verify.sh` e `./smoke.sh` ed è verde sulla PR.
- [ ] Il diff tocca solo il perimetro dichiarato.

## Strategia di rollback
Revert della PR: si torna alla verifica con avvio dei jar isolati.

## Limiti per l'agente
- Nessuna tabella di business, nessun endpoint oltre a quello di salute, nessun job oltre a `installationCheckJob`.
- Nessuna versione non fissata, in `compose.yaml`, nei Dockerfile o nei POM.
- Negli script ogni comando il cui fallimento conta va controllato: uno script che prosegue dopo un errore è un difetto. Rileggi ogni script riga per riga con questa domanda prima di consegnare.
- Le mutazioni usate per le prove negative non restano nel codice.
- Se un requisito risulta irrealizzabile nel perimetro: `needs-spec-update`, non un aggiramento.
