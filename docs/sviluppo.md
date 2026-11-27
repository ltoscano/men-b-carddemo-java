# Sviluppo: costruire, verificare, avviare

Prerequisiti sull'host: Docker (con Compose v2), git e bash. Nessun JDK, Maven o PostgreSQL locale.

1. Clona con i submodule: `git clone --recurse-submodules <url>` (o `git submodule update --init`).
2. La verifica è divisa in due comandi, gli stessi della CI:
   - `./verify.sh`: build e test, compreso un test di integrazione che avvia PostgreSQL in un container (Testcontainers);
   - `./smoke.sh`: avvio reale dello stack con Compose, salute, job batch, pulizia.

## `./verify.sh`: build e test

1. Dentro `maven:3.9.16-eclipse-temurin-21` cancella i `target/` precedenti ed esegue `mvn -B verify` (compila e prova i cinque moduli, compreso il test di integrazione con PostgreSQL descritto sotto). Se la cancellazione fallisce, la verifica si ferma prima di Maven.
2. Controlla il rapporto di surefire del test di integrazione `PostgresIntegrazioneTest` con `quality/RapportoSurefire.java`, eseguito nel container dal lanciatore di sorgenti del JDK, che legge l'XML con il parser del JDK. Il rapporto deve:
   - essere un XML ben formato e completo (un file troncato o alterato non si legge);
   - essere di questa corsa: `mvn` riceve `-Dmenb.verify.run=<corsa>` e surefire registra la proprietà nel rapporto, quindi un rapporto di un'altra corsa viene respinto;
   - avere `tests` uguale al numero di `testcase` (almeno uno) e `skipped`, `failures` ed `errors` a 0;
   - contenere il caso `avviaLImmagineDiComposeScriveRileggeEdElimina`, senza `skipped`, `failure`, `error` o riesecuzioni.

   Se il rapporto manca o non soddisfa queste condizioni, la verifica fallisce.
3. Controlla i rapporti di copertura e di analisi statica con `quality/RapportiQualita.java` (JaCoCo e SpotBugs, sezione "Copertura e analisi statica (#27)" sotto): il rapporto aggregato di JaCoCo e la prova dell'agente in ogni modulo che esegue test, un rapporto SpotBugs per ogni modulo di produzione. I plugin li producono dentro `mvn verify`; `verify.sh` li valida dopo Maven, come il rapporto di surefire.
4. Controlla che `carddemo-online` e `carddemo-batch` abbiano esattamente un jar eseguibile (`*-exec.jar`).
5. Non avvia alcun processo applicativo: con PostgreSQL le applicazioni non partono senza database, quindi l'avvio è compito di `./smoke.sh`.
6. I due test di contesto (`OnlineApplicationTest`, `BatchApplicationTest`) caricano il contesto Spring senza database, con il profilo `test` (`src/test/resources/application-test.properties`), che esclude l'autoconfigurazione della sorgente dati. Nessun database in memoria o incorporato. Senza sorgente dati Spring Batch usa da sé un archivio dei metadati senza persistenza.
7. Esito: codice 0 se tutto passa, pulizia compresa (punto 13); diverso da 0 al primo errore. L'ultima riga è `== verifica completata` oppure `== VERIFICA FALLITA (codice N)`.
8. La cache delle dipendenze Maven sta nel volume Docker `menb-build-m2` (variabile `MENB_BUILD_CACHE_VOLUME` per cambiarlo); `docker volume rm menb-build-m2` la azzera.
9. A fine corsa solo le cartelle `target/` tornano all'utente dell'host; un errore di `chown` fa fallire la verifica.
10. Moduli: `domain` (nessuna dipendenza), `loader`, `online`, `batch` (solo da `domain`), `parity` (da tutti). `online` e `batch` producono un jar ordinario e uno eseguibile con classificatore `exec`.
11. Ispezione delle dipendenze: `docker run --rm -v menb-build-m2:/root/.m2 -v "$PWD":/workspace -w /workspace maven:3.9.16-eclipse-temurin-21 mvn -B dependency:tree`.
12. Limite di tempo: l'intero container di build ha `MENB_VERIFY_TIMEOUT` secondi (predefinito 1800); allo scadere il client Docker riceve SIGTERM, dopo 10 s SIGKILL, e la verifica fallisce. Ogni altro comando esterno dello script sull'host (`id`, `mkdir`, `rm`, i comandi `docker` di pulizia) ha il limite `MENB_VERIFY_SHORT_TIMEOUT` (predefinito 60 s). Il limite è implementato in `quality/limite.sh` (senza `timeout`, che su macOS manca), condiviso con `quality/regressioni-verify.sh`. L'output dei comandi sotto limite va in file di una cartella privata della corsa (`$TMPDIR/menb-<corsa>`, creata con `mkdir`, rimossa alla fine), non in `$(...)`: un processo figlio sopravvissuto all'arresto terrebbe aperta la pipe e l'attesa non avrebbe limite.
13. Pulizia: alla fine, riuscita o fallita, anche se lo script riceve INT, TERM o HUP o scade il limite, `verify.sh` ferma il client Docker in corso, rimuove il container di build se esiste ancora (prima, perché non avvii altri container) e i container con l'etichetta `menb.verify.run=<corsa>` della propria corsa, poi verifica con un nuovo elenco che non ne resti nessuno. Se ne trova, li rimuove e fallisce comunque; se Docker non restituisce l'elenco, o lo restituisce in un formato inatteso, l'assenza non è provata e la verifica fallisce. L'identificativo della corsa (`verify-<pid>-<casuale>`) compare nel log; i residui di altre corse non vengono toccati.
14. Controllo manuale dei residui di tutte le corse: `docker ps -a --filter label=menb.verify.run`.

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
- **Ryuk disattivato** (`TESTCONTAINERS_RYUK_DISABLED=true`): il container che Testcontainers usa per pulire resterebbe acceso una decina di secondi dopo la fine e non si distingue da quello di altre sessioni. La pulizia la fa `verify.sh`, per etichetta di corsa (punto 13 sopra); il test etichetta il container con `menb.verify.run`, letta dalla variabile `MENB_VERIFY_RUN_ID`. Così non si scarica nemmeno l'immagine di Ryuk, fissata solo per tag dentro Testcontainers.

Rischi:

- **Chi ha accesso al socket di Docker controlla Docker**, e quindi di fatto l'host (può avviare container privilegiati e montare qualunque cartella). Nel container di build gira tutto ciò che Maven esegue: test, plugin, dipendenze scaricate da Maven Central. Una dipendenza compromessa avrebbe lo stesso potere. È lo stesso livello di fiducia che si dà già a `./verify.sh`, che usa Docker sull'host; non va eseguito su codice di cui non ci si fida.
- I test possono creare container, reti e volumi sul daemon dell'host, visibili e in conflitto con quelli dell'utente. Il test usa porte scelte da Docker e un'etichetta propria; la pulizia per etichetta copre i container, non reti o volumi creati da test futuri, che vanno etichettati allo stesso modo.
- Il socket deve essere `/var/run/docker.sock` sul daemon. Con daemon remoti (`DOCKER_HOST=tcp://…`), Docker rootless o altre configurazioni il percorso cambia: non sono supportati e il test fallisce, senza essere saltato.
- Se lo script viene ucciso con SIGKILL la pulizia non avviene (senza Ryuk nessuno rimuove i container): si controlla con il comando del punto 14.

Prove: su macOS, Docker Desktop 29.9.2 (arm64), e in GitHub Actions, `ubuntu-latest` con Docker 29.4.2 (amd64); esiti nella PR dell'issue #15.

## `quality/regressioni-verify.sh`: regressioni di `./verify.sh`

Si esegue a richiesta (non fa parte di `./verify.sh` né della CI obbligatoria), da un albero di lavoro pulito: `./quality/regressioni-verify.sh`.

1. Esegue `./verify.sh` senza mutazioni: deve riuscire, altrimenti i casi negativi fallirebbero per la ragione sbagliata.
2. Poi un caso per volta, ciascuno con il proprio limite di tempo (`MENB_REGRESSIONI_TIMEOUT`, predefinito 1800 s) e con il controllo del codice di uscita **e** del messaggio atteso:

| Caso | Mutazione | Atteso |
| --- | --- | --- |
| `repackage-rimosso` | plugin `spring-boot-maven-plugin` tolto da `carddemo-online/pom.xml` (non più l'intero blocco `<build>`: dal #27 contiene anche SpotBugs, il cui rapporto mancante fermerebbe la corsa prima del controllo dei jar; modifica dichiarata), con il jar eseguibile della corsa di base presente | codice ≠ 0, `attesi esattamente 1 jar eseguibile in carddemo-online/target, trovati 0` |
| `rapporto-incompleto` | `docker` sul `PATH` che inoltra al vero `docker` e, nel solo `docker run`, mette nel container di build un `mvn` che esegue il vero Maven e poi tronca a metà il rapporto del test di integrazione | codice ≠ 0, `non e' XML ben formato e completo`, `rapporto del test di integrazione non valido` |
| `rapporto-altra-corsa` | come sopra, ma il rapporto viene sostituito da quello completo e riuscito della corsa di base | codice ≠ 0, `il rapporto non e' della corsa corrente`, `rapporto del test di integrazione non valido` |
| `test-rotto` | un test che fallisce, aggiunto in `carddemo-domain` | codice ≠ 0, il test nell'elenco dei fallimenti di surefire, `mvn verify fallito` |
| `id-fallisce` | `id` sul `PATH` che esce con 42 | codice ≠ 0, `id -u fallito` |
| `id-bloccato` | `id` sul `PATH` che non ritorna (un processo figlio che dura un'ora); `MENB_VERIFY_SHORT_TIMEOUT=5`; limite del caso 90 s | codice ≠ 0 entro il limite, `superato il limite di 5s: id -u`, `id -u fallito` |
| `docker-fallisce` | `docker` sul `PATH` che esce con 42 | codice 42, `container di build terminato con codice 42` |
| `docker-irraggiungibile` | `docker` sul `PATH` che inoltra tutto al vero `docker` ma toglie il montaggio del socket dal container di build: Docker funziona sull'host, non dentro Maven | codice ≠ 0 entro il limite, `Could not find a valid Docker environment`, fallimento di `PostgresIntegrazioneTest`, `mvn verify fallito` |
| `git-bloccato` | questo stesso script, con `git` sul `PATH` che non ritorna e `MENB_REGRESSIONI_SHORT_TIMEOUT=5`; limite del caso 90 s | codice ≠ 0 entro il limite, `superato il limite di 5s: git -C`, `git status fallito` |

Nei casi `rapporto-incompleto`, `rapporto-altra-corsa` e `docker-irraggiungibile` lo shim registra in un file di aver applicato la mutazione; se il file manca (per esempio perché `verify.sh` ha cambiato la forma degli argomenti), il caso fallisce invece di passare per la ragione sbagliata. Dopo i casi con un comando che non ritorna, i processi figli lasciati dagli shim vengono fermati.

3. Ripristina il POM e cancella il test aggiunto dopo ogni caso, e comunque all'uscita (anche per errore o INT, TERM, HUP); alla fine controlla che `git status` sia pulito.
4. Esito: 0 solo se tutti i casi danno l'esito atteso e l'albero è pulito; l'ultima riga è `== REGRESSIONI RIUSCITE: tutti i casi rilevati` o `== REGRESSIONI FALLITE (codice N)`. Per un caso non rilevato stampa le ultime righe del suo log.
5. `MENB_REGRESSIONI_LOGS=<cartella esistente>` conserva il log di ogni caso (`<caso>.log`).
6. Ogni comando esterno dello script (`git`, `mkdir`, `cp`, `rm`, `chmod`, `./verify.sh`) ha un limite di tempo: `MENB_REGRESSIONI_SHORT_TIMEOUT` (predefinito 60 s) per quelli brevi, `MENB_REGRESSIONI_TIMEOUT` per ogni `./verify.sh`. La cartella di lavoro si crea con `mkdir` sotto limite (non `mktemp`), con un nome unico.
7. Non si provano strumenti che restituiscono dati falsi ma ben formati (regola "Fin dove arriva la sfiducia negli script" in `CLAUDE.md`).

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
| JaCoCo (`jacoco-maven-plugin`, agente e rapporto) | 0.8.16 | `maven-metadata.xml` su Maven Central (`release` = 0.8.16, 26 ott 2026). Non gestito da Spring Boot 4.2.0 (`spring-boot-dependencies-4.2.0.pom` non lo contiene). Supporta Java 21; verificato eseguendo l'agente sul JDK 21 dell'immagine di build |
| SpotBugs (`spotbugs-maven-plugin` 4.10.5.0, motore `spotbugs` 4.10.5) | 4.10.5.0 / 4.10.5 | `maven-metadata.xml` su Maven Central (`release` 4.10.5.0 e 4.10.5, 12 ott 2026). Non gestito da Spring Boot 4.2.0. Il motore è fissato anche come dipendenza del plugin; analizza bytecode Java 21 (verificato: i quattro moduli si analizzano senza errori né classi mancanti) |
| Immagine PostgreSQL del test di integrazione | quella di `compose.yaml`, letta dal test | — |

Boot e tutte le librerie Spring sono quelle gestite dal parent `spring-boot-starter-parent`; nessuna versione dinamica. I digest completi sono in `docker/app.Dockerfile`, `compose.yaml` e `smoke.sh`.

## Regole sui moduli (#26)

Tre regole fanno parte di `mvn verify`, quindi di `./verify.sh` e della CI, senza modificare `verify.sh`. Nel log di Maven ogni controllo compare con il proprio nome di esecuzione.

| Regola | Strumento (versione) | Dove | Esecuzione nel log |
| --- | --- | --- | --- |
| Archi interni tra moduli (matrice sotto) | maven-enforcer-plugin 3.6.3 (gestita da Spring Boot 4.2.0), regola `bannedDependencies` | `pom.xml` di ogni modulo | `enforce (archi-interni)`, 4 moduli |
| Database incorporati vietati (H2, HSQLDB, Derby, anche transitivi o `optional`) | stesso plugin | `pom.xml` padre | `enforce (database-incorporati)` e `(database-incorporati-diretti)`, padre e 5 moduli |
| Accessi tra classi | ArchUnit 1.5.1 in `carddemo-parity` | `ArchitetturaTest` | test `ArchitetturaTest`, 2 casi |
| Tipi in virgola mobile, letterali e `var` | maven-checkstyle-plugin 3.6.0 con Checkstyle 14.4.0 | `quality/regole/checkstyle.xml` | `check (tipi-vietati)`, 4 moduli |

Versioni: il plugin Enforcer è quella gestita da Spring Boot 4.2.0; Checkstyle (plugin e libreria) e ArchUnit non sono gestiti da Spring Boot e sono fissati nel POM padre alle ultime versioni stabili su Maven Central al 27 nov 2026.

Matrice degli archi interni ammessi: `domain` nessuno; `loader`, `online`, `batch` solo `domain`; `parity` tutti. La regola vale in ogni ambito e anche per `optional`; vede le dipendenze dichiarate (non il bytecode), quindi una dichiarazione non usata viene rilevata. Per questo l'esecuzione `archi-interni` usa `searchTransitive=false`: con la ricerca transitiva Enforcer salta le dipendenze dirette `optional`. Gli archi interni indiretti non servono: ogni modulo controlla le proprie dichiarazioni.

Database incorporati: due esecuzioni, perché la ricerca transitiva (che trova H2 portato da un'altra libreria) non vede una dipendenza diretta `optional`, quella diretta sì.

ArchUnit analizza il codice di produzione dei pacchetti `io.github.ltoscano.carddemo.<domain|loader|online|batch>` (test esclusi) e fallisce se l'insieme è vuoto o se manca un modulo.

Tipi: Checkstyle legge il sorgente di produzione di `domain`, `loader`, `online`, `batch` e vieta i token `double` e `float` (campi, parametri, ritorni, locali, cast, array, `.class`), i letterali in virgola mobile (`1.0`, `1e3`, `2f`, `2d`), gli identificatori `Double`, `Float` (anche qualificati, argomenti di tipo, import), `doubleValue`, `floatValue` e alcune interfacce `Double*` di `java.util.function`, e l'identificatore `var`. Nessuna esclusione.

**Limiti dichiarati.**
- `var` è vietato come identificatore: nella grammatica di Checkstyle non è un token a sé (`LITERAL_VAR` non esiste in Checkstyle 14.4.0), quindi anche una variabile chiamata `var` viene respinta.
- Il controllo sul sorgente vede ciò che è scritto, non i tipi inferiti: `Math.sqrt(x)` usato dentro un'espressione, o un metodo di libreria che restituisce `double` il cui risultato non viene dichiarato, non sono rilevati. L'elenco dei nomi vietati è finito: un tipo in virgola mobile con un nome non elencato (per esempio `DoubleSummaryStatistics`) non è rilevato.
- Le dipendenze esterne non sono toccate dalle regole sugli archi interni. I test e `carddemo-parity` non sono soggetti al divieto dei tipi in virgola mobile.
- `-Denforcer.skip=true` o `-Dcheckstyle.skip=true` sulla riga di comando disattivano il controllo corrispondente: `./verify.sh`, la CI e lo script delle regressioni non li passano, e le regressioni verificano dal log che ogni controllo sia stato eseguito.

**Regressioni:** `./quality/regressioni-regole.sh`, a richiesta (non nella CI obbligatoria). Per ogni caso applica una mutazione al working tree (i file di prova sono in `quality/regole/casi/` e vengono copiati nel modulo solo durante il caso), esegue Maven in un container, verifica codice di uscita e messaggio del controllo atteso (non errori di compilazione o di download, non scadenza del limite) e ripristina anche su interruzione. Il working tree deve essere pulito all'avvio e lo è alla fine. Casi: base (ogni controllo eseguito, contato nel log); archi vietati (`domain→loader`, `loader→online`, `online→batch`, `batch→online`, `batch→loader` in ambito test, `online→loader` optional); H2, HSQLDB, Derby, H2 optional, HSQLDB transitivo; ArchUnit (`online` usa `batch` fallisce, `online` usa `domain` passa); dodici violazioni di tipo; sei cancelli disattivati o rimossi (`skip`, plugin tolto da un modulo, test ArchUnit eliminato) che la corsa di base deve riconoscere. Nel caso `archi-domain-loader` viene tolta anche la dipendenza `loader→domain`, altrimenti Maven rifiuterebbe il ciclo prima del controllo. Nel caso ArchUnit l'Enforcer è spento da riga di comando, altrimenti fermerebbe la corsa prima del test. Variabili: `MENB_REGOLE_TIMEOUT` (secondi per caso, predefinito 900), `MENB_REGOLE_SHORT_TIMEOUT` (altri comandi, 60).

### Aggiunte dopo la validazione 1 (#26)

- **Escape Unicode vietati.** Gli escape Unicode nel testo del sorgente (la barra rovesciata seguita da `u` e quattro cifre esadecimali) permettono di scrivere `double`, `java.lang.Double`, `float x[]` o `var` in forma che i controlli sul testo dei token non riconoscono, ma che il compilatore accetta. Checkstyle ha quindi una regola `RegexpSingleline` sul testo grezzo dei file di produzione (messaggio `UNICODE-ESCAPE-VIETATO`), commenti e stringhe compresi: anche un escape legittimo in una stringa va scritto in altro modo. Le quattro regressioni nuove (`tipi-unicode-primitivo`, `-wrapper`, `-array`, `-var`) usano sorgenti che compilano con il controllo spento (verificato con `javac` sul JDK 21 dell'immagine di build) e falliscono nell'esecuzione `tipi-vietati`.
- **Database incorporati: controllo sulle classi.** Un'esecuzione `maven-antrun-plugin` 3.2.0 (gestito da Spring Boot, id `classi-database-vietate`, fase `process-test-classes`) è dichiarata una sola volta nel POM padre, quindi gira in ogni modulo, `parity` compreso, sul classpath di test effettivo del modulo (`maven.test.classpath`: compile, runtime, provided, optional, test). Fallisce con `DATABASE-INCORPORATO-CLASSE-VIETATA` se è caricabile una classe driver nota (`org.h2.Driver`, `org.h2.jdbcx.JdbcDataSource`, `org.hsqldb.jdbc.JDBCDriver`, `org.hsqldb.jdbcDriver`, `org.apache.derby.jdbc.EmbeddedDriver`, `org.apache.derby.iapi.jdbc.AutoloadedDriver`), qualunque coordinata Maven la porti. Un primo controllo come test di `carddemo-parity` non bastava: il suo classpath non riceve le dipendenze `optional`, `test` e `provided` degli altri moduli. L'Enforcer vieta inoltre i bundle `org.apache.servicemix.bundles:org.apache.servicemix.bundles.{hsqldb,derby,h2}*`. Regressioni: `db-servicemix-hsqldb`, `db-servicemix-derby` (bundle reali, vietati dall'Enforcer), `db-classi-hsqldb` (Enforcer spento da riga di comando), e quattro casi con un JAR che contiene la sola classe `org.h2.Driver` (vuota, non è H2) sotto coordinate non elencate `it.menb:prova-driver:1.0`, nel repository locale di prova `quality/regole/casi/repo-locale/` (JAR costruito con `javac`/`jar` dal sorgente `quality/regole/casi/driver-finto/`): `classi-online-optional`, `classi-online-test`, `classi-online-provided`, `classi-domain-test`, con l'Enforcer acceso. `cancello-classi-skip` mette in skip il controllo in un modulo: la corsa di base conta le esecuzioni effettive (`Executed tasks`) e lo rileva.
  **Limite residuo:** un database incorporato con classi rinominate (shading), o con coordinate e classi non elencate, non è rilevato; l'elenco delle classi è finito. Il controllo guarda il classpath dichiarato dei moduli, non quello di un'applicazione assemblata in altro modo.
- **Dove girano i controlli.** Nella build delle immagini (`docker/app.Dockerfile`, `mvn package`) sono attivi Enforcer e Checkstyle; ArchUnit è un test di `carddemo-parity` e gira in `./verify.sh`, che è il cancello (il controllo sulle classi, invece, è un'esecuzione di Maven e gira anche nella build delle immagini: `process-test-classes` precede `package`, quindi `mvn package` lo esegue. Correzione di #27: la frase precedente, "ferma `package` prima di `process-test-classes`", era sbagliata; la prova è nella sezione "Copertura e analisi statica (#27)").
- **Ripristino delle regressioni.** In `quality/regressioni-regole.sh` ogni destinazione di una mutazione è registrata per il ripristino prima della prima scrittura. Prova: `MENB_REGOLE_PROVA_SCRITTURA_PARZIALE=1 ./quality/regressioni-regole.sh` crea un file di prova e poi esce con errore; alla fine il working tree deve essere pulito. Gli esiti di `sed`, `cp`, `awk` e `grep` sono controllati; non hanno un limite di tempo (operano su file locali), lo hanno i comandi che possono restare in attesa (Docker, Maven, git).

## Copertura e analisi statica (#27)

Due controlli nuovi su `./verify.sh`: la copertura dei test (JaCoCo) e l'analisi statica dei difetti (SpotBugs). Versioni in "Versioni scelte". Nessuna soglia di copertura finché non c'è codice di business.

Due momenti distinti. I plugin **producono** i rapporti nel ciclo ordinario di Maven (`mvn -B verify`); `./verify.sh` li **valida dopo** Maven con `quality/RapportiQualita.java` (lanciatore di sorgenti del JDK, parser XML del JDK, non `grep`). La validazione non fa parte del ciclo Maven, quindi `quality/regressioni-regole.sh`, che lancia Maven con un solo test, non ne è toccato.

### JaCoCo

| Cosa | Fase di Maven | Dove | Raggiunge, nella build delle immagini (`mvn -pl carddemo-<modulo> -am package`) |
| --- | --- | --- | --- |
| Agente (`prepare-agent`, esecuzione `agente-copertura`) | `initialize` | POM padre, quindi ogni modulo; scrive `<modulo>/target/jacoco.exec` | **Sì**, nei moduli selezionati (padre, `domain` e `online` per l'immagine online; padre, `domain` e `batch` per quella batch): l'agente gira nei loro test. Nessuno ne legge il file |
| Rapporto aggregato (`report-aggregate`, esecuzione `rapporto-aggregato`) | `verify` | solo POM di `carddemo-parity`; XML in `carddemo-parity/target/site/jacoco-aggregate/jacoco.xml` | **No**: `package` si ferma prima di `verify` e `parity` non è tra i moduli selezionati |

L'identificativo della corsa (`-Dmenb.verify.run`, già usato per il rapporto di surefire; senza, `locale`) è l'identificativo di sessione dell'agente: sta nel file di esecuzione di ogni modulo e nel rapporto aggregato.

`RapportiQualita jacoco` verifica:
- il rapporto è XML ben formato e completo; il suo `DOCTYPE` (`report.dtd`) è accettato senza alcun accesso esterno (nessun DTD esterno, nessuna entità esterna, nessun XInclude; il file `RapportoSurefire.java`, invece, continua a rifiutare ogni `DOCTYPE`);
- tutte le sue sessioni portano l'identificativo di questa corsa (un rapporto ben formato di un'altra corsa è respinto);
- per ogni modulo che ha eseguito test (esistono rapporti di surefire in `target/`; se ci sono sorgenti di test ma nessun rapporto è un errore) esiste `target/jacoco.exec`, ben formato e con sessioni di questa corsa: è la prova che l'agente era attivo **in quel modulo**. Serve perché un modulo con l'agente spento resta comunque nel rapporto aggregato, a copertura zero;
- ogni classe di produzione eseguibile compilata in questa corsa compare nel gruppo del suo modulo, anche a copertura zero. L'elenco atteso si ricava leggendo i file `.class` di `target/classes` di ogni cartella `carddemo-*`: una classe è eseguibile se non è sintetica e ha almeno un metodo con codice che JaCoCo non scarta (metodi sintetici salvo le lambda, `values`/`valueOf` degli enum, costruttore privato vuoto senza argomenti). Un modulo senza classi eseguibili (oggi `domain` e `loader`, che hanno solo `package-info`) è un'assenza lecita e stampata come tale; che l'insieme complessivo sia vuoto, invece, è un errore.

**Limiti dichiarati.** L'elenco delle classi eseguibili riproduce i filtri di JaCoCo che servono oggi: un filtro che JaCoCo applica e qui non è riprodotto (per esempio sui record) produrrebbe un falso rosso (classe attesa e assente), non un falso verde; in quel caso si estende `eseguibile()`. Non si controlla il contenuto dei contatori: nessuna soglia.

### SpotBugs

- Dove: plugin dichiarato nel POM padre (`pluginManagement`, esecuzione `analisi-difetti`, obiettivo `check`, fase `verify`; la configurazione sta a livello di plugin e non dell'esecuzione, perché `check` lancia in fork l'obiettivo `spotbugs` con l'esecuzione predefinita, che non riceve quella di `analisi-difetti`: così effort, soglia e filtro erano ignorati, scoperto provando un filtro di esclusioni) e riattivato dai quattro moduli di produzione (`domain`, `loader`, `online`, `batch`); `parity` non ha codice di produzione. Nella build delle immagini **non gira**: `package` precede `verify`.
- Soglia: `threshold=Medium` (segnala difetti a confidenza media e alta, esclude la bassa, che è rumorosa) ed `effort=Max` (analisi più approfondita: il codice è poco, il costo non pesa). Nessun limite sul grado del difetto (`maxRank` predefinito, 20). Motivo: sono i valori che segnalano per intero quanto SpotBugs considera un difetto probabile, senza il rumore della confidenza bassa; prima del codice di business si parte stretti e si allenta, con motivo, solo davanti a falsi positivi reali. Da riconsiderare quando arriva il codice.
- Un difetto alla soglia fa fallire `mvn verify` (`failOnError`), quindi `./verify.sh`.
- Esclusioni: oggi **nessuna**. Un file di esclusioni è ammesso solo come `quality/regole/spotbugs-esclusioni.xml`, configurato nel POM padre (`excludeFilterFile`), con un commento XML con il motivo subito prima di ogni `<Match>`; `RapportiQualita spotbugs` respinge il file senza motivo, un filtro configurato senza il file o con un altro nome, e un file non configurato.
- `RapportiQualita spotbugs` verifica, per ogni modulo con `src/main/java`: esiste `target/spotbugsXml.xml`, ben formato; l'`analysisTimestamp` è successivo all'inizio di questa corsa (letto con `date` nel container prima di Maven); zero errori di analisi e zero classi mancanti; zero difetti; ogni classe compilata del modulo (anche `package-info`) ha una voce `ClassStats`, cioè è stata davvero analizzata.
- SpotBugs non ha segnalato difetti nell'esistente: nessuna correzione al codice di produzione, nessuna esclusione.

### Build delle immagini: cosa si è osservato

`docker build -f docker/app.Dockerfile --build-arg MODULE=online .` (e `batch`), con `--progress=plain`, il 27 nov 2026. Ordine dei moduli: `carddemo-parent`, `carddemo-domain`, poi `carddemo-online` (o `carddemo-batch`). In ciascuno compaiono, nel log di `mvn package`: `enforcer`, `checkstyle` (nei moduli), `jacoco:0.8.16:prepare-agent (agente-copertura)` con `sessionid=locale`, `antrun:3.2.0:run (classi-database-vietate)` con `Executed tasks`, e `surefire:test` con i test di `domain` e `online`/`batch`. **Non** compaiono `jacoco:report-aggregate`, `spotbugs`, `carddemo-loader`, `carddemo-parity`. Quindi:
- il controllo sulle classi dei database (fase `process-test-classes`) **gira** nella build delle immagini, nei moduli selezionati (padre incluso); la frase di #26 secondo cui `package` si ferma prima di `process-test-classes` era sbagliata, perché quella fase precede `package`;
- l'agente JaCoCo gira (i test sono eseguiti in immagine), ma il rapporto aggregato e SpotBugs no: sono controlli di `./verify.sh` e della CI.

### Regressioni: `quality/regressioni-copertura.sh`

A richiesta (non nella CI obbligatoria), da un albero pulito: `./quality/regressioni-copertura.sh`. Corsa di base di `./verify.sh` con verifica di completezza (nel log: 6 `prepare-agent`, 1 `report-aggregate`, 4 `spotbugs:check` e 4 `BugInstance size is 0`, e le righe che `RapportiQualita` stampa: 5 prove dell'agente, 1 rapporto aggregato, 4 rapporti SpotBugs); poi una mutazione per caso, con ripristino anche su interruzione. Tutte le alterazioni passano da `./verify.sh`; per quelle sui rapporti un `mvn` messo nel container esegue il vero Maven e poi altera il rapporto (lo shim registra di averlo fatto, altrimenti il caso fallisce). Ogni caso controlla codice di uscita, messaggio atteso e assenza di marcatori di un altro fallimento (compilazione, download, limite di tempo), e "BUILD SUCCESS" dove Maven deve riuscire.

| Caso | Mutazione | Atteso da `./verify.sh` |
| --- | --- | --- |
| `rapporto-assente`, `rapporto-troncato`, `rapporto-altra-corsa` | rapporto aggregato rimosso, dimezzato, sostituito con quello della corsa di base | `rapporto JaCoCo assente`, `non e' XML ben formato e completo`, `non e' della corsa corrente` |
| `rapporto-senza-modulo`, `rapporto-senza-classe` | gruppo di `carddemo-online` svuotato; tolta la sola classe `InstallationCheckJobConfig` di `carddemo-batch` (il modulo resta presente) | `il modulo carddemo-online ha 1 classi eseguibili ... manca`, `classe ...InstallationCheckJobConfig di carddemo-batch assente` |
| `rapporto-aggregato-skip` | `report-aggregate` in skip in `parity` | `rapporto JaCoCo assente` |
| `esecuzione-troncata` | `jacoco.exec` di `online` troncato | `file di esecuzione ... troncato` |
| `agente-spento-online`, `-batch`, `-domain`, `-loader` | agente in skip in un modulo, due con codice e due senza righe di produzione | `agente JaCoCo non attivo in carddemo-<modulo>` (Maven verde, aggregato con il modulo a zero) |
| `agente-residuo-online` | agente spento in `online` e, dopo Maven, il `jacoco.exec` sano di un'altra corsa rimesso al suo posto | `sessione 'verify-...' non della corsa corrente` |
| `difetto-domain`, `-loader`, `-online`, `-batch` | classe con difetto: `NP_ALWAYS_NULL`, `EC_UNRELATED_TYPES`, `RV_RETURN_VALUE_IGNORED`, `ES_COMPARING_PARAMETER_STRING_WITH_EQ` | `spotbugs ... check (analisi-difetti) on project carddemo-<modulo>: failed with 1 bugs`, il nome del difetto, `mvn verify fallito` |
| `spotbugs-assente`, `-troncato`, `-altra-corsa`, `-senza-classe` | rapporto SpotBugs rimosso, dimezzato, sostituito con quello di base, privo della voce di una classe | `rapporto SpotBugs assente`, `non leggibile o non e' XML`, `non e' di questa corsa`, `classe ... non analizzata` |
| `esclusione-senza-motivo`, `esclusione-con-motivo` | file di esclusioni senza e con commento di motivo | respinto; accettato (e il difetto escluso non fa fallire nulla) |
| `cancello-spotbugs-skip-loader`, `-batch`, `cancello-spotbugs-padre-rimosso` | SpotBugs in skip in un modulo; tolto dal POM padre | `rapporto SpotBugs assente per carddemo-<modulo>` |
| `cancello-controllo-jacoco-rimosso`, `cancello-controllo-spotbugs-rimosso` | la chiamata a `RapportiQualita` tolta da `verify.sh`: tutto resta verde (codice 0) | la verifica di completezza della corsa di base rileva che le righe del controllo mancano |
| `controprova-lecita` | classe nuova senza difetti, con un test | nessun fallimento; `domain` mostra 1 classe eseguibile e 2 classi analizzate |

Variabili: `MENB_COPERTURA_TIMEOUT` (secondi per ogni `./verify.sh`, 1800), `MENB_COPERTURA_SHORT_TIMEOUT` (altri comandi, 60), `MENB_COPERTURA_LOGS` (cartella dei log di ogni caso). Non si provano strumenti che restituiscono dati falsi ma ben formati (regola di `CLAUDE.md`).
