> Classe di rischio: piena (parità). Wave 2, pilota batch. È il "test" della catena specifica → test → issue → implementazione: si scrive e si mergia **prima** della traduzione di `CBACT01C`, e chi tradurrà non potrà modificarlo.

## Obiettivo

Scrivere il test che dirà se `CBACT01C` tradotto in Java fa ciò che fa l'originale: stessi file di uscita, stessa console dove è riferimento, stesso codice di uscita, a partire dagli stessi conti. Il test entra nel ramo principale marcato "fallimento atteso", perché la traduzione non esiste ancora.

## Dipendenze e perimetro

- Dipende da: #55 (output di riferimento in `oracle/golden/readacct/`: file `*.riferimento.txt`, `ingresso.rec`, tabelle `esclusioni.tsv`, `correzioni.tsv`, `console.tsv`), #60 (caricamento dei conti in PostgreSQL), #59 (tabella `account`), #54 (codifica dei campi).
- Cartelle ammesse: `carddemo-parity/**` (test e loro risorse, comprese le applicazioni di prova per il riconoscimento del job), `quality/**` e `verify.sh` solo per l'elenco dei fallimenti attesi e per rendere obbligatorie le suite nuove, `docs/contratti.md` (sezione "Contratto del job READACCT"), `docs/sviluppo.md`, i `pom.xml` strettamente necessari.
- Fuori ambito: qualsiasi classe di produzione del job (`carddemo-batch/src/main/**`, `carddemo-domain/src/main/**`); modifiche a `oracle/`, `analysis/`, `legacy/`; gli altri programmi.

## Specifica

### 1. Contratto del job, fissato qui

Il test definisce l'interfaccia che la traduzione dovrà offrire; la traduzione non potrà cambiarla.

- **Comando.** Il job si avvia con il jar eseguibile di `carddemo-batch`, in un processo proprio, con questi argomenti e nessun altro: `--spring.batch.job.name=READACCT OUTFILE=<percorso> ARRYFILE=<percorso> VBRCFILE=<percorso>` (i nomi DD di `app/jcl/READACCT.jcl`; i tre argomenti senza `--` sono parametri del job). Il nome Spring Batch del job, cioè ciò che restituisce `Job.getName()`, è `READACCT`; il nome del bean e della classe è libero. La connessione al database arriva dalle proprietà standard di Spring (variabili d'ambiente), come per le altre applicazioni.
- **Nessun job predefinito.** Con più di un job nell'applicazione ogni avvio deve indicare `spring.batch.job.name`. Gli avvii esistenti che oggi non lo indicano (`smoke.sh`, `AccountMigrazioneTest`) andranno adeguati dall'issue di traduzione, nel suo perimetro; questa issue non li tocca e lo dichiara in documentazione.
- **Riesecuzione.** Due avvii consecutivi con lo stesso comando, sullo stesso database e sugli stessi percorsi, riescono entrambi e producono entrambi le uscite complete: il secondo non è rifiutato come "già completato" e sostituisce per intero i file esistenti (equivalente del passo `PREDEL` del JCL seguito dall'esecuzione). Come ottenerlo con Spring Batch (parametri identificanti, identità tecnica di ogni esecuzione) è una scelta della traduzione; il chiamante non aggiunge parametri.
- **Lettura.** I conti si leggono dalla tabella `account` in ordine crescente di `acct_id`, qualunque sia l'ordine in cui sono stati inseriti.
- `OUTFILE`: record fissi di 107 byte, senza terminatori. `ARRYFILE`: record fissi di 110 byte, senza terminatori.
- `VBRCFILE`: flusso di record a lunghezza variabile con il descrittore di record di z/OS (RDW) e senza descrittore di blocco (BDW): ogni record è preceduto da 4 byte, due per la lunghezza del record **compreso il descrittore** (byte più significativo per primo) e due a zero. Per i due record di un conto: `00 10 00 00` + 12 byte e `00 2B 00 00` + 39 byte. `LRECL=84` del JCL è il massimo di 80 byte di dati più il descrittore. **Decisione delegata**: il riferimento di parità è la sequenza dei record logici (#55); per il formato fisico si adotta quello del sistema di origine e non quello di GnuCOBOL, che scrive la lunghezza dei soli dati (`00 0C 00 00`, `00 27 00 00`).
- **Console.** Sullo standard output del processo compaiono solo le righe dei `DISPLAY` dell'originale, una per `DISPLAY`, nell'ordine dell'originale, con gli spazi finali conservati: nessun banner, nessuna riga di log (i log vanno sullo standard error o su file). Sono 2 + 15 × N righe.
- **Codice di uscita** del processo: 0 a fine regolare.

### 2. Come il test avvia e che cosa confronta, per gli scenari `esempio` e `mirato`

**Avvio.** Il test lancia il jar eseguibile di `carddemo-batch` prodotto dalla build corrente in un processo separato (non le classi nel processo dei test: il classpath condiviso ha già prodotto un falso verde, PR #61), con un limite di tempo, e cattura per intero standard output, standard error e codice di uscita. Se nel ciclo Maven di `verify.sh` il jar non è disponibile quando girano i test di `carddemo-parity`, fermarsi con `needs-spec-update`.

**Preparazione**, per ciascuno scenario: database PostgreSQL reale e vuoto (Testcontainers), migrazione applicata, conti caricati con il caricatore di #60 da `oracle/golden/readacct/generati/golden/<scenario>/ingresso.rec`. Prima di avviare il job, cioè prima del punto in cui oggi è ammesso fallire, il test verifica che il contenuto di `account` corrisponda a **quell'**ingresso, ricomponendo i record dalla tabella con un codificatore indipendente (come in #60): caricare per errore l'ingresso dell'altro scenario deve rendere rosso il test già adesso. I percorsi dei tre file di uscita sono nuovi e inizialmente assenti.

**Confronti**, eseguiti dal comparatore:

- `OUTFILE` e `ARRYFILE`: confronto byte per byte con `<file>.riferimento.txt`; non si confrontano i soli byte mascherati (`**`), uno per uno, e mai un campo o un intervallo più largo. Il test non rilegge `esclusioni.tsv` né `correzioni.tsv` per decidere che cosa confrontare: usa il riferimento già prodotto da #55; un controllo a parte verifica che i byte mascherati nei riferimenti siano esattamente quelli di `esclusioni.tsv`.
- `VBRCFILE`: il test verifica i descrittori (lunghezza compresa del descrittore, due byte a zero) con una regola propria e ne estrae i record logici con un proprio lettore; li confronta per numero, ordine, lunghezza e contenuto con `VBRCFILE.riferimento.txt`.
- Console: le righe di classe a di `console.riferimento.txt` devono coincidere, nella stessa posizione, con le righe dello standard output; le righe marcate `#OSSERVAZIONE` non si confrontano nel contenuto, ma devono esserci, una per ciascuna; il totale è 2 + 15 × N.
- Numero di record: N, N e 2N; codice di uscita 0.

**Due verifiche in più sull'orchestrazione**, per lo scenario `mirato`:

- *Riesecuzione*: senza ricaricare i conti, prima del secondo avvio i tre file di uscita vengono sostituiti con file più lunghi dal contenuto sentinella; dopo il secondo avvio tutti i confronti si ripetono e devono riuscire. Un job che non scrive nulla, o che scrive solo l'inizio, non passa.
- *Ordine di lettura*: stesso scenario, con i conti inseriti nella tabella in un ordine fisico diverso (ingresso permutato prima del caricamento, stessi valori): le uscite devono coincidere con gli stessi riferimenti.

Lo scenario `osservazione` di #55 non è usato, e un controllo lo impedisce.

### 3. Fallimento atteso

- **Motivo dichiarato**: avviando il comando del punto 1, l'applicazione non trova un job di nome `READACCT`. Lo si riconosce dalla diagnostica nativa del selettore di Spring Boot per un nome di job inesistente (messaggio e codice di uscita, da fissare leggendoli dall'applicazione attuale) e da nient'altro: non dalla presenza di un bean o di una classe con un certo nome. Qualunque errore diverso (database, caricamento, avvio, limite di tempo) e qualunque errore successivo alla scoperta del job **non** è il motivo dichiarato.
- Il test è marcato con un meccanismo esplicito (un'estensione JUnit del progetto, per esempio `@FallimentoAtteso(issue = …, motivo = …)`) che fa risultare il caso **riuscito** solo se il corpo fallisce per il motivo dichiarato, e **fallito** se fallisce per un altro motivo o se riesce (con il messaggio che chiede di togliere la marcatura).
- **Ricevuta.** Per ogni caso riconosciuto come fallimento atteso l'estensione scrive nel rapporto della corsa una ricevuta (caso, issue, motivo, identificativo della corsa). `verify.sh` pretende, per nome e indipendentemente dall'elenco: i casi di parità `esempio`, `mirato`, riesecuzione e ordine di lettura, eseguiti e con la ricevuta della corsa corrente; i test del comparatore e dell'estensione, eseguiti e riusciti in modo ordinario. Così un caso di parità tolto insieme alla sua marcatura e alla sua riga dell'elenco rende rossa la verifica.
- Un elenco versionato (`quality/fallimenti-attesi.tsv`: classe, metodo, issue che lo toglierà, motivo) è l'unica fonte dei casi marcati: `verify.sh` fallisce se un caso è marcato e non è nell'elenco, o è nell'elenco e non è marcato.
- La traduzione (issue successiva) toglie la marcatura, la riga dell'elenco e la pretesa della ricevuta, e nient'altro dei casi di parità. **Il meccanismo deve reggere in entrambe le fasi**: con l'elenco che contiene i casi di `READACCT` (ora) e con l'elenco vuoto (dopo la traduzione). Per questo le prove sul meccanismo (marcatura tolta, riga tolta, riga in più, motivo diverso) non si fanno sui casi di `READACCT` ma su un caso campione dedicato, che vive nei test del meccanismo e resta dopo la traduzione; e `verify.sh` legge dall'elenco quali casi pretendono la ricevuta, così che togliere una riga, la marcatura e la pretesa insieme, per un caso che ora riesce, lasci la verifica verde, mentre toglierle per un caso che ancora fallisce la renda rossa. La transizione è descritta in `docs/sviluppo.md` come una procedura di tre righe.

### 4. Come si prova un test che non può ancora passare

Il comparatore è separato dall'avvio e ha i propri test, non marcati, che devono passare ora:

- **Uscite fedeli simulate**: file costruiti nel test a partire dai file fisici dell'oracle versionati da #55, con le correzioni applicate, il descrittore dei record variabili convertito nella forma del punto 1 e la console dell'oracle: il comparatore le accetta, per entrambi gli scenari. La conversione del descrittore è verificata per conto suo sui primi byte attesi scritti a mano (`00 10 00 00`, `00 2B 00 00`): simulatore e lettore non devono poter condividere lo stesso errore.
- **Prove negative sul comparatore**, una alterazione alla volta, ciascuna respinta con la diagnosi che nomina file, record e posizione: un byte alterato in una posizione determinata di `OUTFILE`; i byte 76 e 79 di `OUTFILE` (i confini della maschera) e un byte dentro la data, tra 69 e 76; un byte di `ARRYFILE`; il byte 80 e, separatamente, il byte 99 di `ARRYFILE` riportati a `30` (l'errore dell'oracle: un Java che lo copiasse deve essere respinto); un record in meno; un record in più; due record scambiati; un record logico di `VBRCFILE` con lunghezza sbagliata; il descrittore con i byte in ordine inverso; il `VBRCFILE` nel formato fisico di GnuCOBOL (lunghezza dei soli dati); una riga di console di classe a alterata, e con uno spazio finale in meno; una riga di console in meno; una riga di log in più sullo standard output; codice di uscita diverso da 0; file di uscita assente.
- **Controprove**: un byte alterato in una posizione mascherata è accettato; una riga di console marcata osservazione con contenuto diverso è accettata. Entrambe dichiarate in documentazione come ciò che il test **non** garantisce.
- **Prove sull'avvio e sul riconoscimento del job**, con applicazioni di prova costruite nei test (non nel codice di produzione): nessun job `READACCT` → motivo dichiarato riconosciuto; un job di prova il cui nome Spring Batch è `READACCT` e il cui bean ha un altro nome, e che non scrive nulla → il rilevatore dice che il job esiste e il caso fallisce sui confronti, non per assenza; lo stesso job di prova che lascia intatti file sentinella → respinto dalla verifica di riesecuzione; errore del database del solo avvio sotto prova → fallimento non atteso.
- Il meccanismo del fallimento atteso ha i propri test: corpo che fallisce per il motivo dichiarato → riuscito con ricevuta; per un altro motivo → fallito; corpo che riesce → fallito.

## Invarianti di parità

- Il riferimento è quello di #55 e solo quello: il test non contiene valori attesi propri sul contenuto delle uscite. Sono ammessi attesi strutturali propri del contratto di questa issue (i descrittori dei record variabili, il numero di righe).
- Stesso ordine di chiave, stesso numero di record, stessi byte nelle posizioni determinate.

## Criteri di accettazione

1. `./verify.sh` esce con 0: i test del comparatore e del meccanismo passano; il test di parità risulta eseguito e "fallito come atteso" per il motivo dichiarato; le suite nuove sono obbligatorie per nome.
2. Prove sul meccanismo dentro `verify.sh` vero, ciascuna con il caso che deve fallire e la diagnosi attesa (un errore di compilazione, un guasto di Docker o un limite di tempo non valgono come esito): marcatura tolta da un caso di parità; riga tolta dall'elenco; riga in più nell'elenco; metodo di parità, marcatura e riga tolti insieme lasciando gli altri test; ingresso dello scenario `mirato` sostituito con quello di `esempio`; database del solo avvio sotto prova irraggiungibile, con il resto dell'infrastruttura dei test funzionante.
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
