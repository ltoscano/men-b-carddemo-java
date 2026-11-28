APPROVATA CON RISERVE

Validazione sullo SHA `74a979dbadf852cfa85c4e465ae2f119885d5ffc`.

| Rilievo del primo giro | Stato | Comando / controesempio rieseguito | Esito |
|---|---|---|---|
| 1 — lettura indipendente | **Chiuso** | Varianti compilate A+B e A+C, quindi `dati/run.sh` | Entrambe respinte: rispettivamente da `IDXLEGGI` e `IDXDUMP`, al byte 181. Letture per chiave sbagliate respinte anche eliminando il controllo interno della chiave. [Log](/tmp/menb-val58b-logs/mutations.log). |
| 2 — invalidazione preliminare | **Chiuso** | Da indice sano: ingresso, attesi, build e binario assenti; `DATI_TIMEOUT=no` | Ogni comando termina con 1 e rimuove il risultato stabile. Provati anche errori nella preparazione dell’immagine e nel controllo del legacy. [Log](/tmp/menb-val58b-logs/lifecycle.log). |
| 3 — pubblicazione anticipata | **Chiuso** | Sonda durante l’ultima lettura; errore della lettura e della rinomina | Percorso stabile assente durante la verifica; pubblicazione mediante rinomina dello **stesso inode**. Entrambi gli errori lasciano assenti risultato stabile e file in verifica. [Log](/tmp/menb-val58b-logs/publication.log). |
| 4 — sostituzione fra dimensione e apertura | **Non chiuso; limite già accettato** | `stat` reale seguito da rename dell’ingresso da 15.000 a 14.999 byte | Ancora 50 scritture e uscita 0. Confermo il limite senza riaprirlo come difetto. [Log](/tmp/menb-val58b-logs/race.log). |
| 5 — esiti ignorati | **Chiuso** | Sonde `cmp` 0/1/42, `wc@2`, `rm` nelle trap e nelle pulizie | Errori propagati; nessuna alterazione nulla accettata come valida. Passano anche le prove sulle quattro invocazioni di `rm` in `run.sh`. [Sonde](/tmp/menb-val58b-logs/helpers.log), [controllo completo](/tmp/menb-val58b-logs/dati-check.log). |
| 6 — documentazione contraddittoria | **Chiuso** | Lettura di `oracle/README.md:244` | Il paragrafo cita ora anche `dati`. |

`IDXLEGGI` apre realmente l’indice, usa organizzazione, accesso, chiave e record del `SELECT`/`FD` di `CBACT01C` e non condivide implementazione con caricatore o `IDXDUMP`. Il **mio programma COBOL** ha verificato il file pubblicato: 50 record, 15.000 byte identici, EOF 10 e tutte le 50 letture per chiave corrette. [Sorgente](/tmp/menb-val58b-logs/VALREAD.cbl), [esito](/tmp/menb-val58b-logs/independent.txt).

Con entrambi i lettori finti capaci di riusare una copia precedente, `dati` può ancora pubblicare un indice alterato; nella variante provata, però, **`dati --check` fallisce** sulla prova della rilettura accorciata. Accetto il limite della sostituzione coordinata di entrambe le vie; non richiedo un terzo lettore. [Evidenza](/tmp/menb-val58b-logs/mutant-validation.log).

Nuovo rilievo:

- **Minore — copertura incompleta dell’EOF di `IDXLEGGI`.** Nella copia isolata ho aggiunto `OR N-RECORD = 50` alla condizione del ciclo: il lettore termina senza effettuare la lettura che dovrebbe restituire 10, ma build e `dati --check` passano ancora, con **102 negative e 6 controprove**. [Mutazione](/tmp/menb-val58b-logs/noeof-mutation.patch), [log](/tmp/menb-val58b-logs/noeof-check.log). Il sorgente consegnato raggiunge correttamente EOF; il difetto riguarda la protezione dalla regressione. **Falso verde:** sì, della suite rispetto all’EOF del nuovo lettore. **Oracle infedele:** non dimostrato da questa omissione; `IDXDUMP` mantiene il controllo effettivo. **Correzione richiesta, versionata:** controllo esplicito dello stato 10 prima di `CLOSE` e prova negativa specifica che interrompa `IDXLEGGI` dopo il cinquantesimo record.

I quattro comandi richiesti sono stati eseguiti una volta sull’albero consegnato:

| Comando | Esito |
|---|---|
| `./analysis/run.sh oracle-dati --check` | 0; 156 prove negative |
| `./oracle/run.sh build` | 0; 29 programmi |
| `./oracle/run.sh dati --check` | 0; 102 negative, 6 controprove |
| `./oracle/run.sh --all --check` | 0; tutti i passi superati |

I conteggi coincidono **per tutti i dieci passi** con la [CI della PR sullo SHA attuale](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46103668277). [Conteggi locali](/tmp/menb-val58b-logs/local-counts.txt). Anche `analysis-check`, `verify` e `smoke` risultano verdi per la PR.

Diff interamente letto e nel perimetro. Modifiche agli attesi di `dati` giustificate dalle nuove letture e dalla verifica prima della pubblicazione; impronta del contenuto invariata. Record, elenco, tabella e attesi a mano invariati rispetto al primo giro.

Nessuna modifica versionata, nessun commit. Resta soltanto `?? .validazione/`, già presente all’inizio. Risorse Docker `menb-val58b-` rimosse; risorse condivise conservate.