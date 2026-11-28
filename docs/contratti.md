# Contratti condivisi

Tipi del modulo `carddemo-domain` che ogni programma tradotto userà allo stesso modo. Le regole complete stanno nei documenti di Wave 0A citati in ogni sezione; qui si dice che cosa offre il codice Java, come si chiama e come si verifica.

## Codifica dei campi

Issue #54. Porta in Java le regole con cui i byte di un campo COBOL diventano un valore e viceversa, solo per il profilo `oracle-gnucobol` (i byte come li legge e scrive l'oracle GnuCOBOL di questo repository). Le regole, le fonti e i casi limite sono in [`docs/legacy-map/data-contract/codifica.md`](legacy-map/data-contract/codifica.md); la colla di riferimento è `analysis/data-codec/glue/codec.py`. Il Java non aggiunge regole: se una sembra strana, è quella osservata sull'oracle.

Tipi, nel pacchetto `io.github.ltoscano.carddemo.domain`:

| Tipo | Che cosa è |
| --- | --- |
| `FieldCategory` | le cinque categorie: `ALPHANUMERIC`, `DISPLAY_UNSIGNED`, `DISPLAY_SIGNED`, `COMP_3`, `COMP` |
| `FieldPicture` | geometria di un campo: `FieldPicture.of(categoria, "S9(10)V9(2)")` ricava lunghezza in byte, scala e segno dalla `PICTURE` normalizzata (la "variante" di `codifica.md`) |
| `GnuCobolFieldCodec` | le tre operazioni, distinte: `decode`, `reencode`, `encode` |
| `DecodedField` | risultato della decodifica: `status()`, `number()` o `text()` (presenti solo se valido), `originalBytes()` (sempre) |
| `DecodeStatus` | `VALID`, `INVALID`, `BEYOND_PICTURE` |
| `FieldEncodingException`, `IncompleteFieldException` | rifiuto esplicito di un valore non rappresentabile; campo che non sta tutto nel record |

Le tre operazioni:

- **`decode(picture, record, offset)`**: byte → stato e, solo se valido, valore. Prima di convertire verifica che il campo stia tutto nel record (offset non negativo, `offset + lunghezza ≤ lunghezza del record`), altrimenti `IncompleteFieldException`, senza stato né valore. Un campo non valido e un binario oltre la `PICTURE` non hanno valore (voci 20 e 63 del registro). I numeri sono `BigDecimal` con la scala della `PICTURE`, costruiti da interi esatti; mai `double` o `float`.
- **`reencode(decoded)`**: ricodifica conservativa, restituisce i byte letti tali e quali (uno zero negativo resta negativo).
- **`encode(picture, BigDecimal)`** e **`encode(picture, String)`**: valore nuovo → byte nella rappresentazione che il profilo scrive. Ogni scala è accettata se la conversione alla scala della `PICTURE` è esatta (per `S9(4)V9(2)`: `1`, `1.2`, `1.20`, `1.200` sì, `1.234` no). Un valore oltre la `PICTURE`, con cifre decimali di troppo, negativo in un campo senza segno, un testo più lungo del campo o con un carattere oltre U+00FF è rifiutato con `FieldEncodingException`: niente troncamento né arrotondamento silenzioso. Il troncamento di un `MOVE` COBOL (colonna `move` dei vettori) è un comportamento del COBOL, non del codec.

### Un esempio per categoria

Esempi presi da copybook di CardDemo (`legacy/aws-mainframe-modernization-carddemo/app/cpy/`); byte in esadecimale, `HH*n` = n volte il byte `HH`.

| Categoria | Campo (file:riga) | Chiamata Java | Byte | Valore |
| --- | --- | --- | --- | --- |
| alfanumerico | `ACCT-ACTIVE-STATUS PIC X(01)` (`CVACT01Y.cpy:6`) | `decode(FieldPicture.of(ALPHANUMERIC, "X(1)"), record, offset)` | `59` | `text()` = `"Y"`; `encode(p, "Y")` = `59` |
| `DISPLAY` senza segno | `ACCT-ID PIC 9(11)` (`CVACT01Y.cpy:5`) | `decode(FieldPicture.of(DISPLAY_UNSIGNED, "9(11)"), record, offset)` | `30*10 31` | `number()` = `1` (scala 0); `20*11` (spazi) è `INVALID`, senza valore |
| `DISPLAY` con segno | `ACCT-CURR-BAL PIC S9(10)V99` (`CVACT01Y.cpy:7`) | `decode(FieldPicture.of(DISPLAY_SIGNED, "S9(10)V9(2)"), record, offset)` | `30*8 31 32 33 4D` | `number()` = `-12.34`; `30*11 7D` (zero negativo `}`) vale `0.00`, `reencode` restituisce `7D`, `encode(p, 0.00)` scrive `7B` |
| `COMP-3` | `EXP-ACCT-CURR-BAL PIC S9(10)V99 COMP-3` (`CVEXPORT.cpy:50`) | `decode(FieldPicture.of(COMP_3, "S9(10)V9(2)"), record, offset)` | `00 00 00 01 23 45 6D` | `number()` = `-1234.56` |
| `COMP` | `EXP-CUST-ID PIC 9(09) COMP` (`CVEXPORT.cpy:25`) | `decode(FieldPicture.of(COMP, "9(9)"), record, offset)` | `00 00 00 7B` | `number()` = `123`; `3B 9A CA 00` (10^9) è `BEYOND_PICTURE`, senza valore |

### Come si verifica

Test in `carddemo-domain/src/test/java/io/github/ltoscano/carddemo/domain/`:

- `OracleGnuCobolVectorsTest`: legge dal repository (non ne tiene copie) `analysis/data-codec/vettori/oracle-gnucobol.tsv` e `oracle-oltre-picture.tsv`, con un lettore che applica la grammatica di `comune.py` (`VectorFile`). Conteggi dichiarati: 375 vettori, 336 di decodifica, 39 di codifica (25 riescono, 14 rifiutati), 10 osservazioni oltre la `PICTURE`. Ogni vettore è un caso del rapporto. In decodifica: stato, valore e scala (`equals`, non `compareTo`), byte originali, ricodifica conservativa, codifica del valore uguale alla colonna `byte`; il campo è provato da solo e dentro un record più lungo all'offset 8, tra byte di guardia diversi prima e dopo. In codifica: byte attesi o rifiuto. È **obbligatorio** quando c'è la proprietà di sistema `menb.verify.run`, che `./verify.sh` passa a Maven (il file mancante è allora un fallimento), ed è **saltato, e risulta saltato**, quando manca (build delle immagini, che non copia `analysis/`). Ogni caso, dopo aver superato tutti i controlli, scrive su stdout `VETTORE-VERIFICATO <id>`, dove `<id>` è `<file>:<riga>:<prime 16 cifre esadecimali dello SHA-256 della riga>`; surefire lo conserva nel rapporto, dentro il caso. Dopo Maven `./verify.sh` (passo 2/7) controlla con `quality/RapportoSurefire.java` che nel rapporto di questa corsa ci siano esattamente i casi `oracleGnuCobolVectors()[1..375]` e `beyondPictureObservations()[1..10]`, nessuno saltato, e che il k-esimo caso porti l'identificativo del k-esimo vettore, ricavato da `RapportoSurefire` leggendo il file con la stessa grammatica delle righe di `comune.py`. Così il rapporto prova *quali* vettori sono stati verificati, non solo quanti: lo stesso vettore ripetuto, un vettore saltato dal lettore o una riga in più nel file fanno fallire `./verify.sh`.
- `DisplayExhaustiveTest`: per ogni variante `DISPLAY` del censimento, i 256 valori dell'ultimo byte (campi con segno) e del primo byte del corpo, 3328 casi, contro una regola riscritta nel test senza usare il codice di decodifica (come `verifica.py`). Un segno iniziale in un campo senza segno è non valido.
- `GnuCobolFieldCodecTest`: campo incompleto e offset fuori dal record per ogni categoria, valori non rappresentabili, scale diverse, `PICTURE` non valide, copia difensiva dei byte.
- `VectorFileTest`: test diretti della grammatica del lettore su file temporanei (righe vuote secondo `str.isspace` di Python, compresa una riga di soli U+00A0; commenti in mezzo; nota facoltativa; esadecimale; stringhe JSON) e del rifiuto, non dello scarto, delle righe che non comprende.
- `NoFloatingPointBytecodeTest`: ispeziona con ASM (la copia di spring-core) tutte le classi compilate del modulo (`target/classes`, ogni pacchetto): nessuna istruzione, costante, campo, firma, variabile locale, chiamata o riferimento a metodo in virgola mobile, e nessuna conversione con perdita (`longValue()J`, `intValue()I`, `shortValue()S`, `byteValue()B`, `doubleValue()D`, `floatValue()F`, `toBigInteger()`; ammesse le forme `…Exact`) su qualunque proprietario che sia o estenda `Number`, metodi ereditati compresi. La gerarchia si risolve con le classi del modulo e poi con il JDK; un proprietario non risolvibile è segnalato. Sono vietati anche i restringimenti primitivi (`L2I`, `I2B`, `I2C`, `I2S`; quelli in virgola mobile lo sono già), salvo l'elenco esatto e motivato `ALLOWED_NARROWING`. Sono i cinque `(byte)`/`(char)` del codec, ciascuno su un valore già ristretto a 0-255 o a una cifra ASCII, con il numero di occorrenze per metodo: un restringimento nuovo, o uno in più nello stesso metodo, fa fallire il test. Serve perché le regole sul testo di #26 non vedono i tipi impliciti (`BigDecimal.valueOf(Math.pow(10, s))` le passa). Il test prova anche che l'ispezione vede questi passaggi.
- Prove negative: `./quality/regressioni-codec.sh` altera il codec, la vista del file dei vettori montata nel container o `verify.sh`, e richiede che `./verify.sh` fallisca per il motivo dichiarato (`--lista` per i casi).

### Che cosa il contratto non fa

- Il profilo `zos-ebcdic` (byte come su z/OS): non è implementato.
- La lettura di un record intero guidata da un contratto di #3 (posizioni dei campi): arriva con le entità, in Wave 1. Qui si decodifica un campo per volta, dati `PICTURE` e offset.
- Aritmetica sugli importi, arrotondamenti, stato di conversazione, transazioni, ordinamento, errori: restano in #16.
- Nessuna clausola che i contratti di CardDemo non usano (`SIGN SEPARATE`, `SYNCHRONIZED`, `JUSTIFIED`, `BLANK WHEN ZERO`), nessun binario oltre 18 cifre.

### Limiti dichiarati

- **Conteggi della `PICTURE`.** La grammatica è quella della colla (`[1-9][0-9]*`, senza limite superiore): `X(10000)` dà lo stesso risultato. Un conteggio, o una somma di cifre intere e decimali, oltre 2147483647 non può essere una lunghezza Java ed è rifiutato con `FieldEncodingException`; la colla lo accetterebbe e poi rifiuterebbe il campo come incompleto.
- **Oltre 28 cifre la colla non è esatta.** Il contesto `Decimal` predefinito di Python arrotonda a 28 cifre significative e la conversione di interi con più di 4300 cifre fallisce: per esempio `9(30)` con `123456789012345678901234567890` vale `1.234567890123456789012345679E+29` nella colla. Il codec Java resta esatto. Nessun campo di CardDemo supera 18 cifre; i confini provati contro la colla usano valori di al più 28 cifre.
- **A capo finale.** Le espressioni regolari della colla usano `$`, che in Python accetta anche un `\n` finale: `geometria("display-senza-segno", "9(4)\n")` è accettata. Il Java la rifiuta. Nessun dato o contratto contiene una `PICTURE` con un a capo.
- **Test svuotato o riscritto.** Il controllo del rapporto prova che ogni vettore ha prodotto il suo marcatore dopo i controlli, non che i controlli siano rimasti o abbiano guardato i dati giusti. Passerebbe un test modificato per scrivere il marcatore senza verificare nulla, oppure riscritto per verificare i dati di un'altra riga e scrivere l'identificativo della riga corrente. Le difese strutturali rendono questo secondo caso una riscrittura esplicita, non una modifica di una riga:
  - una riga (`VectorFile.Row`) si costruisce solo nel lettore, dal suo testo, e le colonne si ricavano sempre da quel testo, su cui si calcola anche l'impronta;
  - il marcatore lo scrive `check()` per la riga che ha appena verificato, quindi `check(rows.get(0))` al posto di `check(r)` è respinto (caso `vettore-altri-dati`).

  Resta comunque una modifica versionata del test, visibile nel diff; la difesa sono le mutazioni di `./quality/regressioni-codec.sh`, che devono restare rosse.

## Tabella dei conti

Issue #59. Prima tabella di business in PostgreSQL: `account`, una riga per record `ACCOUNT-RECORD` del file indicizzato dei conti (`AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS`, chiave `KEYS(11 0)` in `app/jcl/ACCTFILE.jcl`). La crea la migrazione versionata `carddemo-domain/src/main/resources/db/migration/V1__account.sql`, applicata da Flyway all'avvio di `online` e di `batch` (dettagli su Flyway e convivenza con Spring Batch in [`sviluppo.md`](sviluppo.md#tabella-dei-conti-e-flyway-59)). La riempie il caricatore dei conti (#60, sezione [Caricamento dei conti](#caricamento-dei-conti)).

### Colonne

Una colonna per ogni campo elementare del contratto [`CVACT01Y.ACCOUNT-RECORD.tsv`](legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv) diverso dal `FILLER`, nell'ordine del copybook (`app/cpy/CVACT01Y.cpy`). Regola dei tipi:

- `X(n)` → `TEXT COLLATE "C"` con il vincolo `CHECK (char_length(colonna) = n)`; la lunghezza sta solo nel vincolo;
- `9(n)` → `NUMERIC(n,0)`;
- `S9(i)V9(d)` → `NUMERIC(i+d,d)`.

| Campo COBOL | `PICTURE` | Colonna | Tipo |
| --- | --- | --- | --- |
| `ACCT-ID` | `9(11)` | `acct_id` | `NUMERIC(11,0)`, chiave primaria, `CHECK (acct_id >= 0)` |
| `ACCT-ACTIVE-STATUS` | `X(01)` | `acct_active_status` | `TEXT COLLATE "C"`, `CHECK (char_length(acct_active_status) = 1)` |
| `ACCT-CURR-BAL` | `S9(10)V99` | `acct_curr_bal` | `NUMERIC(12,2)` |
| `ACCT-CREDIT-LIMIT` | `S9(10)V99` | `acct_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-CASH-CREDIT-LIMIT` | `S9(10)V99` | `acct_cash_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-OPEN-DATE` | `X(10)` | `acct_open_date` | `TEXT COLLATE "C"`, `CHECK (char_length(...) = 10)` |
| `ACCT-EXPIRAION-DATE` | `X(10)` | `acct_expiraion_date` | `TEXT COLLATE "C"`, `CHECK (char_length(...) = 10)` (il refuso del copybook resta nel nome) |
| `ACCT-REISSUE-DATE` | `X(10)` | `acct_reissue_date` | `TEXT COLLATE "C"`, `CHECK (char_length(...) = 10)` |
| `ACCT-CURR-CYC-CREDIT` | `S9(10)V99` | `acct_curr_cyc_credit` | `NUMERIC(12,2)` |
| `ACCT-CURR-CYC-DEBIT` | `S9(10)V99` | `acct_curr_cyc_debit` | `NUMERIC(12,2)` |
| `ACCT-ADDR-ZIP` | `X(10)` | `acct_addr_zip` | `TEXT COLLATE "C"`, `CHECK (char_length(...) = 10)` |
| `ACCT-GROUP-ID` | `X(10)` | `acct_group_id` | `TEXT COLLATE "C"`, `CHECK (char_length(...) = 10)` |

Tutte le colonne sono `NOT NULL`, perché un record COBOL non ha campi assenti. Nessun valore predefinito. Gli unici vincoli sono la chiave primaria (`account_pkey`), il `CHECK` sulla chiave (`account_acct_id_check`) e la lunghezza esatta di ogni testo (`account_<colonna>_check`). L'unico indice è quello della chiave primaria.

Decisioni della specifica (registro delle approvazioni, voci 100, 102 e 103):

- **Valori, non byte.** La tabella conserva valori, e il sistema Java accetta solo record in rappresentazione canonica (la scrittura in byte che produce `encode` di #54). Un record che scrive lo stesso valore in un altro modo (per esempio lo zero con segno negativo) non viene caricato: il caricatore si ferma e lo segnala. La parità con l'oracle si dichiara per gli ingressi canonici; i 50 conti di esempio lo sono tutti.
- **Un campo `X(n)` contiene sempre esattamente n caratteri, spazi finali compresi**, come nel record COBOL: gli spazi sono dati. Chi scrive fornisce n caratteri; un valore più corto è rifiutato, non riempito. Le date restano testo (non `DATE`): il legacy non le valida al caricamento, e convertirle cambierebbe il comportamento sui valori non validi.
- **Né `CHAR(n)` né `VARCHAR(n)`.** Con `CHAR(n)` PostgreSQL toglie gli spazi finali in ogni conversione a `text`, anche implicita: `lower(colonna) = lower(?)` con un parametro di n caratteri non trova la riga (validazione 1 della PR #61), mentre in COBOL lo stesso confronto è vero (`COACTUPC.cbl:4139-4140`). Con `VARCHAR(n)` un valore più lungo la cui eccedenza è di soli spazi viene troncato a n senza errore prima del vincolo di lunghezza, quindi è accettato (osservato via JDBC il 28 nov 2026, commento sull'issue #59).
- **Collazione `"C"`**: confronti e ordinamenti seguono i soli codici dei caratteri, non la lingua del database (che è `en_US.utf8`).
- **Il `FILLER` non ha colonna**: un record con il `FILLER` diverso da 178 spazi non viene caricato.

### Comportamento osservato di PostgreSQL

Condizioni della prova: PostgreSQL 18.7 (immagine di `compose.yaml`), driver JDBC 42.7.14, inserimento parametrizzato (`setBigDecimal`, `setString`) senza cast. I programmi tradotti contano su questo comportamento. Ogni affermazione corrisponde a un caso di `AccountSchemaTest`.

Importi e chiave:

- Massimo e minimo della `PICTURE` si rileggono con `getBigDecimal` identici, con la stessa scala (confronto con `equals`, non `compareTo`): `9999999999.99` e `-9999999999.99` per gli importi, `99999999999` e `0` per la chiave.
- Una cifra intera in più è rifiutata con SQLSTATE `22003` (`numeric field overflow`): `10000000000.00`, `-10000000000.00`, chiave `100000000000`.
- `acct_id = -1` è rifiutato dal vincolo `account_acct_id_check` (SQLSTATE `23514`). Una chiave duplicata è rifiutata da `account_pkey` (SQLSTATE `23505`).
- **Decimali in più: arrotondati, non rifiutati.** Senza errore, `0.005` diventa `0.01`, `-0.005` diventa `-0.01` e `1.234` diventa `1.23` (metà lontano da zero). **Regola:** gli importi si scrivono già alla scala della colonna, con l'arrotondamento o il troncamento del COBOL esplicito in Java; non si conta sull'arrotondamento del database.
- `ORDER BY acct_id` è numerico: 9, 10, 100, 99999999999.

Testo (`TEXT COLLATE "C"`, esattamente n caratteri):

- **Lunghezza diversa da n: rifiutata** dal vincolo `account_<colonna>_check` (SQLSTATE `23514`), in ogni colonna. Casi provati:
  - più lungo con un carattere non spazio in più;
  - più lungo di un solo spazio;
  - più lungo di 12 spazi;
  - n+1 spazi;
  - stringa vuota;
  - per n = 10, anche `G` e n-1 spazi (più corti).
- **n caratteri: riletti identici** con `getString`, spazi finali compresi, con `char_length` uguale a n. Casi provati: soli spazi, nessuno spazio, `G1` seguito da spazi, ` D E` seguito da spazi.
- **Confronti con un parametro di n caratteri: trovano la riga.** Riga memorizzata: `G1` seguito da 8 spazi. Trovano la riga `acct_group_id = ?`, `lower(acct_group_id) = lower(?)` (con `g1` seguito da 8 spazi) e `acct_group_id::text = ?`.
- **Lo stesso parametro senza gli spazi finali (`G1`, `g1`) non la trova in nessuna delle tre forme.** **Regola:** i programmi tradotti scrivono e confrontano sempre valori di lunghezza piena (n caratteri, come il campo COBOL).
- **Ordinamento per codice del carattere**, sui valori riempiti a 10: spazi, `1`, `A`, `A1`, `B`, `G1`, `a`, `a1`, `b`, `g1`.

### Come si verifica

I test stanno in `carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/` e girano contro PostgreSQL reale (Testcontainers, immagine e digest di `compose.yaml`).

- **`AccountSchemaTest`** (controlli 1, 3, 4). Applica la migrazione con Flyway a un database vuoto e confronta il catalogo con attese scritte a mano nel test:
  - le colonne lette da `information_schema`: nome, ordine, tipo, lunghezza, precisione, scala, collazione, `NOT NULL`, valore predefinito;
  - i valori predefiniti in `pg_attrdef`;
  - tutte le definizioni dei vincoli in `pg_constraint` (da PostgreSQL 18 anche i `NOT NULL`, oltre ai sei vincoli di lunghezza);
  - gli indici in `pg_indexes`;
  - gli oggetti dello schema `public` e i trigger.

  Poi verifica i limiti e il comportamento descritti sopra. Ogni caso lavora in una transazione che annulla alla fine.
- **`AccountContrattoTest`** (controllo 2). Legge il contratto dal repository, attraverso la proprietà `menb.contratto.account` impostata dal POM di `carddemo-parity`. Applica la regola dei tipi scritta nel test, indipendente dalle attese di `AccountSchemaTest`, e pretende per ogni campo elementare non `FILLER`:
  - una colonna con nome e tipo corrispondenti, nello stesso ordine del contratto; per `X(n)`, `text` con collazione `C` e la lunghezza n letta dalla definizione del vincolo `CHECK ((char_length(colonna) = n))` nel catalogo;
  - nessuna colonna in più.

  Controlla anche che cifre e lunghezza del contratto concordino con la `PICTURE`. Una `PICTURE` o un `USAGE` fuori dalla regola fanno fallire il test.
- **`AccountMigrazioneTest`** (controllo 5). Verifica tre cose:
  - la migrazione applicata due volte non cambia né lo schema né lo storico;
  - una migrazione applicata e poi modificata fa fallire l'avvio di `online` e di `batch` con `FlywayValidateException` (`checksum mismatch`), mentre la stessa migrazione non modificata, letta dalla stessa cartella, li lascia partire;
  - primo avvio e riavvio delle due applicazioni su un database vuoto, nei due ordini (`batch, online, batch, online` e `online, batch, online, batch`): lo storico di Flyway resta una sola riga e le tabelle di Spring Batch le crea il loro inizializzatore.

  Questi avvii condividono il classpath dei due moduli: la prova per singola applicazione è nello smoke (vedi [`sviluppo.md`](sviluppo.md#tabella-dei-conti-e-flyway-59)).
- **`./verify.sh`** pretende nel rapporto di questa corsa tutti i casi delle tre classi, per nome, eseguiti e non saltati (passo 3/7).
- **`./smoke.sh`**, con le immagini distribuite, verifica che `online` crei `account` (una tabella secondo il catalogo, con 12 colonne) e lo storico di Flyway con la sola `V1__account.sql` riuscita. Verifica poi che `batch` esegua Flyway sul database già migrato e che, come primo migratore su un database vuoto, crei da sé gli stessi oggetti.

### Limiti dichiarati

- Parità solo per ingressi canonici (decisione sopra): ciò che l'originale fa con un importo non canonico resta un'osservazione dell'oracle (#55).
- Non esaminati qui: i caratteri oltre ASCII e la codifica del database (`UTF8`), che riguardano il caricamento (esaminati in #60, sezione seguente).

## Caricamento dei conti

Issue #60. Il modulo `carddemo-loader` carica nella tabella `account` un file di record a lunghezza fissa di 300 byte nel profilo dell'oracle, lo stesso formato che legge l'oracle GnuCOBOL. Il file di esempio è `analysis/oracle-dati/out/ACCTFILE.rec` (#53: 50 record, chiavi da 1 a 50, nell'ordine del file EBCDIC originale); lo stesso comando caricherà i file degli scenari di parità (#55), perché il file è un parametro.

### Che cosa offre il codice

Pacchetto `io.github.ltoscano.carddemo.loader`:

| Tipo | Che cosa è |
| --- | --- |
| `CampoConto` | il tracciato di `ACCOUNT-RECORD`: per ogni campo elementare, `FILLER` compreso e nell'ordine del contratto, nome COBOL, offset (da 0), lunghezza, categoria e `PICTURE` normalizzata per `FieldPicture.of`, colonna di `account` (nessuna per il `FILLER`). Riporta il contratto [`CVACT01Y.ACCOUNT-RECORD.tsv`](legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv), che non si legge a run time: `docs/` è escluso dal contesto di build delle immagini (`.dockerignore`). Il test `TracciatoContoTest` li confronta riga per riga |
| `CaricatoreConti` | `carica(Path file, Connection connessione)`: il caricamento, in una sola transazione; restituisce `EsitoCaricamento(record, giaCaricato)` |
| `CaricamentoRifiutato` | eccezione con la diagnosi: che cosa ha fermato il caricamento e dove |
| `CaricatoreApplication` | l'applicazione Spring Boot del servizio `loader` (vedi [`sviluppo.md`](sviluppo.md#caricamento-dei-conti-60)) |

Ogni campo si decodifica con `GnuCobolFieldCodec.decode` (#54) alla posizione del tracciato; il caricatore non riscrive regole di codifica. Gli importi passano a PostgreSQL come `BigDecimal` con esattamente la scala della colonna, che è quella della `PICTURE` (2). Il caricatore lo verifica prima di ogni `setBigDecimal` e altrimenti si ferma: PostgreSQL arrotonderebbe in silenzio i decimali in più (vedi "Comportamento osservato di PostgreSQL"), quindi la sola rilettura non basterebbe. I testi passano con `setString`, esattamente n caratteri, spazi finali compresi.

### Che cosa ferma il caricamento

Nessuna riga scritta (transazione annullata), `CaricamentoRifiutato` con una diagnosi che dice il record (da 1), il campo e i byte (offset da 0 nel file e nel record), e in esadecimale i byte letti:

| Condizione | Esempio di diagnosi (dai test) |
| --- | --- |
| dimensione non multipla di 300 | `1199 byte, non multiplo di 300: il record 4 e' incompleto, 299 byte dall'offset 900 del file` |
| campo numerico non valido | `record 3 (offset 600-899 del file), campo ACCT-CASH-CREDIT-LIMIT (offset 636-647 del file, 36-47 del record): campo numerico non valido (INVALID), byte 202020202020202020202020` |
| campo numerico non canonico (byte diversi da `encode(decode(byte))`) | zero negativo: `campo ACCT-CURR-BAL (...): rappresentazione non canonica del valore 0.00: byte 30303030303030303030307d, canonici 30303030303030303030307b`; segno alternativo (ultimo byte cifra ASCII invece della sovrapposizione): `campo ACCT-CREDIT-LIMIT (...): rappresentazione non canonica del valore 5000.00: byte 303030303030353030303030, canonici 30303030303035303030307b` |
| `FILLER` diverso da 178 spazi | `campo FILLER (offset 722-899 del file, 122-299 del record): il FILLER deve essere di 178 spazi, all'offset 899 del file c'e' il byte 58` |
| chiave duplicata | `campo ACCT-ID (offset 600-610 del file, 0-10 del record): chiave 1 duplicata, gia' nel record 1` |
| byte nullo in un campo di testo | `campo ACCT-GROUP-ID (offset 712-721 del file, 112-121 del record): byte nullo X'00' all'offset 714 del file, non rappresentabile in una colonna di testo` |
| importo con una scala diversa da quella della colonna (difesa: con la decodifica attuale non succede) | `campo ...: valore ... con scala 3, la colonna ... ha scala 2` |
| tabella `account` non vuota e diversa dal file | `la tabella account non e' vuota (50 righe) e non contiene esattamente i 50 record del file: ... Prima differenza: chiave 1, record 1 (offset 0-299 del file), campo ACCT-CURR-BAL (offset 12-23 del file, 12-23 del record): nella tabella 195.00 (byte 30303030303030313935307b), nel file byte ...`; altre forme: `la tabella ha la chiave 51, che nel file non c'e'`, `record 50 (...): la chiave ACCT-ID del file manca nella tabella` |

È la regola fissata dall'issue della tabella (#59): il sistema Java accetta solo ingressi canonici, così ogni riga corrisponde a un solo record di byte. Nulla viene normalizzato in silenzio e non esiste un elenco di "perdite accettate". I testi si verificano anche nell'altro verso (`encode(decode(byte))` uguale ai byte letti), che per un `X(n)` è l'identità: il controllo non scarta nulla oggi, rende esplicita la regola.

**Ordine, transazione, concorrenza.** Prima la dimensione del file. Poi, nella transazione:

1. `lock table account in exclusive mode`: il blocco esclude un altro caricatore e ogni scrittura fino alla fine della transazione, ma lascia le letture;
2. il conteggio delle righe di `account`;
3. con la tabella vuota, un record alla volta nell'ordine del file: decodifica e verifica di tutti i campi, controllo della chiave contro quelle già lette, verifica della scala, inserimento. Al primo errore la transazione si annulla; il caricamento conferma solo dopo l'ultimo record.

Due caricatori avviati insieme non possono quindi trovare entrambi la tabella vuota: il secondo attende il blocco, poi trova la tabella piena e la confronta con il suo file (vedi sotto). Un file vuoto (0 byte) su tabella vuota è valido: 0 record, 0 righe, caricamento riuscito.

**Riesecuzione** (specifica aggiornata dopo la validazione 1 della PR #66, registro voce 111). Su una tabella non vuota il caricatore non cancella e non aggiorna mai. Prima verifica tutto il file con le stesse regole, poi legge la tabella in ordine di chiave e confronta ogni riga, ricomposta con `encode` campo per campo, con il record del file che ha la stessa chiave:

- se la tabella contiene **esattamente** i record del file (stesse chiavi e ogni riga uguale al suo record), termina con successo senza scrivere (`EsitoCaricamento.giaCaricato()`; nel log `CARICAMENTO RIUSCITO: già caricato: 50 record, nessuna modifica`);
- altrimenti si ferma con la prima differenza in ordine di chiave: una riga diversa (chiave, record e campo, valore della tabella e byte del file), una chiave della tabella che il file non ha, oppure, dopo aver letto tutta la tabella, il primo record del file che manca.

Così un secondo `docker compose up` sullo stesso volume riesce, e un database diverso da quello atteso è comunque segnalato. Sul mainframe `ACCTFILE.jcl` cancella e ricrea il file indicizzato (`app/jcl/ACCTFILE.jcl`: `DELETE` alla riga 25, `DEFINE CLUSTER` alla 36, poi `REPRO` alla 61); l'equivalente qui è ricreare il volume (comando in [`sviluppo.md`](sviluppo.md#caricamento-dei-conti-60)).

**Caratteri oltre ASCII.** Il codec rappresenta ogni byte di un campo di testo come il carattere U+0000-U+00FF con lo stesso codice; PostgreSQL li conserva in UTF-8 (codifica del database letta nei test: `server_encoding`, `client_encoding` e codifica del database tutte `UTF8`). Il vincolo di lunghezza conta caratteri: un `X(10)` di dieci caratteri tra U+0080 e U+00FF occupa 20 byte (`octet_length`) ed è accettato. Solo U+0000 non è rappresentabile in una colonna di testo, ed è rifiutato prima di arrivare al database.

**Regola sugli importi nel codice compilato.** L'ispezione del bytecode di `NoFloatingPointBytecodeTest` (#54, sezione "Codifica dei campi") copre anche le classi di produzione di `carddemo-loader`, senza eccezioni ammesse. La esegue `IspezioneBytecodeCaricatoreTest`, che riusa quella logica attraverso il jar delle classi di test di `carddemo-domain` (sotto).

### Come si verifica

Test in `carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/` (più uno nel pacchetto `...domain`, sotto), contro PostgreSQL reale (Testcontainers, immagine di `compose.yaml`, migrazione con Flyway). Il contratto e il file di esempio si leggono dal repository (proprietà `menb.contratto.account` e `menb.dati.acctfile` impostate dal POM di `carddemo-parity`), senza copie.

- **`ContiDiProva`** (appoggio, indipendente dal caricatore): ricava il tracciato dal contratto con una regola propria (`PICTURE` normalizzata e categoria da `pic`, `usage`, `segno`; cifre intere e decimali dalle colonne `cifre_intere` e `cifre_decimali`), non da `CampoConto`, e applica i controlli della specifica tra un file e la tabella:
  1. righe = record; insieme delle chiavi uguale;
  2. **ritorno al formato fisso**: ogni riga, letta con `ORDER BY acct_id`, si ricompone con `GnuCobolFieldCodec.encode` e 178 spazi di `FILLER` alle posizioni del contratto; il risultato deve essere uguale byte per byte al record del file, per tutti i record;
  3. **totali di controllo**: la somma di ogni colonna numerica deve essere uguale (con `equals`, scala compresa) a quella calcolata dai byte del file con una lettura `DISPLAY` scritta nel test (cifre ASCII e sovrapposizione del segno, scala dalla colonna `cifre_decimali`), che non usa né il caricatore né la decodifica del codec;
  4. la sequenza delle chiavi con `ORDER BY acct_id` deve essere quella del file;
  6. **parametri consegnati al driver**: un intermediario (`java.lang.reflect.Proxy`) sulla connessione registra ogni `BigDecimal` passato a `setBigDecimal`; l'elenco deve essere, record per record, quello della lettura `DISPLAY` del test, con la stessa scala. Vede ciò che PostgreSQL arrotonderebbe in silenzio (un millesimo in più, una scala 3).
- **`TracciatoContoTest`** (controllo 7): due casi, entrambi confrontati campo per campo **direttamente con le righe del TSV** (nome, offset, lunghezza, categoria da `usage`/`pic`/`segno`, `PICTURE` normalizzata dalle colonne `lunghezza`, `cifre_intere`, `cifre_decimali`, colonna; geometria del codec uguale alle stesse colonne), senza passare da altro codice dei test:
  - `CampoConto` del caricatore;
  - a parte, il modello `ContiDiProva.tracciato()` che usa il codificatore dei test.

  Così uno scambio di offset fatto allo stesso modo nel caricatore e nel modello dei test fa fallire entrambi i casi.
- **`CaricamentoContiTest`**: tre casi.
  - `ACCTFILE.rec` caricato e confrontato con i controlli 1-4 e 6; primo e ultimo conto confrontati colonna per colonna con valori scritti a mano, letti dai byte del file; codifica del database dichiarata.
  - Secondo caricamento dello stesso file: riesce come "già caricato", nessun inserimento preparato, righe e `xmin` invariati.
  - Tabella diversa dal file: si ferma con la prima differenza, righe e `xmin` invariati. Casi provati: un importo alterato, una data alterata, una riga tolta, una riga in più, un file con un record in meno, un file vuoto.
- **`CaricamentoContiCasiTest`**: casi costruiti in file temporanei.
  - Rifiutati, ciascuno con la sua diagnosi e zero righe: zero negativo, segno alternativo, `FILLER` non vuoto, campo numerico con spazi, chiave duplicata, file troncato, byte nullo in un testo. Il record difettoso è il terzo di quattro, quindi una conferma anticipata lascerebbe righe.
  - Accettati, con i controlli 1-4 e 6 e il confronto di ogni colonna con il valore di partenza: massimo e minimo della `PICTURE` (`±9999999999.99`, chiavi `0` e `99999999999`); file vuoto; tre record distinguibili campo per campo (le tre date diverse tra loro, credito e addebito di ciclo non nulli e diversi, limite di credito diverso dal limite di anticipo, gruppo non vuoto, stato diverso da `Y` e diverso da record a record, importi negativi); tre record con tutti i byte `0x80`-`0xFF` nei campi di testo (stringa letta via JDBC e ricodifica byte per byte).
- **`CaricamentoConcorrenteTest`**: due caricatori avviati insieme su un database vuoto. Il test tiene un blocco `ACCESS EXCLUSIVE` su `account` finché `pg_locks` non mostra entrambi in attesa sulla tabella, poi lo rilascia; ogni attesa ha un limite.
  - Con le stesse chiavi: uno scrive, l'altro termina come "già caricato".
  - Con chiavi disgiunte: uno scrive, l'altro si ferma (`non contiene esattamente i 2 record del file`).

  In entrambi i casi la tabella corrisponde al file del vincitore.
- **`CaricatoreApplicazioneTest`**: l'applicazione avviata nel processo dei test su un database vuoto:
  - applica la migrazione, carica e termina con 0;
  - una seconda esecuzione termina con 0 senza scrivere (righe e `xmin` invariati);
  - con una riga alterata termina con 1 senza scrivere;
  - un file troncato termina con 1 e zero righe; file inesistente o argomenti sbagliati con 2.

  Stesso limite di `AccountMigrazioneTest`: il classpath è quello di `carddemo-parity`; la prova con l'immagine del caricatore è nello smoke.
- **`io.github.ltoscano.carddemo.domain.IspezioneBytecodeCaricatoreTest`** (in `carddemo-parity`, controllo 8): ispeziona le classi compilate di `carddemo-loader` (la cartella o il jar da cui le carica) con `NoFloatingPointBytecodeTest.supers` e `findings`. Le riusa attraverso il jar delle classi di test di `carddemo-domain` (`maven-jar-plugin`, obiettivo `test-jar`, esecuzione `classi-di-test` nel POM di `carddemo-domain`; dipendenza `type test-jar`, ambito `test`, nel POM di `carddemo-parity`); sta nel pacchetto `...domain` perché quei metodi sono visibili nel pacchetto. Pretende le quattro classi del caricatore e nessuna segnalazione: per il caricatore non c'è alcun restringimento ammesso.
- **`./verify.sh`** pretende nel rapporto di questa corsa tutti i casi delle sei classi, per nome, eseguiti e non saltati (passo 3/7).
- **`./smoke.sh`** verifica il servizio `loader` con la sua immagine (vedi [`sviluppo.md`](sviluppo.md#caricamento-dei-conti-60)).

### Limiti dichiarati

- Parità solo per ingressi canonici (decisione di #59): un file con un importo non canonico non si carica.
- Il file si legge tutto in memoria (15.000 byte per l'esempio): adatto ai file di CardDemo e degli scenari, non a file di dimensioni arbitrarie.
- Il confronto con una tabella già piena legge tutta la tabella in ordine di chiave: proporzionato a una tabella dei conti di CardDemo.
- Il blocco `EXCLUSIVE` protegge solo dai caricatori e dalle scritture concorrenti durante la transazione; un'applicazione che scrive in `account` dopo il caricamento rende la tabella diversa dal file, e il caricatore successivo (per esempio al prossimo `up`) si ferma.

## Contratto del job READACCT

Fissato dall'issue #65 insieme al test di parità (`carddemo-parity`, `ReadacctParitaTest`), prima della traduzione di `CBACT01C` (issue #67). La traduzione offre questa interfaccia e non la cambia.

| Punto | Contratto |
| --- | --- |
| Comando | jar eseguibile di `carddemo-batch` (`carddemo-batch-<versione>-exec.jar`), in un processo proprio, con questi argomenti e nessun altro: `--spring.batch.job.name=READACCT OUTFILE=<percorso> ARRYFILE=<percorso> VBRCFILE=<percorso>` (nomi DD di `app/jcl/READACCT.jcl`; i tre argomenti senza `--` sono parametri del job) |
| Nome del job | `Job.getName()` = `READACCT`; nome del bean e della classe liberi |
| Database | proprietà standard di Spring dalle variabili d'ambiente `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`; nessun'altra variabile è impostata dal test |
| Nessun job predefinito | con più di un job ogni avvio indica `spring.batch.job.name`. Da #67 i job sono due (`installationCheckJob`, `READACCT`): `smoke.sh`, `AccountMigrazioneTest` e `BatchApplicationTest` indicano `installationCheckJob`, il job che già eseguivano |
| Riesecuzione | due avvii consecutivi con lo stesso comando, sullo stesso database e sugli stessi percorsi riescono entrambi; il secondo sostituisce per intero i file esistenti (equivalente di `PREDEL` + esecuzione). Il chiamante non aggiunge parametri; come ottenerlo con Spring Batch è scelta della traduzione. Scelta di #67: `ParametriDiAvvio` (conversione degli argomenti del selettore di Spring Boot) aggiunge a ogni avvio con parametri un parametro identificativo `menb.avvio` con un valore nuovo, quindi ogni avvio è un'istanza nuova; un incrementatore sul job non serve, perché in Spring Batch 6.1 fa scartare i parametri passati |
| Lettura | tabella `account` in ordine crescente di `acct_id`, qualunque sia l'ordine fisico di inserimento |
| `OUTFILE` | record fissi di 107 byte, senza terminatori |
| `ARRYFILE` | record fissi di 110 byte, senza terminatori |
| `VBRCFILE` | record variabili con descrittore di record di z/OS (RDW), senza descrittore di blocco: 2 byte di lunghezza del record **compreso il descrittore** (byte più significativo per primo) e 2 byte `00`. Per un conto: `00 10 00 00` + 12 byte, `00 2B 00 00` + 39 byte. Lunghezza ammessa 5-84 (`LRECL=84`). Decisione delegata di #65: formato del sistema di origine, non quello di GnuCOBOL (`00 0C 00 00`, `00 27 00 00`) |
| Console | standard output: solo le righe dei `DISPLAY` dell'originale, una per `DISPLAY`, nell'ordine dell'originale, spazi finali conservati, ognuna terminata da LF (nessun CR); nessun banner, nessuna riga di log (log su standard error o su file). 2 + 15 × N righe |
| Codice di uscita | 0 a fine regolare. Da #67: 99 alla fine anomala del programma (`9999-ABEND-PROGRAM`, ogni ramo d'errore di `docs/programmi/CBACT01C.md`), dopo le righe letterali del ramo e la cancellazione dei tre file di uscita; 1 per un errore di avvio dell'applicazione prima del job (database irraggiungibile all'avvio, parametri `OUTFILE`/`ARRYFILE`/`VBRCFILE` mancanti o vuoti); 5 per un job fallito per un guasto che il programma non intercetta (un `Error` della JVM), mai 0 |

### Che cosa confronta il test

Riferimento: soltanto `oracle/golden/readacct/generati/golden/<scenario>/` (#55), scenari `esempio` e `mirato`; lo scenario `osservazione` è rifiutato (`SCENARIO-NON-AMMESSO`). Il comparatore (`ComparatoreReadacct`) non legge `esclusioni.tsv` né `correzioni.tsv`.

- `OUTFILE`, `ARRYFILE`: byte per byte con `<file>.riferimento.txt` (una riga esadecimale per record); si saltano solo i byte `**`, uno per uno. Un test a parte verifica che i byte `**` siano esattamente quelli di `esclusioni.tsv`.
- `VBRCFILE`: descrittori controllati con la regola sopra, record logici estratti da un lettore proprio, confrontati per numero, ordine, lunghezza e contenuto con `VBRCFILE.riferimento.txt`.
- Console: le righe di classe a di `console.riferimento.txt` coincidono, nella stessa posizione, con quelle dello standard output; le righe `#OSSERVAZIONE` devono esserci ma il contenuto non si confronta; totale 2 + 15 × N.
- Record N, N, 2N; codice di uscita 0.
- Preparazione: PostgreSQL reale e vuoto (Testcontainers), migrazione, conti caricati con `CaricatoreConti` (#60) da `ingresso.rec` dello scenario, contenuto di `account` ricomposto con il codificatore indipendente dei test e confrontato con quell'ingresso prima dell'avvio.
- Riesecuzione (`mirato`): dopo il primo avvio i tre file sono sostituiti da file più lunghi con contenuto sentinella (`S`); secondo avvio senza ricaricare; tutti i confronti si ripetono.
- Ordine di lettura (`mirato`): ingresso con i record in ordine inverso, caricato così (il test verifica l'ordine fisico con `ctid`); stessi riferimenti.

### Come si riconosce il job assente

Diagnostica nativa letta dall'applicazione attuale (Spring Boot 4.2.0, comando del contratto): il bean `jobLauncherApplicationRunner` non si crea perché `JobLauncherApplicationRunner.afterPropertiesSet` chiama `Assert.state`, il processo esce con 1 e lo standard output contiene:

```
org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'jobLauncherApplicationRunner' defined in class path resource [...BatchJobLauncherAutoConfiguration.class]: No job found with name 'READACCT'
...
Caused by: java.lang.IllegalStateException: No job found with name 'READACCT'
	at org.springframework.util.Assert.state(Assert.java:102) ...
	at org.springframework.boot.batch.autoconfigure.JobLauncherApplicationRunner.afterPropertiesSet(JobLauncherApplicationRunner.java:90) ...
```

Il test (`AvvioJob.jobAssente`) lo riconosce solo se valgono tutte: codice di uscita 1; in uno stesso flusso (stdout o stderr) una riga che inizia con `org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'jobLauncherApplicationRunner'` e, una volta sola in tutto l'output, la riga esatta `Caused by: java.lang.IllegalStateException: No job found with name 'READACCT'` seguita subito dai due frame `Assert.state(` e `JobLauncherApplicationRunner.afterPropertiesSet(`; nessuna traccia di avvio di un job o di un passo (`] launched with the following parameters`, `Executing step: [`, righe che Spring Batch scrive davvero: `AvvioJobTest` lo verifica sull'uscita reale di un job di prova); e, **indipendentemente dai log dell'applicazione sotto prova**, il repository JDBC di Spring Batch nel database del job esiste e non registra alcun job: `select (select count(*) from batch_job_instance), (select count(*) from batch_job_execution)` dà `0|0` (`AvvioJob.nessunJobRegistrato`). L'applicazione attuale usa il repository JDBC (`spring-boot-starter-batch-jdbc`, `spring.batch.jdbc.initialize-schema=always`) e crea le tabelle prima che il selettore fallisca: nel caso del job assente sono presenti e vuote (verificato da `AvvioJobTest.nessunJobReadacctRiconosciutoComeMotivoDichiarato` e dai quattro casi di parità con il jar vero); un job avviato vi registra un'istanza e un'esecuzione prima del primo passo. Database irraggiungibile o tabelle assenti: non è il job assente. Le righe di log da sole non bastano: un'applicazione con `logging.level.root=WARN` non le scrive. Ogni altro esito non è il motivo dichiarato: un errore con lo stesso testo prima della selezione (frame diversi), un job avviato che fallisce con lo stesso testo stampando la stessa traccia (traccia di avvio presente) e lo stesso job con i log a WARN fissati nell'applicazione (traccia di avvio assente, `1|1` nel repository) sono fallimenti ordinari (`AvvioJobTest`, tre controprove obbligatorie). Limite dichiarato: un'applicazione che stampasse la traccia nativa senza avviare alcun job, o che avviasse il job senza il repository JDBC nel database del test, sarebbe riconosciuta come job assente; casi di questo genere sono contraffazioni o configurazioni diverse da quella attuale, e la traduzione (#67) toglie comunque la marcatura.

### Diagnosi del comparatore

Ogni diagnosi nomina file, record e posizione da 1 (`BYTE-DIVERSO: OUTFILE record 3 posizione 20: atteso 32, trovato 33`). Le diagnosi strutturali indicano il primo record mancante o in eccesso e il suo offset in byte dall'inizio del file, contato da 0 (`NUMERO-DI-RECORD: OUTFILE ha 49 record, attesi 50: primo record mancante 50 (fine del file all'offset 5243)`; `LUNGHEZZA: OUTFILE di 5280 byte: record 50 troncato a 37 byte su 107 (fine del file all'offset 5280)`, dopo aver confrontato i byte presenti del record troncato); per la console la riga e la colonna del primo carattere diverso (`CONSOLE: riga 12 colonna 35: ...`) o la prima riga mancante o in eccesso con il suo testo.

### Che cosa il test non garantisce

- I byte mascherati (`**`: byte 77-78 di `OUTFILE`) non sono confrontati: qualunque valore è accettato (controprova `controprovaByteMascheratoAccettato`).
- Le righe di console `#OSSERVAZIONE` non sono confrontate nel contenuto (controprova `controprovaRigaDiOsservazioneConContenutoDiversoAccettata`).
- Lo standard error non è confrontato.
- Il comportamento su ingressi diversi dai due scenari, su tabella vuota o con errori di I/O non è coperto da questo test. Da #67 lo coprono i test del modulo `batch` (`Cbact01cTest`, `ReadacctJobTest`: addebito di ciclo diverso da zero, ogni ramo d'errore, tabella vuota, forma delle righe di console non confrontate qui); la tabella vuota è confrontata con l'oracle su un file dei conti vuoto (descrizione della PR di #67).
