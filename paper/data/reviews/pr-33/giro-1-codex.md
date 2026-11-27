**BOCCIATA — riprodotto un falso verde sul controllo del test d’integrazione.**

Verificato lo SHA `8e1a4a1a543b5929503c927e9a0fd5af602565f7` su macOS arm64, Docker Desktop 29.9.2. Nessun commit o push.

Tutti i comandi di prova hanno avuto un timeout esterno mio: 360 s per la verifica iniziale, 480 s per lo smoke, 720 s per l’harness, 180 s per le altre build, 5 s per le sonde di blocco. Registro con comandi completi, esiti e durate (file locale del Validatore, non conservato). Nella tabella, `E` abbrevia `<cartella locale del Validatore>`.

| Criterio / prova | Comando eseguito e condizioni | Esito osservato | Durata |
|---|---|---|---:|
| Perimetro — lettura | `rg '^diff --git' .validazione/diff.patch` | Sette file, tutti ammessi. Nessuna modifica a Compose, smoke, business o `analysis.yml` | Non misurata |
| Verifica iniziale | `./verify.sh` | **0**; PostgreSQL 18.7 avviato, scrittura/rilettura/eliminazione; test eseguito con `Skipped: 0` | 81,4 s |
| Smoke | `MENB_SMOKE_PROJECT=val33-adversarial-smoke ./smoke.sh` | **0**; salute, due esecuzioni batch e pulizia | 111,9 s |
| Harness originale | `./quality/regressioni-verify.sh`, log conservati | **0**; tutti i cinque casi rilevati; stato pulito escludendo il materiale iniziale `.validazione/` | 168,2 s |
| Solo digest diverso | `./verify.sh`, digest della 18.6 sotto il tag originale | **0**; database riporta **PostgreSQL 18.6** | 42,4 s |
| Digest inesistente | `./verify.sh`, digest composto da 64 zeri | **1**; errore nel test d’integrazione durante il recupero dell’immagine | 27,5 s |
| Solo tag diverso | `./verify.sh`, tag inventato e digest originale | **0**; riferimento modificato, contenuto **18.7**, come da specifica modificata | 23,0 s |
| Docker assente dentro Maven | `PATH="$E/nosocket:$PATH" ./verify.sh`; shim toglie soltanto il mount del socket | **1**; `PostgresIntegrazioneTest` fallisce con `Could not find a valid Docker environment` | 17,7 s |
| Test reso saltabile | Stesso comando, aggiunta temporanea di `@DisabledIf("dockerAssente")` | Maven verde; `verify.sh` **1** per `skipped=1` | 17,0 s |
| Pulizia dopo successo, eccezione e arresto JVM | `./verify.sh`, poi eccezione oppure `Runtime.halt(3)` dopo `postgres.start()` | Codici **0 / 1 / 1**; nessun residuo. Dopo `halt`, lo script rimuove il container rimasto | 19,0 / 17,2 / 15,1 s |
| Pulizia dopo SIGTERM | `python3 "$E/signal-run.py"`; segnale dopo avvio PostgreSQL | **143**; container rimosso | 16,3 s |
| Pulizia dopo timeout | `MENB_VERIFY_TIMEOUT=45 ./verify.sh`, test sospeso dopo l’avvio | **124**; container rimosso | 46,3 s |
| Isolamento da altra corsa | `docker inspect … val33-adversarial-sentinel` dopo le prove | Sentinella con `menb.verify.run=val33-foreign-run` ancora in esecuzione | 0,02 s |
| Rapporto semplicemente rimasto nel target | `./verify.sh`, rapporto precedente presente e test escluso dal POM | **1**; il vecchio rapporto viene eliminato e quello corrente risulta assente | 13,2 s |
| Rapporto precedente riproposto e troncato | `python3 "$E/stale-malformed.py"`; Maven reale, test escluso, shim ripropone la sola intestazione precedente | **0**, senza test d’integrazione né PostgreSQL: **falso verde** | 8,1 s |
| Parser del rapporto isolato | Frammento originale eseguito con XML troncato oppure contenuto malformato dopo l’intestazione | **0** in entrambi i casi | <0,01 s |
| Harness contro verifica alterata | `./quality/regressioni-verify.sh`, controllo dell’errore di `id -u` temporaneamente ignorato | **1**; segnala il messaggio atteso assente per `id-fallisce` | 32,4 s |
| Ripristino a metà caso | `python3 "$E/interrupt-harness.py"`; SIGTERM con POM realmente alterato | **143**; POM ripristinato, test rotto assente, stato pulito | 13,8 s |
| `id` bloccato | `MENB_VERIFY_TIMEOUT=1 PATH="$E/hang-id:$PATH" ./verify.sh` | Non termina entro il limite configurato; fermato dal **mio** timeout | 5,0 s |
| `git status` bloccato | `MENB_REGRESSIONI_TIMEOUT=1 PATH="$E/hang-git:$PATH" ./quality/regressioni-verify.sh` | Stesso problema; fermato dal **mio** timeout | 5,0 s |
| Output Docker malformato | `PATH="$E/malformed-docker:$PATH" ./verify.sh` | **1**; elenco invalido rifiutato | 14,4 s |
| Residui finali | `python3 "$E/final-check.py"`; elenchi Docker per ciascuna corsa | **26 corse**, nessun container di test o build rimasto | 1,0 s |
| Versioni e database | Lettura POM e analisi del classpath del rapporto iniziale | Testcontainers **2.0.5**, PostgreSQL JDBC **42.7.14**, SnakeYAML **2.7**; nessun H2/HSQLDB/Derby | 0,03 s |
| CI — sola lettura | `cat .validazione/ci.txt` | `verify` e `smoke` risultano verdi; non ho rieseguito GitHub Actions | Non misurata |
| Ripristino finale | `git diff --exit-code`; confronto con copie iniziali | **0**; resta soltanto `?? .validazione/`, già presente all’inizio | 0,2 s |

Per provare l’harness alterando `verify.sh` senza creare commit, ho temporaneamente adattato **soltanto la sua guardia sull’albero pulito** affinché ammettesse i due file deliberatamente modificati. I controlli dei casi sono rimasti invariati. Tutto è stato ripristinato.

1. **Bloccante — rapporto incompleto e precedente accettato come prova corrente. Falso verde: sì.**  
   Evidenza: [verify.sh:196](verify.sh:196), in particolare righe 208–225. Il controllo cerca un’apertura `testsuite` e quattro attributi; non valida l’XML completo, i `testcase` o l’appartenenza alla corsa corrente.

   Ho escluso realmente il test dal POM. Lo shim Maven esegue il vero Maven e poi ripropone **l’intestazione autentica, troncata**, del rapporto precedente. La verifica stampa `tests=1 skipped=0 failures=0 errors=0` e termina con **0**, mentre non viene avviato PostgreSQL. È una prova di risultato precedente e risposta incompleta, nel perimetro di sfiducia richiesto. Riproduttore (file locale del Validatore, non conservato), log (file locale del Validatore, non conservato), riscontri (file locale del Validatore, non conservato).

   **Correzione richiesta:** validare l’intero XML e i casi effettivi; associare il rapporto al `RUN_ID` corrente mediante una proprietà Maven controllata nel rapporto. Aggiungere regressioni per rapporto incompleto e rapporto riproposto. Il semplice file vecchio nel target, invece, viene già respinto dalla pulizia iniziale.

2. **Importante — attese preliminari senza limite. Falso verde: no.**  
   Evidenza: [verify.sh:37](verify.sh:37), chiamate dirette a `id`; [quality/regressioni-verify.sh:46](quality/regressioni-verify.sh:46), chiamata diretta a `git status`. I timeout configurati non coprono queste operazioni. Entrambe le sonde sono rimaste bloccate oltre il limite di un secondo e sono state terminate dal mio limite esterno.

   **Correzione richiesta:** applicare limiti anche alla preparazione e ai controlli iniziali, aggiungendo regressioni con comandi che non ritornano.

Ho letto integralmente i tre script. Le rimozioni Docker fallite non trasformano l’esito in verde: la pulizia ha già impostato il fallimento e ricontrolla l’elenco. Non ho individuato decisioni basate su pipeline di presentazione.

Il socket e il controllo sostanziale dell’host, inclusi i rischi delle dipendenze eseguite da Maven, sono descritti in `docs/sviluppo.md:48–57`. Le mancanze rispetto alla specifica sono quelle dei due rilievi: robustezza contro rapporti incompleti/riproposti e assenza di attese illimitate. Sentinella e immagini specifiche dello smoke sono state rimosse; nessuna risorsa altrui è stata rimossa.