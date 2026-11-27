# Sviluppo: costruire e verificare

Prerequisiti sull'host: Docker e git. Nessun JDK o Maven locale.

1. Clona con i submodule: `git clone --recurse-submodules <url>` (o `git submodule update --init`).
2. Esegui `./verify.sh`: è l'unico comando di verifica, lo stesso della CI.
3. Dentro `maven:3.9.16-eclipse-temurin-21` esegue `mvn -B verify` (compila e prova i cinque moduli).
4. Poi, sempre in container, avvia i jar eseguibili (`*-exec.jar`): `carddemo-online` deve rispondere `UP` su `/actuator/health` entro 90 s; `carddemo-batch` deve terminare con codice 0.
5. Esito: codice 0 se tutto passa, diverso da 0 al primo errore.
6. La cache delle dipendenze Maven sta nel volume Docker `menb-build-m2` (variabile `MENB_BUILD_CACHE_VOLUME` per cambiarlo); `docker volume rm menb-build-m2` la azzera.
7. Il tempo di attesa della salute si regola con `MENB_HEALTH_TIMEOUT` (secondi).
8. I file prodotti in `target/` tornano all'utente dell'host a fine corsa.
9. Moduli: `domain` (nessuna dipendenza), `loader`, `online`, `batch` (solo da `domain`), `parity` (da tutti). `online` e `batch` producono un jar ordinario e uno eseguibile con classificatore `exec`.
10. Ispezione delle dipendenze: `docker run --rm -v menb-build-m2:/root/.m2 -v "$PWD":/workspace -w /workspace maven:3.9.16-eclipse-temurin-21 mvn -B dependency:tree`.

## Versioni scelte

Verificate il 27 novembre 2026.

| Componente | Versione | Fonte consultata |
| --- | --- | --- |
| Java | 21 | requisito del progetto |
| Spring Boot | 4.2.0 (GA; 4.2.0-RC1 e RC2 scartate) | `maven-metadata.xml` di `spring-boot-starter-parent` su Maven Central (`release` = 4.2.0, aggiornato il 19 nov 2026); `4.2.0` è una versione di rilascio, il suo parent richiede Java 17 o superiore, quindi compatibile con 21 |
| Spring Batch | 6.1.0 (gestita da Boot, nessuna sovrascrittura) | `mvn dependency:tree` |
| Immagine di build | `maven:3.9.16-eclipse-temurin-21` (Maven 3.9.16, JDK 21) | tag dell'immagine ufficiale `maven` su Docker Hub |

Boot e tutte le librerie Spring sono quelle gestite dal parent `spring-boot-starter-parent`; nessuna versione dinamica.

## Spring Batch senza database

Con Spring Batch 6.1.0 `carddemo-batch` si avvia, non esegue alcun job e termina con codice 0 senza alcun `DataSource`: né esterno né incorporato. Si usa quindi `spring-boot-starter-batch` (senza `-jdbc`), che non porta un archivio dei metadati su database. L'archivio persistente arriverà con #14.
