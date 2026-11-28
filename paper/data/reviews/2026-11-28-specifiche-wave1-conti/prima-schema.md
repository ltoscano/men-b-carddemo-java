> Classe di rischio: piena (schema, dati). Wave 1, ristretta alla sola tabella che serve al pilota batch (registro delle approvazioni, voce 86).

## Obiettivo

Dare al sistema Java la tabella dei conti in PostgreSQL, creata da una migrazione versionata, con colonne e chiave derivate dal contratto dati del record `ACCOUNT-RECORD`, e dimostrare con test contro PostgreSQL reale che ha la forma dichiarata.

## Dipendenze e perimetro

- Dipende da: #3 (contratto dati, mergiata), #15 e #26 (test con PostgreSQL reale e regole sul codice, mergiate).
- Sorgenti di riferimento: `app/cpy/CVACT01Y.cpy`, `docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv`, `app/jcl/ACCTFILE.jcl` (`KEYS(11 0)`).
- Cartelle ammesse: `carddemo-domain/**` (migrazione e, se serve, il tipo che descrive la tabella), `carddemo-parity/**` (test), i `pom.xml` strettamente necessari per aggiungere lo strumento di migrazione a versione fissata, `docs/contratti.md` (nuova sezione "Tabella dei conti"), `docs/sviluppo.md`, e i file di `quality/` solo se un controllo esistente va adeguato a un numero che cambia (dichiarandolo).
- Fuori ambito: caricamento dei dati (issue successiva), le altre dieci tabelle, entità o repository usati da programmi tradotti, qualsiasi indice o vincolo non ricavato dal contratto.

## Specifica

### Decisioni (delegate, da registrare)

1. **Strumento di migrazione: Flyway**, a versione fissata, eseguito all'avvio delle applicazioni e nei test. Motivo: è lo strumento previsto da Spring Boot, le migrazioni sono file SQL leggibili. Alternativa scartata: `ddl-auto` di Hibernate (lo schema non sarebbe versionato né derivato dal contratto).
2. **La tabella conserva valori, non byte.** Gli importi sono `NUMERIC(12,2)`, la chiave `NUMERIC(11,0)`. Conseguenza dichiarata: una rappresentazione non canonica dello stesso valore (per esempio lo zero con segno negativo) non è conservata; che cosa ne segue per la parità lo decide l'issue del caricamento.
3. **Le date restano testo.** I tre campi data sono `PIC X(10)` e il legacy non li valida al caricamento: colonne di testo di 10 caratteri, non `DATE`. Convertirle sarebbe una miglioria che cambia il comportamento sui valori non validi.
4. **Il `FILLER` non ha una colonna.**

### Tabella `account`

Una colonna per ogni campo elementare del contratto diverso dal `FILLER`, nell'ordine del copybook:

| Campo COBOL | `PICTURE` | Colonna | Tipo |
| --- | --- | --- | --- |
| `ACCT-ID` | `9(11)` | `acct_id` | `NUMERIC(11,0)`, chiave primaria, vincolo `>= 0` |
| `ACCT-ACTIVE-STATUS` | `X(01)` | `acct_active_status` | `CHAR(1)` |
| `ACCT-CURR-BAL` | `S9(10)V99` | `acct_curr_bal` | `NUMERIC(12,2)` |
| `ACCT-CREDIT-LIMIT` | `S9(10)V99` | `acct_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-CASH-CREDIT-LIMIT` | `S9(10)V99` | `acct_cash_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-OPEN-DATE` | `X(10)` | `acct_open_date` | `CHAR(10)` |
| `ACCT-EXPIRAION-DATE` | `X(10)` | `acct_expiraion_date` | `CHAR(10)` (il refuso del copybook si conserva nel nome) |
| `ACCT-REISSUE-DATE` | `X(10)` | `acct_reissue_date` | `CHAR(10)` |
| `ACCT-CURR-CYC-CREDIT` | `S9(10)V99` | `acct_curr_cyc_credit` | `NUMERIC(12,2)` |
| `ACCT-CURR-CYC-DEBIT` | `S9(10)V99` | `acct_curr_cyc_debit` | `NUMERIC(12,2)` |
| `ACCT-ADDR-ZIP` | `X(10)` | `acct_addr_zip` | `CHAR(10)` |
| `ACCT-GROUP-ID` | `X(10)` | `acct_group_id` | `CHAR(10)` |

Tutte le colonne `NOT NULL`: un record COBOL non ha campi assenti. Nessun altro vincolo, indice o valore predefinito. Se la contestazione o l'implementazione mostrano che `CHAR(n)` altera gli spazi finali in lettura o nei confronti in un modo che cambia un risultato osservabile, fermarsi con `needs-spec-update`.

### Controlli, ciascuno con prova negativa

1. La migrazione gira su un PostgreSQL vuoto (Testcontainers, stessa immagine fissata del progetto) e produce esattamente la tabella della specifica: nomi, ordine, tipi, precisione e scala, `NOT NULL`, chiave primaria, letti da `information_schema` e confrontati con una tabella attesa scritta a mano nel test.
2. Corrispondenza con il contratto: per ogni riga elementare non `FILLER` di `CVACT01Y.ACCOUNT-RECORD.tsv` (letto dal repository, non copiato) esiste una colonna, con tipo coerente con `PICTURE` secondo una regola scritta (`X(n)` → `CHAR(n)`; `9(n)` → `NUMERIC(n,0)`; `S9(i)V9(d)` → `NUMERIC(i+d,d)`); nessuna colonna in più.
3. Limiti: il massimo e il minimo valore della `PICTURE` di ogni colonna numerica si inseriscono e si rileggono identici (`BigDecimal`, stessa scala); un valore con una cifra in più è rifiutato dal database; una chiave duplicata è rifiutata; un testo di lunghezza maggiore è rifiutato.
4. Ordinamento: righe inserite in ordine sparso si rileggono con `ORDER BY acct_id` in ordine numerico crescente (caso di prova: 9, 10, 100, 99999999999).
5. La migrazione applicata due volte non cambia nulla e non fallisce; una migrazione già applicata e poi modificata fa fallire l'avvio (controllo di Flyway attivo).

Prove negative: una colonna con scala sbagliata; due colonne scambiate di posto; una colonna resa annullabile; la chiave primaria tolta; una colonna in più; una riga tolta dalla tabella attesa del test insieme alla colonna (deve accorgersene il controllo 2, che legge il contratto).

## Invarianti di parità

- Chiave e ordine di chiave del file indicizzato; precisione e scala degli importi; nessun valore predefinito che riempia un campo mancante.

## Criteri di accettazione

1. `./verify.sh` esce con 0 e i test nuovi risultano eseguiti (non saltati) nel rapporto.
2. `./smoke.sh` esce con 0: le applicazioni partono con la migrazione applicata.
3. `./quality/regressioni-regole.sh` e `./quality/regressioni-verify.sh` escono con 0; di `./quality/regressioni-copertura.sh` i casi toccati dal diff.
4. Ogni prova negativa è riportata con nome e diagnosi.
5. `git status --short` vuoto; diff nel solo perimetro; versione di Flyway fissata; nessun profilo Maven.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR: nessun dato esiste ancora nella tabella.

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git. Mai un database in memoria.
- Una sola issue: niente caricamento, niente altre tabelle, niente entità per programmi futuri.
- Se il contratto o PostgreSQL smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w1a-`.
