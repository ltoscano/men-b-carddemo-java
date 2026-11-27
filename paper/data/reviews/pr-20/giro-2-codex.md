BOCCIATA

Sul commit `78333409`, il rilievo originale è corretto. Resta però un **falso verde riprodotto per container, reti e volumi** quando l’elenco Docker filtrato restituisce vuoto con codice 0 pur esistendo una risorsa etichettata.

Ho eseguito personalmente le prove seguenti. Gli shim agiscono tramite `PATH`; i controlli indipendenti usano `/usr/local/bin/docker`. Progetto smoke dedicato: `menb-val20`. Timeout esterno di 240 s per prova, salvo smoke iniziale 300 s, avvio ordinario 180 s e comandi ausiliari 10–60 s. Log, shim e durate sono in `.validazione/prove/`.

| Comando / prova eseguita | Esito osservato | Durata |
|---|---|---:|
| `./verify.sh` | 0; build e test riusciti, entrambi i jar presenti | 40,36 s |
| `./smoke.sh` | 0; salute e due esecuzioni batch verificate | 10,13 s |
| `docker create --label …` arrestato; `PATH=<sed→42>:$PATH ./smoke.sh` | 1; residuo rilevato e rimosso | 0,93 s |
| `./smoke.sh`, shim `docker ps -a … →42` in pulizia | 1; elenco fallito segnalato | 10,61 s |
| `./smoke.sh`, shim `docker network ls … →42` in pulizia | 1; elenco fallito segnalato | 10,58 s |
| `./smoke.sh`, shim `docker volume ls … →42` in pulizia | 1; elenco fallito segnalato | 10,01 s |
| `./smoke.sh`, elenchi container/reti/volumi malformati con codice 0 | 1 in tutti e tre i casi | 9,94 / 9,87 / 10,04 s |
| `./smoke.sh`, elenco container vuoto/0 con container reale presente | **0; `SMOKE RIUSCITO`, container residuo** | 10,07 s |
| `./smoke.sh`, elenco reti vuoto/0 con rete reale presente | **0; `SMOKE RIUSCITO`, rete residua** | 9,66 s |
| `./smoke.sh`, elenco volumi vuoto/0 con volume reale presente | **0; `SMOKE RIUSCITO`, volume residuo** | 9,80 s |
| `./smoke.sh`, shim guasti per `sed`, `wc`, `tr`, `dirname`, `head`, `tail`, `cut`, `awk` | 0; utility eliminate, pulizia effettiva | 9,90 s |
| `./smoke.sh`, `sleep →42` | 1; nessun falso verde | 0,30 s |
| `./verify.sh`, `id -u →42`; `id -g →42` | 1 prima di Docker | 0,15 / 0,01 s |
| `./verify.sh`, `id` vuoto/0 oppure `nobody`/0 | 1; valori respinti | 0,01 / 0,01 s |
| `./verify.sh`, `docker →42` | Propaga 42 | 0,03 s |
| `./verify.sh`, `rm →42` nel container | 1 prima di Maven | 0,33 s |
| `./verify.sh`, `rm` inefficace con codice 0 | 1; rileva i `target/` rimasti | 0,28 s |
| `./verify.sh`, `chown →42` | 1 | 5,85 s |
| `./verify.sh`, `repackage` rimosso con jar residuo presente | 1; dopo pulizia manca il jar batch | 5,41 s |
| `./verify.sh`, ripristino build sana | 0 | 5,65 s |
| `chflags uchg <jar>`; `./verify.sh` | 1; `Operation not permitted`, Maven non avviato | 0,29 s |
| Rimosso flag; `repackage` rimosso con lo stesso jar residuo; `./verify.sh` | 1; jar residuo eliminato, nuovo eseguibile assente | 5,47 s |
| `./smoke.sh`, DB con healthcheck sulla porta errata | 1 al passo `avvio` | 4,23 s |
| Prima preparazione radice `DOWN` | Restituiva HTTP 503: prova non valida per il caso richiesto; interrotta e ripetuta | 40,71 s |
| `./smoke.sh`, job disabilitato | 1; zero esecuzioni invece di una | 13,13 s |
| `./smoke.sh`, job `COMPLETED`, step portato realmente a `FAILED` nel DB | 1; rileva zero step completati | 21,27 s |
| Volumi `menb-val20-Valid_9.X`, `99menb-val20`, `menb-val20_a-b.c`; `./smoke.sh` | Formati accettati; 1 per risorse preesistenti, tutte rimosse | 1,01 s |
| `./smoke.sh`, due repliche online | 1; rileva due identificativi | 21,50 s |
| `./smoke.sh`, radice `DOWN`, DB `UP`, **HTTP 200** | 1 al passo `salute` | 9,73 s |
| `docker compose -p menb-val20-ordinary up -d --build --wait --wait-timeout 120` | 0; porta configurata 63059, perché 8080 occupata | 6,81 s |
| `./smoke.sh` con stack ordinario attivo | 0; fotografie prima/dopo identiche per container, stato, porte, rete, volume e controllo DB | 11,74 s |
| `docker compose -p menb-val20-ordinary --profile batch down --volumes --remove-orphans --timeout 10` | 0 | 0,45 s |
| `docker run --rm --entrypoint id menb-val20-{online,batch} -u` | Entrambe restituiscono UID 10001 | 0,26 / 0,20 s |
| `git diff --name-status origin/main...HEAD`, confronto con patch fornita | 16 file, tutti nel perimetro; elenco coincidente | 0,01 s |
| Inventari finali con Docker reale e pulizia mirata | Nessun container, rete o volume dei due progetti; rimossi tag e cache creati dalle prove | 1,18 s |

Salvo i tre falsi verdi evidenziati, i controlli indipendenti dopo le iniezioni non hanno trovato residui. Quei tre residui sono stati rimossi manualmente dopo averne registrato l’esistenza.

**Stato del rilievo del primo giro: chiuso.** Il controesempio originale con `sed` fallito ora termina con 1 e senza residui. Il rilievo seguente usa una prova nuova.

1. **Bloccante — elenco vuoto accettato come prova sufficiente della pulizia. Falso verde: sì.**

   Evidenza in [smoke.sh:140](smoke.sh:140): `valid_ids` accetta una stringa vuota; `no_project_resources` la interpreta come assenza. Alle righe 213–215, dopo `down` riuscito, questo produce la dichiarazione di pulizia riuscita.

   Ho creato dopo il controllo iniziale una risorsa con l’etichetta del progetto, estranea ai servizi dichiarati. Il vero `down` termina con 0 lasciandola presente. Lo shim nasconde soltanto l’elenco filtrato corrispondente, restituendo vuoto/0. Risultati indipendenti:

   | Tipo | Risorsa trovata dal Docker reale dopo `SMOKE RIUSCITO` |
   |---|---|
   | Container arrestato | `4bfba97a1e16…` |
   | Rete | `86ee9d6b6c5f…` |
   | Volume | `menb-val20-hidden` |

   Riproduzione salvata: `python3 .validazione/prove/case.py list-empty-container empty-container`, analogamente `network` e `volume`.

   **Correzione richiesta:** nello scenario di guasto semantico richiesto, incrociare gli elenchi filtrati con un inventario ottenuto tramite un percorso distinto, per esempio elenco senza filtro e ispezione delle etichette, controllando gli esiti e fallendo sulle incongruenze. Aggiungere le tre prove di regressione. La dimostrazione riguarda lo shim descritto; senza iniezioni non ho osservato questo falso verde.

Ho letto entrambi i diff, gli script interi, specifica, discussione e `ci.txt`. La CI è **solo letta**: il file riporta quattro esiti `pass`; non l’ho rieseguita sul servizio remoto. Nessun altro rilievo nuovo dimostrato. Tutte le mutazioni ai sorgenti sono ripristinate; nessun commit o push.