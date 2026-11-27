# Sviluppo: costruire, verificare, avviare

Prerequisiti sull'host: Docker (con Compose v2), git e bash. Nessun JDK, Maven o PostgreSQL locale.

1. Clona con i submodule: `git clone --recurse-submodules <url>` (o `git submodule update --init`).
2. La verifica è divisa in due comandi, gli stessi della CI:
   - `./verify.sh`: build e test, compreso un test di integrazione che avvia PostgreSQL in un container (Testcontainers);
   - `./smoke.sh`: avvio reale dello stack con Compose, salute, job batch, pulizia.

## `./verify.sh`: build e test

1. Dentro `maven:3.9.16-eclipse-temurin-21` cancella i `target/` precedenti ed esegue `mvn -B verify` (compila e prova i cinque moduli, compreso il test di integrazione con PostgreSQL descritto sotto). Se la cancellazione fallisce, la verifica si ferma prima di Maven.
2. Controlla nel rapporto di surefire di questa build che il test di integrazione `PostgresIntegrazioneTest` sia stato eseguito e non saltato (almeno un test, `skipped`, `failures` ed `errors` a 0). Se il rapporto manca, la verifica fallisce.
3. Controlla che `carddemo-online` e `carddemo-batch` abbiano esattamente un jar eseguibile (`*-exec.jar`).
4. Non avvia alcun processo applicativo: con PostgreSQL le applicazioni non partono senza database, quindi l'avvio è compito di `./smoke.sh`.
5. I due test di contesto (`OnlineApplicationTest`, `BatchApplicationTest`) caricano il contesto Spring senza database, con il profilo `test` (`src/test/resources/application-test.properties`), che esclude l'autoconfigurazione della sorgente dati. Nessun database in memoria o incorporato. Senza sorgente dati Spring Batch usa da sé un archivio dei metadati senza persistenza.
6. Esito: codice 0 se tutto passa, pulizia compresa (punto 12); diverso da 0 al primo errore. L'ultima riga è `== verifica completata` oppure `== VERIFICA FALLITA (codice N)`.
7. La cache delle dipendenze Maven sta nel volume Docker `menb-build-m2` (variabile `MENB_BUILD_CACHE_VOLUME` per cambiarlo); `docker volume rm menb-build-m2` la azzera.
8. A fine corsa solo le cartelle `target/` tornano all'utente dell'host; un errore di `chown` fa fallire la verifica.
9. Moduli: `domain` (nessuna dipendenza), `loader`, `online`, `batch` (solo da `domain`), `parity` (da tutti). `online` e `batch` producono un jar ordinario e uno eseguibile con classificatore `exec`.
10. Ispezione delle dipendenze: `docker run --rm -v menb-build-m2:/root/.m2 -v "$PWD":/workspace -w /workspace maven:3.9.16-eclipse-temurin-21 mvn -B dependency:tree`.
11. Limite di tempo: l'intero container di build ha `MENB_VERIFY_TIMEOUT` secondi (predefinito 1800); allo scadere il client Docker riceve SIGTERM, dopo 10 s SIGKILL, e la verifica fallisce. Ogni altro comando Docker dello script ha un limite di 60 s. Il limite è implementato in `quality/limite.sh` (senza `timeout`, che su macOS manca), condiviso con `quality/regressioni-verify.sh`.
12. Pulizia: alla fine, riuscita o fallita, anche se lo script riceve INT, TERM o HUP o scade il limite, `verify.sh` ferma il client Docker in corso, rimuove il container di build se esiste ancora (prima, perché non avvii altri container) e i container con l'etichetta `menb.verify.run=<corsa>` della propria corsa, poi verifica con un nuovo elenco che non ne resti nessuno. Se ne trova, li rimuove e fallisce comunque; se Docker non restituisce l'elenco, o lo restituisce in un formato inatteso, l'assenza non è provata e la verifica fallisce. L'identificativo della corsa (`verify-<pid>-<casuale>`) compare nel log; i residui di altre corse non vengono toccati.
13. Controllo manuale dei residui di tutte le corse: `docker ps -a --filter label=menb.verify.run`.

## Test di integrazione con PostgreSQL (Testcontainers)

`carddemo-parity/src/test/java/.../PostgresIntegrazioneTest.java` dimostra il meccanismo e non introduce schema:

1. Legge l'immagine del servizio `db` da `compose.yaml` (`services.db.image`). Il percorso arriva dal POM di `carddemo-parity` come proprietà di sistema `menb.compose.file`, impostata a `${project.parent.basedir}/compose.yaml`: la radice del repository, non la cartella del modulo. Se la proprietà manca, il file non esiste o l'immagine non ha tag e digest, il test fallisce.
2. Avvia con Testcontainers proprio quel riferimento, tag e digest compresi, senza una seconda costante. Testcontainers interpreta `postgres:18.7-trixie@sha256:…` come repository `postgres:18.7-trixie`, quindi il nome è dichiarato compatibile con `postgres` (`asCompatibleSubstituteFor`).
3. Asserisce che il container effettivamente avviato abbia come immagine (`Config.Image`) lo stesso riferimento letto da `compose.yaml` e che l'immagine avviata abbia quel digest fra i suoi `RepoDigests`.
4. Crea una tabella temporanea propria (`menb_prova_integrazione`), scrive due righe, le rilegge, la elimina e controlla che non esista più; stampa `select version()`.
5. Chiude il container e verifica che Docker non lo trovi più.
6. Nessuna annotazione o proprietà lo salta: se Docker non è raggiungibile, Testcontainers lancia un'eccezione (`Could not find a valid Docker environment`), il test fallisce e con esso `./verify.sh`, in pochi secondi.

**Tag e digest.** Con un riferimento `nome:tag@sha256:digest`, Docker scarica e avvia per digest e non risolve il tag sul registro. Fa fede il digest; il tag è un'etichetta per chi legge. Quindi:
- cambiando il solo digest con quello di un'altra versione, parte quell'altra versione (lo si vede da `select version()` nel log);
- con un digest inesistente il pull fallisce e `./verify.sh` fallisce;
- cambiando il solo tag, cambia il riferimento del container avviato (`Config.Image`), ma il contenuto resta quello del digest.

**Limite dichiarato:** un tag inesistente accanto a un digest valido non fa fallire né il test né `docker compose up`, che avviano la stessa immagine. Farlo fallire richiederebbe di interrogare il registro dal test; i tag vengono ripubblicati nel tempo e il test smetterebbe di riprodurre ciò che fa Compose (decisione: voce 28 del registro delle approvazioni).

### Accesso a Docker dai test

Maven gira in un container, quindi i test devono avviare altri container e raggiungerne le porte. Soluzione scelta, uguale su macOS (Docker Desktop) e su Linux (GitHub Actions):

- **Socket del daemon montato** nel container di build: `-v /var/run/docker.sock:/var/run/docker.sock`. La sorgente di un montaggio è risolta dal daemon, quindi è il suo socket; Docker Desktop tratta questo percorso in modo speciale e porta al daemon della sua VM. I container avviati dai test sono fratelli del container di build, non figli.
- **Porte via `host.docker.internal`**: il container di build ha `--add-host host.docker.internal:host-gateway` e `TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal`, quindi Testcontainers si collega alle porte pubblicate sull'host. Su Linux `host-gateway` è l'indirizzo dell'host sulla rete `bridge`; su Docker Desktop è l'host della VM.
- **Ryuk disattivato** (`TESTCONTAINERS_RYUK_DISABLED=true`): il container che Testcontainers usa per pulire resterebbe acceso una decina di secondi dopo la fine e non si distingue da quello di altre sessioni. La pulizia la fa `verify.sh`, per etichetta di corsa (punto 12 sopra); il test etichetta il container con `menb.verify.run`, letta dalla variabile `MENB_VERIFY_RUN_ID`. Così non si scarica nemmeno l'immagine di Ryuk, fissata solo per tag dentro Testcontainers.

Rischi:

- **Chi ha accesso al socket di Docker controlla Docker**, e quindi di fatto l'host (può avviare container privilegiati e montare qualunque cartella). Nel container di build gira tutto ciò che Maven esegue: test, plugin, dipendenze scaricate da Maven Central. Una dipendenza compromessa avrebbe lo stesso potere. È lo stesso livello di fiducia che si dà già a `./verify.sh`, che usa Docker sull'host; non va eseguito su codice di cui non ci si fida.
- I test possono creare container, reti e volumi sul daemon dell'host, visibili e in conflitto con quelli dell'utente. Il test usa porte scelte da Docker e un'etichetta propria; la pulizia per etichetta copre i container, non reti o volumi creati da test futuri, che vanno etichettati allo stesso modo.
- Il socket deve essere `/var/run/docker.sock` sul daemon. Con daemon remoti (`DOCKER_HOST=tcp://…`), Docker rootless o altre configurazioni il percorso cambia: non sono supportati e il test fallisce, senza essere saltato.
- Se lo script viene ucciso con SIGKILL la pulizia non avviene (senza Ryuk nessuno rimuove i container): si controlla con il comando del punto 13.

Prove: su macOS, Docker Desktop 29.9.2 (arm64), e in GitHub Actions, `ubuntu-latest` con Docker 29.4.2 (amd64); esiti nella PR dell'issue #15.

## `quality/regressioni-verify.sh`: regressioni di `./verify.sh`

Si esegue a richiesta (non fa parte di `./verify.sh` né della CI obbligatoria), da un albero di lavoro pulito: `./quality/regressioni-verify.sh`.

1. Esegue `./verify.sh` senza mutazioni: deve riuscire, altrimenti i casi negativi fallirebbero per la ragione sbagliata.
2. Poi un caso per volta, ciascuno con il proprio limite di tempo (`MENB_REGRESSIONI_TIMEOUT`, predefinito 1800 s) e con il controllo del codice di uscita **e** del messaggio atteso:

| Caso | Mutazione | Atteso |
| --- | --- | --- |
| `repackage-rimosso` | blocco `<build>` tolto da `carddemo-online/pom.xml`, con il jar eseguibile della corsa di base presente | codice ≠ 0, `attesi esattamente 1 jar eseguibile in carddemo-online/target, trovati 0` |
| `test-rotto` | un test che fallisce, aggiunto in `carddemo-domain` | codice ≠ 0, il test nell'elenco dei fallimenti di surefire, `mvn verify fallito` |
| `id-fallisce` | `id` sul `PATH` che esce con 42 | codice ≠ 0, `id -u fallito` |
| `docker-fallisce` | `docker` sul `PATH` che esce con 42 | codice 42, `container di build terminato con codice 42` |
| `docker-irraggiungibile` | `docker` sul `PATH` che inoltra tutto al vero `docker` ma toglie il montaggio del socket dal container di build: Docker funziona sull'host, non dentro Maven | codice ≠ 0 entro il limite, `Could not find a valid Docker environment`, fallimento di `PostgresIntegrazioneTest`, `mvn verify fallito`; se il montaggio non viene trovato, la mutazione non è applicata e il caso fallisce |

3. Ripristina il POM e cancella il test aggiunto dopo ogni caso, e comunque all'uscita (anche per errore o INT, TERM, HUP); alla fine controlla che `git status` sia pulito.
4. Esito: 0 solo se tutti i casi danno l'esito atteso e l'albero è pulito; l'ultima riga è `== REGRESSIONI RIUSCITE: tutti i casi rilevati` o `== REGRESSIONI FALLITE (codice N)`. Per un caso non rilevato stampa le ultime righe del suo log.
5. `MENB_REGRESSIONI_LOGS=<cartella esistente>` conserva il log di ogni caso (`<caso>.log`).
6. Non si provano strumenti che restituiscono dati falsi ma ben formati (regola "Fin dove arriva la sfiducia negli script" in `CLAUDE.md`).

## Lo stack Compose

| Servizio | Cosa fa |
| --- | --- |
| `db` | PostgreSQL, volume nominato `pgdata`, healthcheck con `pg_isready` via TCP |
| `online` | parte quando `db` è sano; pubblica la porta HTTP sull'host (`MENB_ONLINE_PORT`, predefinita 8080); healthcheck su `/actuator/health`, che comprende il componente `db` |
| `batch` | non parte con `up` (profilo `batch`); `docker compose run --rm batch` esegue `installationCheckJob` e termina |

- Avvio: `docker compose up -d --wait` (db e online). Salute: `curl http://localhost:8080/actuator/health`.
- Job: `docker compose run --rm batch`. Ogni lancio crea una nuova istanza del job (parametro `run.id` incrementato), quindi si può rilanciare sullo stesso database.
- Arresto: `docker compose down` (aggiungere `-v` per cancellare anche il volume del database).
- Configurazione: indirizzo, utente e password del database arrivano alle applicazioni da `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, impostate da `compose.yaml` a partire da `MENB_DB_NAME`, `MENB_DB_USER`, `MENB_DB_PASSWORD`. Ogni variabile ha un valore predefinito di sviluppo, quindi da clone pulito non serve creare file; `.env.example` li elenca e si copia in `.env` solo per cambiarli. Sono valori di sviluppo, non segreti.
- Immagini: `docker/app.Dockerfile`, una per `online` e una per `batch` (argomento `MODULE`). Build multi-stage: il jar si compila nel container Maven (test compresi), l'immagine finale contiene solo la JRE e il jar e gira come utente `carddemo` (uid 10001).
- I metadati di Spring Batch stanno in PostgreSQL, nelle tabelle `batch_*` che Spring Batch crea al primo avvio (`spring.batch.jdbc.initialize-schema=always`). Nessuna tabella di business.

## `./smoke.sh`: avvio reale

1. Usa il progetto Compose `menb-smoke` (variabile `MENB_SMOKE_PROJECT`), non legge il file `.env` e pubblica `online` su una porta host scelta da Docker, letta con `docker compose port`: funziona anche con lo stack ordinario attivo e non lo tocca.
2. Se esistono già risorse con l'etichetta del progetto (residui di una corsa interrotta), le rimuove e fallisce: un risultato precedente non può passare per attuale.
3. Costruisce le immagini, avvia `db` e `online` e attende lo stato sano (`up --wait`).
4. Interroga `/actuator/health` dall'host (container `curlimages/curl` sulla rete dell'host, timeout per richiesta) e legge il JSON con PostgreSQL: servono HTTP 200, stato alla radice `UP` e componente `db` presente e `UP`.
5. Controlla che prima dei lanci non ci siano esecuzioni di `installationCheckJob`; lancia `docker compose run --rm batch` due volte e dopo ogni lancio verifica in PostgreSQL che ci siano esattamente 1, poi 2 esecuzioni, `COMPLETED`, ciascuna con il solo `installationCheckStep` `COMPLETED`, su istanze distinte. Il solo codice di uscita 0 non basta.
6. Alla fine, anche se un passo è fallito, esegue `down --volumes --remove-orphans`; poi verifica per etichetta che non restino container (anche arrestati), reti o volumi. Se ne restano li rimuove per etichetta e fallisce comunque; se Docker non restituisce l'elenco (o lo restituisce in un formato inatteso), l'assenza non è provata e lo smoke fallisce. Il controllo per etichetta non è ridondante: `down` termina con 0 anche quando un volume non si può rimuovere perché un altro container lo usa. Se lo smoke riceve INT, TERM o HUP, ferma il comando in corso e poi esegue la stessa pulizia.
7. Ogni comando esterno ha un limite di tempo (implementato nello script, senza `timeout`, che su macOS manca). Limiti in secondi: `MENB_SMOKE_BUILD_TIMEOUT` (900), `MENB_SMOKE_UP_TIMEOUT` (240), `MENB_SMOKE_BATCH_TIMEOUT` (180), `MENB_SMOKE_DOWN_TIMEOUT` (120).
8. Esito: 0 solo se tutti i passi, pulizia compresa, riescono; altrimenti diverso da 0, con il passo fallito nell'ultima riga.
9. Controllo manuale dei residui: `docker ps -a --filter label=com.docker.compose.project=menb-smoke`, `docker network ls --filter label=com.docker.compose.project=menb-smoke`, `docker volume ls --filter label=com.docker.compose.project=menb-smoke`.

Le immagini `menb-smoke-online` e `menb-smoke-batch` restano dopo lo smoke (non sono container, reti o volumi) e vengono sovrascritte alla corsa successiva.

## Versioni scelte

Verificate il 27 novembre 2026.

| Componente | Versione | Fonte consultata |
| --- | --- | --- |
| Java | 21 | requisito del progetto |
| Spring Boot | 4.2.0 (GA; 4.2.0-RC1 e RC2 scartate) | `maven-metadata.xml` di `spring-boot-starter-parent` su Maven Central (`release` = 4.2.0, aggiornato il 19 nov 2026); `4.2.0` è una versione di rilascio, il suo parent richiede Java 17 o superiore, quindi compatibile con 21 |
| Spring Batch | 6.1.0 (gestita da Boot, nessuna sovrascrittura) | `mvn dependency:tree` |
| Driver PostgreSQL, HikariCP | gestiti da Boot 4.2.0 (nessuna versione nei POM) | `mvn dependency:tree` |
| Immagine di build | `maven:3.9.16-eclipse-temurin-21` (Maven 3.9.16, JDK 21), nel Dockerfile anche per digest `sha256:99e61abc…` | tag dell'immagine ufficiale `maven` su Docker Hub |
| Immagine di esecuzione | `eclipse-temurin:21.0.13.1_2-jre-alpine-3.24`, digest `sha256:5d7689f4…` | Docker Hub: ultima patch di Java 21; la variante `jre-noble` della stessa patch non aveva ancora l'immagine `arm64`, la variante Alpine sì (`amd64`, `arm64`) |
| PostgreSQL | `postgres:18.7-trixie`, digest `sha256:64c8b0d3…` | `postgresql.org/versions.json`: 18.7 rilasciata il 12 nov 2026, supportata fino al 14 nov 2030. Scartata la 19.0 (rilasciata il 19 nov 2026, prima versione della serie) |
| curl per lo smoke | `curlimages/curl:8.23.0`, digest `sha256:3fb7e13e…` | Docker Hub, ultima versione pubblicata (28 ott 2026) |
| Testcontainers (`testcontainers-postgresql`) | 2.0.5 (gestita da Boot, nessuna sovrascrittura) | `spring-boot-dependencies-4.2.0.pom` (`testcontainers.version` = 2.0.5) e `maven-metadata.xml` di `org.testcontainers:testcontainers` su Maven Central (`release` = 2.0.5), verificati il 27 nov 2026 |
| Driver PostgreSQL e SnakeYAML nei test di `parity` | gestiti da Boot 4.2.0 (42.7.14 e 2.7), dichiarati con scope `test` | `mvn dependency:tree` |
| Immagine PostgreSQL del test di integrazione | quella di `compose.yaml`, letta dal test | — |

Boot e tutte le librerie Spring sono quelle gestite dal parent `spring-boot-starter-parent`; nessuna versione dinamica. I digest completi sono in `docker/app.Dockerfile`, `compose.yaml` e `smoke.sh`.
