BOCCIATA

Validato lo SHA `bbdc66bd8139611b417d511ca21fdfa9899138b7`. I cinque rilievi precedenti sono chiusi secondo la specifica aggiornata; emerge una nuova lacuna nel contratto dei confronti.

| Rilievo del primo giro | Stato | Comando/prova rieseguita | Esito |
|---|---|---|---|
| 1. Perdita degli spazi nelle conversioni | **Chiuso** | Inserimento parametrizzato; `=`, `lower(colonna)=lower(?)`, `colonna::text=?`, `colonna=?::text`, via JDBC e `psql` | Con parametro pieno: **1 riga**; senza spazi finali: **0**. Spazi conservati. |
| 2. Batch incapace di migrare autonomamente | **Chiuso** | `./smoke.sh` con `skip-executing-migrations=true` in batch | **1**, passo `batch-primo`: `<assente>\|r\|0`. |
| 3. Vista accettata come tabella | **Chiuso** | `./smoke.sh` con `CREATE VIEW account AS SELECT 1 AS acct_id` | **1**, passo `migrazione`: `v\|r\|1`. |
| 4. Classpath condiviso dei test di avvio | **Chiuso secondo la nuova specifica** | `./smoke.sh`, starter tolto separatamente da online e batch | Online: **1** in `migrazione`, oggetti assenti. Batch: **1** in `batch-1`, messaggio Flyway assente. Il limite di `AccountMigrazioneTest` è documentato. |
| 5. Affermazione falsa sul testo lungo con spazi | **Chiuso** | Inserimenti parametrizzati di `G1` seguito da 11 spazi e di 13 spazi; rilettura dei valori validi | Entrambi rifiutati con **23514**; valori di dieci caratteri riletti identici. |

Le [prove JDBC](/tmp/menb-val61b-audit/logs/jdbc.log), le [operazioni sulle sei colonne](/tmp/menb-val61b-audit/logs/operazioni-jdbc.log), le [prove psql](/tmp/menb-val61b-audit/logs/psql.log) e gli [smoke negativi](/tmp/menb-val61b-audit/logs/mut-smoke.jsonl) conservano gli esiti.

1. **Importante — La regola della “lunghezza piena” non completa la semantica dei confronti COBOL.**

   **Evidenza:** PostgreSQL della stessa immagine, JDBC 42.7.14 e `psql` con parametri producono:

   | Operazione su dati validi ASCII | PostgreSQL | GnuCOBOL dell’immagine oracle |
   |---|---:|---:|
   | `trim(acct_group_id) = ?`, valore e parametro `G1` seguito da otto spazi | falso | `FUNCTION TRIM(a) = a`: vero |
   | Campo `X(10)` contenente `A` seguito da nove spazi confrontato con campo `X(1)` contenente `A`: uguaglianza | falso | vero |
   | Stessi campi: maggiore | vero | falso |

   Nel secondo caso entrambi i campi hanno già la propria lunghezza piena. Il COBOL estende l’operando più corto durante il confronto; `TEXT` non lo fa. Le prove sono nei [risultati JDBC](/tmp/menb-val61b-audit/logs/jdbc.log) e nel [confronto GnuCOBOL](/tmp/menb-val61b-audit/logs/cobol.log).

   **Correzione richiesta:** completare la decisione del contratto tramite `needs-spec-update`, definendo la normalizzazione degli operandi anche dopo funzioni e tra campi di lunghezze diverse; aggiornare documentazione e test con questi controesempi.

   **Falso verde:** sì, sulla parità comportamentale dichiarata. Il catalogo attuale rispetta invece il DDL prescritto. **Modifica versionata richiesta:** sì, contratto/documentazione e test.

Le mutazioni sono state applicate singolarmente attraverso:

```sh
mvn -B -pl carddemo-parity -am test \
  -Dtest=AccountSchemaTest,AccountContrattoTest \
  -Dsurefire.failIfNoSpecifiedTests=false \
  -Dmenb.verify.run=<corsa>
```

| Mutazione | Esito e diagnosi |
|---|---|
| Lunghezza con `<=` oppure `>=` | **1**: contratto, definizione del vincolo e casi di lunghezza |
| Vincolo sulla colonna sbagliata, stesso numero | **1**: lunghezza contrattuale mancante sulla colonna corretta |
| `octet_length` | **1**: controllo indipendente del contratto |
| `COLLATE "C"` tolto da una sola colonna | **1**: collazione diversa nel catalogo |
| `TEXT` → `VARCHAR(10)` | **1**: tipo errato; i casi con soli spazi eccedenti risultano accettati |
| `TEXT` → `CHAR(10)` | **1**: tipo errato e valori riempiti rifiutati dal vincolo |
| `length`, uguaglianza invertita, collazione `POSIX` | **1** anche se equivalenti: i controlli pretendono forma e nome prescritti |
| Colonna, attese e conteggi tolti insieme | Schema **14/14** e migrazione **4/4** verdi; contratto **rosso**, `acct_group_id` mancante |

La lettura del vincolo non ha prodotto falsi verdi nelle mutazioni richieste. [Esiti completi](/tmp/menb-val61b-audit/logs/mutazioni.jsonl).

Ho confermato inoltre:

- `char_length` conta caratteri, **non byte**: dieci `é` occupano 20 byte, dieci emoji 40; entrambi sono accettati con lunghezza 10. È un limite distinto, già rinviato al caricamento dalla documentazione.
- Concatenazione, `LIKE`, ordinamento e conservazione degli spazi danno gli esiti documentati. Gli arrotondamenti sono confermati: `0.005 → 0.01`, `-0.005 → -0.01`, `1.234 → 1.23`.
- Nessuna attesa senza limite nelle righe aggiunte allo smoke; il secondo database resta nel volume del servizio, rimosso dalla pulizia.
- Il diff di correzione coincide con quello tra i due SHA e modifica **otto file, tutti ammessi**.

| Criterio eseguito una volta | Esito |
|---|---|
| `./verify.sh` | **0**, 425 test, nessun errore o salto |
| `./smoke.sh` | **0**, incluso `batch-primo` |
| `./quality/regressioni-verify.sh` | **0** |
| `./quality/regressioni-regole.sh` | **0** |
| `./quality/regressioni-copertura.sh controprova-lecita` | **0**, base e controprova |

I conteggi coincidono con la [CI sullo stesso SHA](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46108474940): domain **399**, loader/online/batch **1 ciascuno**, parity **23**. Il criterio “tutti i check verdi” resta però insoddisfatto: un [job oracle](https://github.com/ltoscano/men-b-carddemo-java/actions/runs/46108475038/job/140866455453) fallisce sul controllo temporale MVSWAIT, **610 ms contro 500 ms**, fuori dal diff.

Nessuna modifica versionata o commit. Resta soltanto `.validazione/` preesistente non tracciata. Risorse Docker proprie rimosse; immagini e volumi condivisi conservati.