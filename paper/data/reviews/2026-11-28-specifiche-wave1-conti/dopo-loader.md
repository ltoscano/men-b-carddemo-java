> Classe di rischio: piena (dati). Wave 1, ristretta al file dei conti (registro delle approvazioni, voce 86).

## Obiettivo

Caricare nella tabella `account` gli stessi conti che l'oracle legge, a partire dallo stesso file di record, e dimostrare che ciò che sta in PostgreSQL corrisponde record per record a quel file.

## Dipendenze e perimetro

- Dipende da: #59 (tabella `account`, che fissa: valori e non byte, solo ingressi canonici); #53 (file `analysis/oracle-dati/out/ACCTFILE.rec`: 50 record di 300 byte nel profilo dell'oracle); #54 (codifica dei campi in Java, mergiata).
- Cartelle ammesse: `carddemo-loader/**`, `carddemo-parity/**` (test), `compose.yaml` e `docker/**` per il servizio di caricamento, `smoke.sh` per le fasi di build, avvio, verifica e pulizia che il nuovo servizio richiede, `verify.sh` e `quality/RapportoSurefire.java` solo per rendere obbligatorie le suite nuove, `docs/contratti.md`, `docs/sviluppo.md`, i `pom.xml` strettamente necessari.
- Fuori ambito: gli altri file; la lettura dei conti da parte di programmi tradotti; qualsiasi modifica ad `analysis/`, `oracle/`, `legacy/`.

## Specifica

- **Ingresso**: un file di record a lunghezza fissa di 300 byte nel profilo dell'oracle, indicato come parametro. Il caricatore non è legato al file di esempio: lo stesso comando caricherà i file degli scenari costruiti per la parità (#55).
- **Decodifica**: ogni campo con `GnuCobolFieldCodec` (#54) e il tracciato del contratto `CVACT01Y.ACCOUNT-RECORD`, riportato in una tabella Java (campo, posizione, lunghezza, categoria, `PICTURE`) che un test in `carddemo-parity` confronta riga per riga con `docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv` letto dal repository. Il contratto non si legge durante la build delle immagini (`docs/` è escluso dal contesto di build). Nessuna regola di codifica riscritta.
- **Che cosa ferma il caricamento** (nessuna riga scritta, transazione annullata, codice di uscita diverso da 0, diagnosi con numero di record, campo e byte): dimensione non multipla di 300; campo numerico non valido; **campo numerico in rappresentazione non canonica** (i byte del campo sono diversi da `encode(decode(byte))`: zero con segno negativo, segno alternativo); **`FILLER` diverso da 178 spazi**; chiave duplicata; carattere non rappresentabile in una colonna di testo (il byte nullo). È la regola fissata dall'issue della tabella: il sistema Java accetta solo ingressi canonici, così ogni riga corrisponde a un solo record di byte. Nulla viene normalizzato in silenzio e non esiste un elenco di "perdite accettate".
- **Riesecuzione**: il caricamento su una tabella non vuota si ferma con errore; non cancella e non aggiorna. (Sul mainframe `ACCTFILE.jcl` cancella e ricrea il file: l'equivalente è ricreare il database, e va documentato.)
- **Ordine**: tutto in una sola transazione, nell'ordine del file.
- **Servizio**, con un solo percorso: il caricatore è un'applicazione del modulo `carddemo-loader` che all'avvio applica la migrazione con Flyway (la stessa risorsa di `carddemo-domain`), carica il file e termina con il codice dell'esito. In `compose.yaml` è un servizio senza profilo, che dipende dal database sano; i servizi applicativi dipendono dal caricatore con `condition: service_completed_successfully`, così `up --wait` attende il caricamento e un caricamento fallito ferma l'avvio. `ACCTFILE.rec` entra nell'immagine finale del caricatore con un `COPY` esplicito in `docker/` (la cartella `analysis/` è nel contesto di build). `smoke.sh` costruisce anche questa immagine, verifica 50 righe, prima e ultima chiave e codice di uscita 0 del caricatore, e nella pulizia rimuove anche il suo container terminato. Un secondo `up` sullo stesso volume trova la tabella piena: va deciso e documentato l'esito (il caricatore si ferma con errore e l'avvio fallisce: per ricaricare si ricrea il volume), e lo smoke lo prova.

### Controlli, ciascuno con prova negativa (test contro PostgreSQL reale)

1. Numero di righe uguale al numero di record; insieme delle chiavi uguale.
2. **Ritorno al formato fisso**: da ogni riga, riletta con `ORDER BY acct_id`, un codificatore indipendente dal caricatore (nel test) ricompone il record di 300 byte con `encode` e 178 spazi di `FILLER`; il risultato è uguale byte per byte al record d'ingresso, per tutti i record, senza eccezioni.
3. Totali di controllo: somma di ciascuna colonna numerica uguale alla somma calcolata dai byte del file con una lettura indipendente (nel test, senza passare dal caricatore).
4. Ordine: la sequenza delle chiavi lette con `ORDER BY acct_id` è la sequenza del file (che #53 garantisce crescente).
5. Casi costruiti nel test (file temporanei). Rifiutati, ciascuno con la sua diagnosi e zero righe scritte: zero negativo; segno alternativo; `FILLER` non vuoto; campo numerico con spazi; chiave duplicata; file troncato; byte nullo in un campo di testo. Accettati: importo massimo e minimo della `PICTURE`; file vuoto (0 record, 0 righe, dichiarato); un insieme di record **distinguibili campo per campo** (le tre date tutte diverse tra loro, credito e addebito di ciclo entrambi non nulli e diversi, limite di credito diverso dal limite di anticipo, gruppo non vuoto, stato diverso da `Y`, importi negativi); record con caratteri oltre ASCII (byte `0x80`-`0xFF`) nei campi di testo, verificando la stringa letta via JDBC e la ricodifica byte per byte. La codifica effettiva del database si legge e si dichiara (attesa: UTF-8).
6. **Le suite nuove sono obbligatorie** in `verify.sh`, per nome, eseguite e non saltate; prove negative: suite assente, suite saltata.

Prove negative: coppie di campi di uguale tracciato scambiate nel caricatore, una coppia alla volta (i due limiti; scadenza e riemissione; credito e addebito di ciclo; CAP e gruppo); stato o gruppo scritti come costante; un carattere oltre ASCII alterato; il controllo di canonicità disattivato (lo zero negativo entra); scala sbagliata; segno ignorato; un record saltato; l'ultimo record caricato due volte con chiave alterata; transazione confermata prima dell'errore (deve restare zero righe); caricamento su tabella non vuota che riesce; caricatore che fallisce mentre l'avvio di Compose riesce.

## Invarianti di parità

- Stessi conti, stessi valori, stesso ordine di chiave del file che legge l'oracle.
- Nessun valore riparato in silenzio: ciò che la tabella non può conservare non entra.
- Importi solo `BigDecimal`.

## Criteri di accettazione

1. `./verify.sh` esce con 0; i test nuovi risultano eseguiti nel rapporto.
2. `./smoke.sh` esce con 0, con il controllo sul caricamento; un caricamento fallito lo rende rosso.
3. Le suite di regressione esistenti toccate dal diff escono con 0.
4. Ogni prova negativa è riportata con nome e diagnosi.
5. `git status --short` vuoto; diff nel solo perimetro.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR per il codice. Il revert Git non annulla un caricamento già confermato su un database esistente: il database di sviluppo si ricrea (comando in `docs/sviluppo.md`).

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git. Mai un database in memoria.
- Una sola issue: solo il file dei conti.
- Se il contratto, i dati o il codec smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w1b-`.
