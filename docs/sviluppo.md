# Sviluppo: costruire, verificare, avviare

Prerequisiti sull'host: Docker (con Compose v2), git e bash. Nessun JDK, Maven o PostgreSQL locale.

1. Clona con i submodule: `git clone --recurse-submodules <url>` (o `git submodule update --init`).
2. La verifica è divisa in due comandi, gli stessi della CI:
   - `./verify.sh`: build e test, senza servizi esterni;
   - `./smoke.sh`: avvio reale dello stack con Compose, salute, job batch, pulizia.

## `./verify.sh`: build e test

1. Dentro `maven:3.9.16-eclipse-temurin-21` cancella i `target/` precedenti ed esegue `mvn -B verify` (compila e prova i cinque moduli). Se la cancellazione fallisce, la verifica si ferma prima di Maven.
2. Controlla che `carddemo-online` e `carddemo-batch` abbiano esattamente un jar eseguibile (`*-exec.jar`).
3. Non avvia alcun processo applicativo: con PostgreSQL le applicazioni non partono senza database, quindi l'avvio è compito di `./smoke.sh`.
4. I due test di contesto (`OnlineApplicationTest`, `BatchApplicationTest`) caricano il contesto Spring senza database, con il profilo `test` (`src/test/resources/application-test.properties`), che esclude l'autoconfigurazione della sorgente dati. Nessun database in memoria o incorporato. Senza sorgente dati Spring Batch usa da sé un archivio dei metadati senza persistenza.
5. Esito: codice 0 se tutto passa, diverso da 0 al primo errore.
6. La cache delle dipendenze Maven sta nel volume Docker `menb-build-m2` (variabile `MENB_BUILD_CACHE_VOLUME` per cambiarlo); `docker volume rm menb-build-m2` la azzera.
7. A fine corsa solo le cartelle `target/` tornano all'utente dell'host; un errore di `chown` fa fallire la verifica.
8. Moduli: `domain` (nessuna dipendenza), `loader`, `online`, `batch` (solo da `domain`), `parity` (da tutti). `online` e `batch` producono un jar ordinario e uno eseguibile con classificatore `exec`.
9. Ispezione delle dipendenze: `docker run --rm -v menb-build-m2:/root/.m2 -v "$PWD":/workspace -w /workspace maven:3.9.16-eclipse-temurin-21 mvn -B dependency:tree`.

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
6. Alla fine, anche se un passo è fallito, esegue `down --volumes --remove-orphans`; poi verifica per etichetta che non restino container (anche arrestati), reti o volumi. Se ne restano li rimuove per etichetta e fallisce comunque.
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

Boot e tutte le librerie Spring sono quelle gestite dal parent `spring-boot-starter-parent`; nessuna versione dinamica. I digest completi sono in `docker/app.Dockerfile`, `compose.yaml` e `smoke.sh`.
