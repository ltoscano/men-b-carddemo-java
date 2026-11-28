> Classe di rischio: piena (parità). Wave 2, pilota batch. È il "test" della catena specifica → test → issue → implementazione: si scrive e si mergia **prima** della traduzione di `CBACT01C`, e chi tradurrà non potrà modificarlo.

## Obiettivo

Scrivere il test che dirà se `CBACT01C` tradotto in Java fa ciò che fa l'originale: stessi file di uscita, stessa console dove è riferimento, stesso codice di uscita, a partire dagli stessi conti. Il test entra nel ramo principale marcato "fallimento atteso", perché la traduzione non esiste ancora.

## Dipendenze e perimetro

- Dipende da: #55 (output di riferimento in `oracle/golden/readacct/`: file `*.riferimento.txt`, `ingresso.rec`, tabelle `esclusioni.tsv`, `correzioni.tsv`, `console.tsv`), #60 (caricamento dei conti in PostgreSQL), #59 (tabella `account`), #54 (codifica dei campi).
- Cartelle ammesse: `carddemo-parity/**` (test e loro risorse), `quality/**` e `verify.sh` solo per l'elenco dei fallimenti attesi e per rendere obbligatorie le suite nuove, `docs/contratti.md` (sezione "Contratto del job READACCT"), `docs/sviluppo.md`, i `pom.xml` strettamente necessari.
- Fuori ambito: qualsiasi classe di produzione del job (`carddemo-batch/src/main/**`, `carddemo-domain/src/main/**`); modifiche a `oracle/`, `analysis/`, `legacy/`; gli altri programmi.

## Specifica

### 1. Contratto del job, fissato qui

Il test definisce l'interfaccia che la traduzione dovrà offrire; la traduzione non potrà cambiarla.

- Nome del job Spring Batch: `READACCT`. Si avvia con l'applicazione `carddemo-batch` e i parametri `job=READACCT`, `OUTFILE=<percorso>`, `ARRYFILE=<percorso>`, `VBRCFILE=<percorso>` (i nomi DD di `app/jcl/READACCT.jcl`). Legge i conti dalla tabella `account` in ordine di chiave.
- `OUTFILE`: record fissi di 107 byte, senza terminatori. `ARRYFILE`: record fissi di 110 byte, senza terminatori.
- `VBRCFILE`: sequenza di record a lunghezza variabile; ogni record è preceduto da un descrittore di 4 byte nella forma dei record `VB` di z/OS (due byte, lunghezza del record compreso il descrittore, ordine dei byte più significativo per primo; due byte a zero). **Decisione delegata**: il riferimento di parità è la sequenza dei record logici (#55); per il formato fisico si adotta quello del sistema di origine e non quello di GnuCOBOL, che è un dettaglio del compilatore.
- Console: una riga per ogni `DISPLAY` dell'originale, sullo standard output del job, nell'ordine dell'originale, senza altre righe del job mescolate (i log dell'applicazione vanno altrove o sono distinguibili: definire come il test isola le righe del job).
- Codice di uscita 0 a fine regolare.
- I file di uscita si creano nuovi; se esistono già, il job li sostituisce (osservazione di #55 sulla riesecuzione).

### 2. Che cosa confronta il test, per gli scenari `esempio` e `mirato`

Per ciascuno scenario: database PostgreSQL reale e vuoto (Testcontainers), migrazione applicata, conti caricati con il caricatore di #60 da `oracle/golden/readacct/generati/golden/<scenario>/ingresso.rec`, job avviato con il contratto del punto 1, poi:

- `OUTFILE` e `ARRYFILE`: confronto byte per byte con `<file>.riferimento.txt`; le posizioni mascherate (`**`) non si confrontano; ogni altra posizione sì. Il test non rilegge `esclusioni.tsv` né `correzioni.tsv` per decidere che cosa confrontare: usa il riferimento già prodotto da #55, e un controllo a parte verifica che le posizioni mascherate nei riferimenti siano esattamente quelle di `esclusioni.tsv`.
- `VBRCFILE`: il test estrae i record logici dal file del job con un proprio lettore del formato del punto 1 e li confronta, per numero, ordine, lunghezza e contenuto, con `VBRCFILE.riferimento.txt`.
- Console: le righe di classe a di `console.riferimento.txt` (#55) devono coincidere, nell'ordine, con le righe corrispondenti del job; le righe marcate `#OSSERVAZIONE` non si confrontano nel contenuto, ma il numero totale di righe e la loro posizione sì (2 + 15 × N).
- Numero di record: N, N e 2N; codice di uscita 0.
- Lo scenario `osservazione` di #55 non è usato, e un controllo lo impedisce.

### 3. Fallimento atteso

- Finché il job `READACCT` non esiste, il test fallisce. Lo si marca con un meccanismo esplicito (un'estensione JUnit del progetto, per esempio `@FallimentoAtteso(issue = …, motivo = …)`) che: fa risultare il test **riuscito** solo se il corpo fallisce **per il motivo dichiarato** (il job `READACCT` non è definito), e **fallito** se il corpo fallisce per un altro motivo o se riesce.
- Un elenco versionato (`quality/fallimenti-attesi.tsv`: classe, metodo, issue che lo toglierà, motivo) è l'unica fonte dei test marcati. `verify.sh` fallisce se un test è marcato e non è nell'elenco, se è nell'elenco e non è marcato, o se l'elenco contiene un test che non è stato eseguito.
- La traduzione (issue successiva) toglie la marcatura e la riga dell'elenco, e nient'altro del test.

### 4. Come si prova un test che non può ancora passare

Il comparatore (la parte del test che confronta uscite e riferimenti) è separato dall'avvio del job e ha i propri test, che non sono marcati e devono passare ora:

- **Uscite fedeli simulate**: file costruiti nel test a partire dai file fisici dell'oracle versionati da #55 (con le correzioni applicate, il descrittore dei record variabili nella forma del punto 1 e la console dell'oracle): il comparatore le accetta, per entrambi gli scenari.
- **Prove negative sul comparatore**, una alterazione alla volta, ciascuna respinta con la diagnosi che nomina file, record e posizione: un byte alterato in una posizione determinata di `OUTFILE`; di `ARRYFILE`; il byte 80 di `ARRYFILE` riportato a `30` (l'errore dell'oracle: un Java che lo copiasse deve essere respinto); un record in meno; un record in più; due record scambiati; un record logico di `VBRCFILE` con lunghezza sbagliata; il descrittore con i byte in ordine inverso; una riga di console di classe a alterata; una riga di console in meno; codice di uscita diverso da 0; file di uscita assente; file di uscita di una corsa precedente con il job che non scrive nulla.
- **Controprove**: un byte alterato in una posizione mascherata è accettato; una riga di console marcata osservazione con contenuto diverso è accettata. Entrambe dichiarate in documentazione come ciò che il test **non** garantisce.
- Il meccanismo del fallimento atteso ha i propri test: corpo che fallisce per il motivo dichiarato → riuscito; per un altro motivo → fallito; corpo che riesce → fallito, con il messaggio che chiede di togliere la marcatura.

## Invarianti di parità

- Il riferimento è quello di #55 e solo quello: il test non contiene valori attesi propri sulle uscite.
- Stesso ordine di chiave, stesso numero di record, stessi byte nelle posizioni determinate.

## Criteri di accettazione

1. `./verify.sh` esce con 0: i test del comparatore e del meccanismo passano; il test di parità risulta eseguito e "fallito come atteso" per il motivo dichiarato; le suite nuove sono obbligatorie per nome.
2. Prove sul meccanismo dentro `verify.sh` vero: marcatura tolta dal test (il test fallisce, `verify.sh` rosso); riga tolta dall'elenco; riga in più nell'elenco; motivo del fallimento cambiato (per esempio database non raggiungibile): `verify.sh` rosso in tutti i casi.
3. `./smoke.sh`, `./quality/regressioni-verify.sh`, `./quality/regressioni-regole.sh` escono con 0; di `regressioni-copertura.sh` i casi toccati.
4. Ogni prova negativa è riportata con nome e diagnosi.
5. `git status --short` vuoto; diff nel solo perimetro; nessuna classe di produzione aggiunta.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR: nessun codice di produzione ne dipende.

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git. Mai un database in memoria.
- Non scrivere il job, nemmeno in forma di bozza o dentro i test: le "uscite fedeli simulate" si costruiscono dai file dell'oracle, non eseguendo logica tradotta.
- Se i riferimenti di #55 o il caricatore di #60 smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w2a-`.
