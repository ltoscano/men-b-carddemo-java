> Classe di rischio: piena (schema, dati). Wave 1, ristretta alla sola tabella che serve al pilota batch (registro delle approvazioni, voce 86).

## Obiettivo

Dare al sistema Java la tabella dei conti in PostgreSQL, creata da una migrazione versionata, con colonne e chiave derivate dal contratto dati del record `ACCOUNT-RECORD`, e dimostrare con test contro PostgreSQL reale che ha la forma dichiarata.

## Dipendenze e perimetro

- Dipende da: #3 (contratto dati, mergiata), #15 e #26 (test con PostgreSQL reale e regole sul codice, mergiate).
- Sorgenti di riferimento: `app/cpy/CVACT01Y.cpy`, `docs/legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv`, `app/jcl/ACCTFILE.jcl` (`KEYS(11 0)`).
- Cartelle ammesse: `carddemo-domain/src/main/resources/db/migration/**` (la migrazione: da qui la vedono, attraverso le dipendenze già ammesse tra moduli, le applicazioni, i test e il futuro caricatore), `carddemo-parity/**` (test), i `pom.xml` strettamente necessari (Flyway con il suo modulo per PostgreSQL e l'integrazione di Spring Boot, a versione fissata, nelle applicazioni `online` e `batch` e dove servono i test), i file `application*.properties` delle applicazioni, `smoke.sh` (solo per verificare che la migrazione sia stata applicata dalle applicazioni), `verify.sh` e `quality/RapportoSurefire.java` (solo per rendere obbligatoria l'esecuzione delle suite nuove, vedi controllo 6), gli altri file di `quality/` solo se un controllo esistente va adeguato a un numero che cambia (dichiarandolo), `docs/contratti.md` (nuova sezione "Tabella dei conti"), `docs/sviluppo.md`.
- Fuori ambito: caricamento dei dati (issue successiva), le altre dieci tabelle, entità o repository usati da programmi tradotti, qualsiasi indice o vincolo non ricavato dal contratto.

## Specifica

### Decisioni (delegate, da registrare)

1. **Strumento di migrazione: Flyway**, a versione fissata, eseguito all'avvio delle applicazioni e nei test. Motivo: è lo strumento previsto da Spring Boot, le migrazioni sono file SQL leggibili. Alternativa scartata: `ddl-auto` di Hibernate (lo schema non sarebbe versionato né derivato dal contratto).
2. **La tabella conserva valori, non byte, e il sistema Java accetta solo dati in rappresentazione canonica.** Gli importi sono `NUMERIC(12,2)`, la chiave `NUMERIC(11,0)`. Un valore numerico ha una sola scrittura in byte nel profilo dell'oracle (quella che `encode` di #54 produce); un record che ne usa un'altra (per esempio lo zero con segno negativo, o un segno alternativo) **non viene caricato**: il caricatore si ferma e lo segnala (issue del caricamento). Così ogni riga della tabella corrisponde a un solo record di byte, e la parità con l'oracle si dichiara per gli ingressi canonici. I 50 conti di esempio lo sono tutti. Che cosa fa l'originale con un ingresso non canonico resta un'osservazione dell'oracle (#55, scenario di osservazione), non un comportamento che il Java promette. Alternative scartate: colonne aggiuntive con la rappresentazione originale di ogni importo (complica ogni programma successivo per un caso che i dati non contengono); mascherare nel riferimento le posizioni interessate (la tabella delle esclusioni di #55 riguarda ciò che il sorgente non determina, non ciò che la persistenza Java perde, e una maschera per posizione nasconderebbe errori di segno veri).
3. **Le date restano testo.** I tre campi data sono `PIC X(10)` e il legacy non li valida al caricamento: colonne di testo di 10 caratteri, non `DATE`.
3b. **Un campo `PIC X(n)` è una colonna `TEXT COLLATE "C"` con il vincolo `CHECK (char_length(colonna) = n)`** (specifica aggiornata due volte il 28 novembre 2026: dopo la validazione 1 della PR #61, registro voce 102, e dopo il fermo dell'Esecutore, voce 103: `VARCHAR(n)` tronca senza errore un valore più lungo la cui eccedenza è di soli spazi, prima di valutare il vincolo). La lunghezza vive solo nel vincolo. La colonna contiene sempre esattamente n caratteri, spazi finali compresi: gli spazi sono dati, come nel record COBOL. Motivo: con `CHAR(n)` PostgreSQL toglie gli spazi finali in ogni conversione a `text`, anche implicita; `lower(colonna) = lower(?)` con un parametro di n caratteri non trova la riga, mentre in COBOL lo stesso confronto è vero (`COACTUPC.cbl:4139-4140` usa `FUNCTION LOWER-CASE` su questi campi). La collazione `"C"` rende confronti e ordinamenti dipendenti dai soli codici dei caratteri, non dalla lingua del database. Chi scrive deve fornire n caratteri: un valore più corto è rifiutato dal vincolo, non riempito. Convertirle sarebbe una miglioria che cambia il comportamento sui valori non validi.
4. **Il `FILLER` non ha una colonna**: un record con `FILLER` diverso da 178 spazi non viene caricato (stessa regola del punto 2).
5. **Convivenza con Spring Batch**: l'inizializzatore di Spring Batch continua a creare le proprie tabelle di metadati; Flyway gestisce solo `account`, con uno storico proprio. Poiché un database già usato contiene le tabelle `batch_*` senza storico Flyway, l'introduzione richiede un volume PostgreSQL nuovo o ricreato: il comando va documentato in `docs/sviluppo.md`. Nessun `baseline` implicito e nessuna disattivazione dell'inizializzatore: se le due cose non convivono su un database vuoto, fermarsi con `needs-spec-update`.

### Tabella `account`

Una colonna per ogni campo elementare del contratto diverso dal `FILLER`, nell'ordine del copybook:

| Campo COBOL | `PICTURE` | Colonna | Tipo |
| --- | --- | --- | --- |
| `ACCT-ID` | `9(11)` | `acct_id` | `NUMERIC(11,0)`, chiave primaria, vincolo `>= 0` |
| `ACCT-ACTIVE-STATUS` | `X(01)` | `acct_active_status` | `TEXT COLLATE "C"`, `CHECK (char_length = 1)` |
| `ACCT-CURR-BAL` | `S9(10)V99` | `acct_curr_bal` | `NUMERIC(12,2)` |
| `ACCT-CREDIT-LIMIT` | `S9(10)V99` | `acct_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-CASH-CREDIT-LIMIT` | `S9(10)V99` | `acct_cash_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-OPEN-DATE` | `X(10)` | `acct_open_date` | `TEXT COLLATE "C"`, `CHECK (char_length = 10)` |
| `ACCT-EXPIRAION-DATE` | `X(10)` | `acct_expiraion_date` | `TEXT COLLATE "C"`, `CHECK (char_length = 10)` (il refuso del copybook si conserva nel nome) |
| `ACCT-REISSUE-DATE` | `X(10)` | `acct_reissue_date` | `TEXT COLLATE "C"`, `CHECK (char_length = 10)` |
| `ACCT-CURR-CYC-CREDIT` | `S9(10)V99` | `acct_curr_cyc_credit` | `NUMERIC(12,2)` |
| `ACCT-CURR-CYC-DEBIT` | `S9(10)V99` | `acct_curr_cyc_debit` | `NUMERIC(12,2)` |
| `ACCT-ADDR-ZIP` | `X(10)` | `acct_addr_zip` | `TEXT COLLATE "C"`, `CHECK (char_length = 10)` |
| `ACCT-GROUP-ID` | `X(10)` | `acct_group_id` | `TEXT COLLATE "C"`, `CHECK (char_length = 10)` |

Tutte le colonne `NOT NULL`: un record COBOL non ha campi assenti. Nessun altro vincolo oltre a quelli elencati (chiave primaria, `>= 0` sulla chiave, lunghezza esatta dei testi), nessun valore predefinito, nessun indice oltre a quello implicito della chiave primaria.

### Controlli, ciascuno con prova negativa

1. La migrazione gira su un PostgreSQL vuoto (Testcontainers, stessa immagine fissata del progetto) e produce esattamente la tabella della specifica: nomi, ordine, tipi, precisione e scala, `NOT NULL`, chiave primaria, letti da `information_schema` e confrontati con una tabella attesa scritta a mano nel test. Si leggono e si confrontano anche: le definizioni di tutti i vincoli (compreso il `CHECK` sulla chiave), i valori predefiniti (nessuno), gli indici (solo quello della chiave primaria).
2. Corrispondenza con il contratto: per ogni riga elementare non `FILLER` di `CVACT01Y.ACCOUNT-RECORD.tsv` (letto dal repository, non copiato) esiste una colonna, con tipo coerente con `PICTURE` secondo una regola scritta (`X(n)` → `TEXT COLLATE "C"` con vincolo di lunghezza esatta n, letta dalla definizione del vincolo; `9(n)` → `NUMERIC(n,0)`; `S9(i)V9(d)` → `NUMERIC(i+d,d)`); nessuna colonna in più.
3. Limiti: il massimo e il minimo valore della `PICTURE` di ogni colonna numerica si inseriscono e si rileggono identici (`BigDecimal`, stessa scala); un valore con una cifra in più è rifiutato dal database; `acct_id = -1` è rifiutato; una chiave duplicata è rifiutata. Testo, sempre con inserimento parametrizzato e senza cast: un valore più lungo o più corto di n è rifiutato, anche quando l'eccedenza è di soli spazi; un valore di n caratteri si rilegge identico via JDBC, spazi finali compresi, anche se è di soli spazi o ha spazi finali; il confronto `colonna = ?` e i confronti attraverso funzioni (`lower(colonna) = lower(?)`, conversione a `text`) con un parametro di n caratteri trovano la riga; un parametro senza gli spazi finali non la trova (documentarlo: i programmi tradotti confrontano sempre valori di lunghezza piena). Ordinamento di testi con maiuscole, minuscole, cifre e spazi secondo i codici dei caratteri. Il comportamento osservato va scritto in `docs/contratti.md`, insieme all'arrotondamento silenzioso dei decimali in eccesso da parte di PostgreSQL (da cui la regola: gli importi si scrivono già alla scala della colonna).
4. Ordinamento: righe inserite in ordine sparso si rileggono con `ORDER BY acct_id` in ordine numerico crescente (caso di prova: 9, 10, 100, 99999999999).
5. La migrazione applicata due volte non cambia nulla e non fallisce; una migrazione già applicata e poi modificata fa fallire l'avvio (controllo di Flyway attivo). Primo avvio e riavvio delle applicazioni su un database vuoto, con le tabelle di Spring Batch create dal loro inizializzatore.
6. **Ciascuna applicazione applica davvero la migrazione, con il proprio classpath distribuito**: `smoke.sh` verifica, dopo l'avvio, che `account` esista **come tabella** (non una vista con lo stesso nome) e che lo storico di Flyway riporti la migrazione riuscita; e prova anche `batch` come primo migratore su un database vuoto, controllando gli oggetti creati. Prove negative, ciascuna deve rendere rosso lo smoke: Flyway disattivato in `online`; in `batch`; `spring.flyway.skip-executing-migrations=true` in `batch`; lo starter di Flyway tolto dal POM di `online`; dal POM di `batch`; la migrazione che crea una vista `account`. I test di avvio in `carddemo-parity` condividono il classpath dei due moduli: va dichiarato in documentazione che la prova per applicazione è nello smoke.
7. **Le suite nuove sono obbligatorie**: `verify.sh` pretende nel rapporto della corsa corrente i casi delle classi di test nuove, per nome, eseguiti e non saltati (stesso meccanismo usato per i vettori del codec). Prove negative: suite assente; suite saltata.

Prove negative: il `CHECK` sulla chiave tolto; un `DEFAULT 0` aggiunto a una colonna; un indice non univoco aggiunto; una colonna con scala sbagliata; due colonne scambiate di posto; una colonna resa annullabile; la chiave primaria tolta; una colonna in più; una riga tolta dalla tabella attesa del test insieme alla colonna (deve accorgersene il controllo 2, che legge il contratto).

## Invarianti di parità

- Chiave e ordine di chiave del file indicizzato; precisione e scala degli importi; nessun valore predefinito che riempia un campo mancante.

## Criteri di accettazione

1. `./verify.sh` esce con 0 e pretende i test nuovi eseguiti (controllo 7).
2. `./smoke.sh` esce con 0, con il controllo 6.
3. `./quality/regressioni-regole.sh` e `./quality/regressioni-verify.sh` escono con 0; di `./quality/regressioni-copertura.sh` i casi toccati dal diff.
4. Ogni prova negativa è riportata con nome e diagnosi.
5. `git status --short` vuoto; diff nel solo perimetro; versione di Flyway fissata; nessun profilo Maven.
6. CI verde sullo SHA finale.

## Strategia di rollback

Revert della PR per il codice. Un database di sviluppo su cui la migrazione è già stata applicata va ricreato (comando in `docs/sviluppo.md`): il revert Git non toglie la tabella.

## Limiti per l'agente

- Unico prerequisito dell'host: Docker e Git. Mai un database in memoria.
- Una sola issue: niente caricamento, niente altre tabelle, niente entità per programmi futuri.
- Se il contratto o PostgreSQL smentiscono la specifica: fermarsi, commento tecnico, `needs-spec-update`.
- Autocontrollo delle quattro famiglie prima della PR. File di appoggio sull'host con prefisso `issue-w1a-`.
