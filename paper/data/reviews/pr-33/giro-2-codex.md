APPROVATA CON RISERVE

Validato `02a8741` su macOS arm64. Resta un rilievo importante sull’output mantenuto aperto da un figlio sopravvissuto; **non produce falsi verdi**. Nessun commit o push.

Tutte le prove hanno avuto un timeout esterno mio. Log, comandi, limiti e riproduttori (file locale del Validatore, non conservato).

| Comando e condizioni | Esito osservato | Durata |
|---|---|---:|
| `./verify.sh` iniziale | **0**; PostgreSQL 18.7, test eseguito, `Skipped: 0` | 30,3 s |
| `./quality/regressioni-verify.sh` | **0**; tutti i dieci casi, base compresa, con esito atteso; stato ripristinato | 132,1 s |
| `MENB_SMOKE_PROJECT=val33b-second-smoke ./smoke.sh` | **0**; salute, due job completati, pulizia | 40,9 s |
| Controlli iniziali Git e Docker, per nome/etichetta delle proprie corse | Nessun residuo delle otto corse; sorgenti puliti | 0,8 s |
| `./verify.sh`: test escluso dal POM, intestazione autentica del vecchio rapporto riproposta | **1**; XML incompleto respinto; test d’integrazione effettivamente non eseguito | 67,6 s |
| `./verify.sh`: `id` bloccato, ignora TERM; limite breve 2 s | **1**; timeout rilevato, poi KILL dopo la grazia prevista | 12,1 s |
| Harness: `git status` bloccato, ignora TERM; limite breve 2 s | **1**; errore nei controlli iniziale e finale | 24,2 s |
| `./verify.sh`: rapporto XML completo di un’altra corsa | **1**; identificativo della corsa diverso | 54,0 s |
| `./verify.sh`: `testcase` con `skipped`, `failure`, `error`, mantenendo i contatori della suite a zero | **1 / 1 / 1**; rilevati gli elementi nel singolo caso | 55,6 / 48,5 / 68,6 s |
| `./verify.sh`: `tests=2`, un solo `testcase` | **1**; conteggio incoerente | 34,3 s |
| `./verify.sh`: rapporto assente / vuoto | **1 / 1**; entrambe le condizioni respinte | 38,2 / 43,8 s |
| `./verify.sh`: rapporto corrente nel percorso atteso, vecchio rapporto aggiuntivo | **0**; controllato il rapporto corrente | 81,1 s |
| `./verify.sh`: vecchio rapporto nel percorso atteso, corrente aggiuntivo | **1**; il file aggiuntivo non rende accettabile quello vecchio | 34,6 s |
| `./verify.sh`: comando Java esce con 42 | **1**; errore propagato | 30,3 s |
| `./verify.sh`: Java bloccato; limite build 45 s | **124**; raggiunto Java dopo Maven riuscito, poi timeout | 46,1 s |
| `./verify.sh`: `docker ps` di pulizia bloccato | **1**; assenza dei residui dichiarata non verificabile | 56,3 s |
| `./verify.sh`: `docker rm` bloccato su una sentinella reale | **1**; residuo segnalato. Sentinella poi rimossa dal Validatore | 40,3 s |
| `id` / `git` con figlio sopravvissuto, output raccolto in file | Script terminati con **1 / 1**; figli ancora vivi, poi terminati dal Validatore | 3,0 / 6,1 s |
| `./verify.sh`, raccolta con `stdout=PIPE, stderr=STDOUT`, stesso figlio | Script già uscito con **1**, ma nessun EOF entro il timeout esterno | 8,0 s |
| `bash -o pipefail -c './verify.sh 2>&1 \| cat'`, stesso figlio | Pipeline bloccata; terminata dal timeout esterno | 8,0 s |
| Due `./verify.sh` consecutivi senza mutazioni | **0 / 0**; nessun falso rosso riprodotto | 29,4 / 33,0 s |
| `./verify.sh`: cambiato soltanto il digest con quello della 18.6 | **0**; database effettivamente PostgreSQL **18.6** | 45,4 s |
| `./verify.sh`: socket Docker tolto soltanto dentro Maven | **1**; fallimento del test con `Could not find a valid Docker environment` | 60,9 s |
| `./verify.sh`: test reso saltabile con `@Disabled` | Maven verde, verifica **1** per `skipped=1` | 40,6 s |
| `./verify.sh`: SIGTERM dopo avvio effettivo PostgreSQL | **143**; container residuo rilevato e rimosso | 60,0 s |
| Controllo finale: 59 interrogazioni Docker mirate, 28 identificativi di corsa | Nessun container proprio, rete o volume smoke rimasto | 2,1 s |
| `git diff --exit-code` finale | **0** | 0,1 s |

Lo stato Git finale conserva soltanto `?? .validazione/`, già presente inizialmente. Escludendo esclusivamente quel materiale tramite configurazione temporanea esterna, `git status` è vuoto. Ho rimosso anche le due immagini del progetto smoke dedicato; il volume cache fornito è rimasto intatto.

I due rilievi del primo giro:

- **Rapporto troncato e precedente: corretto.** Ripetuto il controesempio con esclusione reale dal POM: ora restituisce 1. Il falso verde precedente rientrava nella regola sulla sfiducia; non è più riproducibile.
- **`id` e `git status` senza limite: corretti nei controesempi originari.** Entrambi terminano con errore entro limite più grazia. Falso verde: **no**. Rientrano nella regola sulla sfiducia. Resta il nuovo caso sull’output descritto sotto.

Rilievi nuovi o residui:

1. **Importante — un figlio sopravvissuto mantiene aperto `stderr` del chiamante. Falso verde: no. Rientra nella regola sulla sfiducia: sì.**

   Evidenza: [quality/limite.sh](quality/limite.sh:26), righe 26–31 e 74–79: vengono arrestati soltanto i PID diretti. Alla riga 60, `limited_out` isola soltanto stdout.

   Con uno shim `id` che avvia `sleep 3600` come figlio e attende, il timeout funziona e **il processo `verify.sh` esce con 1 in circa 3 s**. Il figlio resta però vivo con `stderr` collegato alla pipe del chiamante. La raccolta combinata dell’output non riceve EOF entro 8 s; anche `./verify.sh 2>&1 | cat` resta bloccato dopo aver stampato `VERIFICA FALLITA`. Ho terminato io il figlio o la pipeline. Registrazione della sonda (file locale del Validatore, non conservato).

   È un problema di attesa e chiusura dell’output, senza strumenti che fabbricano dati falsi ben formati.

   **Correzione richiesta:** gestire i discendenti in modo isolato, oppure impedire che conservino i descrittori del chiamante. Aggiungere una regressione con output combinato in pipe che verifichi EOF entro il limite e assenza del figlio residuo.

Ho letto specifica, commenti, entrambi i diff, gli script interi e il validatore Java. Il diff complessivo contiene **otto file, tutti ammessi**; quello dal primo giro ne contiene cinque, anch’essi ammessi. Nessuna modifica a smoke, Compose, business, `analysis/` o `analysis.yml`. Le evidenze CI/Linux riportate dall’Esecutore sono state **solo lette**, non rieseguite.