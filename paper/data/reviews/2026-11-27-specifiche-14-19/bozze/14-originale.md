## Obiettivo
Da clone pulito, `docker compose up` deve portare su un'applicazione vuota ma sana: database, servizio online, runner batch. Da qui in poi esiste sempre qualcosa che gira.

## Dipendenze e perimetro
- Dipende da: #13.
- Cartelle e file coinvolti: `compose.yaml`, `docker/`, `smoke.sh`, `.github/workflows/ci.yml` (solo l'aggiunta del passo di smoke), `docs/sviluppo.md`, configurazione Spring minima in `carddemo-online/` e `carddemo-batch/`.
- Fuori ambito: schema e dati (Wave 1), logica di business, strumenti di qualità (#15).

## Specifica
- Immagini dell'applicazione con build multi-stage, basi a versione fissata, utente non-root.
- Servizi: `db` (PostgreSQL a versione fissata, volume nominato), `online` (espone la porta HTTP e un endpoint di salute), `batch` (profilo dedicato: si avvia a comando, esegue un job vuoto e termina con codice 0).
- Healthcheck su `db` e `online`; `online` parte solo quando `db` è sano.
- Credenziali da variabili d'ambiente con valori di sviluppo dichiarati come tali; nessun segreto nel repository.
- `./smoke.sh`: avvia lo stack, attende lo stato sano, interroga l'endpoint di salute, esegue il job batch vuoto, spegne e rimuove i volumi. Fallisce con messaggio chiaro a ogni passo non riuscito.

## Criteri di accettazione (verificabili)
- [ ] Da clone pulito, solo Docker: `./smoke.sh` termina con codice 0.
- [ ] Fermando `db` durante lo smoke test, lo script fallisce (verificato e descritto nella PR).
- [ ] La CI esegue `./verify.sh` e `./smoke.sh`.
- [ ] Il diff tocca solo il perimetro dichiarato.

## Strategia di rollback
Revert della PR.

## Limiti per l'agente
- Nessuna tabella, nessun endpoint oltre a quello di salute.

