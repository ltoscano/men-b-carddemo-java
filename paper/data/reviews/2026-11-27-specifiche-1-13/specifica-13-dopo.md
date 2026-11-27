## Obiettivo
Creare lo scheletro del progetto Java: cinque moduli vuoti ma compilabili, un comando unico di verifica che gira solo in container, e la CI che esegue quello stesso comando.

## Dipendenze e perimetro
- Dipende da: nessuna. Procede in parallelo alla Wave 0A.
- Cartelle e file coinvolti (i soli modificabili): `pom.xml`, `carddemo-domain/`, `carddemo-loader/`, `carddemo-online/`, `carddemo-batch/`, `carddemo-parity/`, `verify.sh`, `.github/workflows/ci.yml`, `docs/sviluppo.md`, `.gitignore`, `.dockerignore`.
- Fuori ambito: Docker Compose e immagini dell'applicazione (#14), strumenti di qualità (#15), tipi di dominio e contratti (#16), qualsiasi logica di business, accesso al database, `legacy/`, `analysis/`, `oracle/`, `paper/`.

## Specifica
- Java 21. Spring Boot nell'ultima versione stabile (GA, non milestone né RC) compatibile con Java 21 alla data del lavoro, **fissata** nel `pom.xml` padre; Spring Batch e le altre librerie Spring nella versione gestita da quella di Boot, senza sovrascritture. Nessuna versione dinamica o `LATEST`. `docs/sviluppo.md` riporta versioni, data e fonte consultata per la scelta.
- Coordinate: `groupId` `io.github.ltoscano.carddemo`, package base uguale.
- Moduli e dipendenze ammesse tra moduli:

| Modulo | Ruolo | Può dipendere da |
| --- | --- | --- |
| `carddemo-domain` | tipi e contratti condivisi | nessun altro modulo |
| `carddemo-loader` | caricamento dei dati | `domain` |
| `carddemo-online` | servizio online (applicazione Spring Boot avviabile) | `domain` |
| `carddemo-batch` | job batch (applicazione Spring Boot avviabile) | `domain` |
| `carddemo-parity` | test di parità | tutti |

- Ogni modulo contiene il minimo per compilare e un test che passa.
- `carddemo-online`: applicazione web con endpoint di salute (`/actuator/health`), quindi con le dipendenze per HTTP e Actuator già presenti. `carddemo-batch`: applicazione che si avvia, non esegue alcun job e termina con codice 0.
- Nessuna delle due richiede un database in questa issue, e **non è ammesso un database in memoria o incorporato** per soddisfare l'avvio. Se la versione di Spring Batch scelta pretende un archivio per i propri metadati, si usa un archivio senza persistenza fornito da Spring Batch, se esiste in quella versione, oppure si rinvia l'attivazione di Batch a #14 lasciando la dipendenza dichiarata; la scelta è descritta in `docs/sviluppo.md`.
- Artefatti: `online` e `batch` producono sia un jar eseguibile sia un jar ordinario utilizzabile come dipendenza; `carddemo-parity` dipende dai jar ordinari.
- La issue #14 potrà modificare i `pom.xml` dei moduli `online` e `batch` e la loro configurazione per aggiungere l'accesso a PostgreSQL: qui non va anticipato.
- `./verify.sh` è l'unico comando di verifica: esegue `mvn -B verify` dentro un'immagine Maven ufficiale con JDK 21 a versione fissata, montando il repository; poi, sempre in container, **avvia i jar eseguibili effettivamente prodotti**: `online` deve rispondere sano sull'endpoint di salute entro un tempo limite, `batch` deve terminare con codice 0. Non richiede JDK né Maven sull'host. Conserva la cache delle dipendenze tra esecuzioni in un volume Docker, non in una cartella dell'host fuori dal repository.
- `.github/workflows/ci.yml`: a ogni push e pull request esegue `./verify.sh` e fallisce se fallisce. Il checkout include i submodule.
- `docs/sviluppo.md`: come costruire e verificare, in dieci righe.

## Invarianti da preservare
- Nessun file fuori dal perimetro modificato. `README.md` e `CLAUDE.md` non si toccano.

## Criteri di accettazione (verificabili)
- [ ] Da clone pulito, con solo Docker: `./verify.sh` termina con codice 0.
- [ ] Rompendo un test in un modulo qualsiasi, `./verify.sh` termina con codice diverso da 0 (verificato dall'Esecutore e descritto nella PR; la rottura non va lasciata nel codice).
- [ ] `mvn dependency:tree` (in container) mostra che `domain` non dipende da altri moduli del progetto e che `online`, `batch`, `loader` dipendono solo da `domain`.
- [ ] `./verify.sh` fallisce se il jar di `online` non risponde sano o se `batch` termina con codice diverso da 0 (verificato dall'Esecutore, descritto nella PR).
- [ ] Il workflow è presente nella PR e la CI sulla PR è verde.
- [ ] `git diff --stat origin/main...HEAD` tocca solo i file del perimetro.

## Strategia di rollback
Revert della PR.

## Limiti per l'agente
- Nessuna classe di dominio, entità, repository, controller o job: solo lo scheletro.
- Nessuna dipendenza oltre a Spring Boot, Spring Batch e ciò che serve ai test di base. Niente Lombok, niente generatori di codice.
- Se il push del file di workflow è rifiutato per permessi del token, non aggirare: aprire la PR **come bozza** senza il workflow, scrivere in evidenza che la consegna è bloccata e perché, e fermarsi. L'issue non è conclusa finché il workflow non è nella PR e la CI non è verde.
