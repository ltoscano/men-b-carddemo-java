APPROVATA

Controprove Java eseguite nel container con `mvn -B -pl carddemo-batch -am package -Dsurefire.failIfNoSpecifiedTests=false`, selezionando i test indicati. Mutazioni isolate e poi ripristinate.

| Rilievo | Stato | Comando / prova | Esito |
|---|---|---|---|
| 1 — Fine della console | **Chiuso** | `/bin/bash`, funzioni estratte da `smoke.sh`, console reale e Docker reale | Console corretta accettata; respinti coda senza LF, coda con LF, ultima riga senza LF e NUL in una riga non confrontata. Bash 3.2 dell’host; ogni confronto entro 0,14 s. |
| 2 — Addebito non nullo | **Chiuso** | `-Dtest=Cbact01cTest`, con `1525.00` al posto di `1005.00` per addebito negativo | Tre test rossi: ARRYFILE, record 3, 1 e 2, posizione 28, `00 → 52`. Ricostruiti indipendentemente un record per file: **107, 110 e 59 byte**, nessuna differenza dagli attesi. Nessun calcolo circolare con il codice di produzione. |
| 3 — Codice di uscita | **Chiuso** | `-Dtest=ReadacctProcessoTest`, con `EsitoReadacct` limitato ad apertura e lettura | **11 fallimenti**, tutti `99 atteso / 5 ottenuto`. Senza mutazione passano i 16 casi, comprese tutte le 14 iniezioni della tabella degli errori. |
| 4 — Momento di PREDEL | **Chiuso** | I due test PREDEL di `Cbact01cTest`, selezionati singolarmente | Entrambe le mutazioni — dopo l’apertura e dopo il primo DISPLAY — fanno fallire entrambi i test: sentinelle presenti quando devono essere già assenti. |
| 5 — Tabella di corrispondenza | **Chiuso** | `python3` per l’incrocio delle righe, più ispezione puntuale | **21 righe campionate** con numero e istruzione corretti; **175 istruzioni** nelle righe 141–426 coperte, nessuna osservabile senza riga. Tutti i paragrafi presenti. |

Il main dei test carica `BatchApplication`, usa la configurazione originale del job e lo stesso calcolo tramite `SpringApplication.exit`; sostituisce i collaboratori necessari all’iniezione dei guasti. Le classi di prova sono assenti dai jar di produzione e dal jar contenuto nell’immagine.

Le due modifiche aggiuntive di produzione sono corrette e motivate. Rimuovendo il generatore esplicito ricompare l’uscita **0 anziché 5**; rimuovendo la pulizia sull’`Error` manca START dalla console. Restano verificati console, file e codici **0/99** dei percorsi previsti. Nell’immagine reale, `installationCheckJob` termina con **0**; avvio senza nome e nome inesistente con **1**, stdout vuoto.

| Comando di accettazione | Esito |
|---|---|
| `./verify.sh` | **0**; quattro casi READACCT riusciti ordinariamente, zero saltati e zero ricevute di fallimento atteso |
| `./smoke.sh` | **0**; file di 5350, 5500 e 2950 byte; console corretta di 752 righe |
| `./quality/regressioni-verify.sh` | **0**; nove guasti riconosciuti |
| `./quality/regressioni-regole.sh` | **0**; 44 casi riconosciuti |
| `./quality/regressioni-copertura.sh rapporto-senza-classe agente-spento-batch difetto-batch spotbugs-assente spotbugs-troncato spotbugs-altra-corsa spotbugs-senza-classe cancello-spotbugs-skip-batch` | **0**; base completa e otto casi riconosciuti |

Diff di correzione letto integralmente, identico al diff Git e nel perimetro. [CI sullo SHA finale `bbd58cd`](https://github.com/ltoscano/men-b-carddemo-java/commit/bbd58cde0a08f07479b8ad88e441b0cd68363695/checks): **8/8 check riusciti**.

**Nuovi rilievi: nessuno.**

Cartella consegnata invariata, nessun commit. Copie temporanee, container, reti, volumi e tag immagine `menb-val70b-` rimossi; nessuna rimozione di risorse condivise e nessun `prune`.