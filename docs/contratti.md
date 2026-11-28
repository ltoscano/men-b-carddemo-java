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

Issue #59. Prima tabella di business in PostgreSQL: `account`, una riga per record `ACCOUNT-RECORD` del file indicizzato dei conti (`AWS.M2.CARDDEMO.ACCTDATA.VSAM.KSDS`, chiave `KEYS(11 0)` in `app/jcl/ACCTFILE.jcl`). La crea la migrazione versionata `carddemo-domain/src/main/resources/db/migration/V1__account.sql`, applicata da Flyway all'avvio di `online` e di `batch` (dettagli su Flyway e convivenza con Spring Batch in [`sviluppo.md`](sviluppo.md#tabella-dei-conti-e-flyway-59)). La tabella è vuota: il caricamento dei 50 conti di esempio è un'issue successiva.

### Colonne

Una colonna per ogni campo elementare del contratto [`CVACT01Y.ACCOUNT-RECORD.tsv`](legacy-map/data-contract/contratti/CVACT01Y.ACCOUNT-RECORD.tsv) diverso dal `FILLER`, nell'ordine del copybook (`app/cpy/CVACT01Y.cpy`). Regola dei tipi: `X(n)` → `CHAR(n)`; `9(n)` → `NUMERIC(n,0)`; `S9(i)V9(d)` → `NUMERIC(i+d,d)`.

| Campo COBOL | `PICTURE` | Colonna | Tipo |
| --- | --- | --- | --- |
| `ACCT-ID` | `9(11)` | `acct_id` | `NUMERIC(11,0)`, chiave primaria, `CHECK (acct_id >= 0)` |
| `ACCT-ACTIVE-STATUS` | `X(01)` | `acct_active_status` | `CHAR(1)` |
| `ACCT-CURR-BAL` | `S9(10)V99` | `acct_curr_bal` | `NUMERIC(12,2)` |
| `ACCT-CREDIT-LIMIT` | `S9(10)V99` | `acct_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-CASH-CREDIT-LIMIT` | `S9(10)V99` | `acct_cash_credit_limit` | `NUMERIC(12,2)` |
| `ACCT-OPEN-DATE` | `X(10)` | `acct_open_date` | `CHAR(10)` |
| `ACCT-EXPIRAION-DATE` | `X(10)` | `acct_expiraion_date` | `CHAR(10)` (il refuso del copybook resta nel nome) |
| `ACCT-REISSUE-DATE` | `X(10)` | `acct_reissue_date` | `CHAR(10)` |
| `ACCT-CURR-CYC-CREDIT` | `S9(10)V99` | `acct_curr_cyc_credit` | `NUMERIC(12,2)` |
| `ACCT-CURR-CYC-DEBIT` | `S9(10)V99` | `acct_curr_cyc_debit` | `NUMERIC(12,2)` |
| `ACCT-ADDR-ZIP` | `X(10)` | `acct_addr_zip` | `CHAR(10)` |
| `ACCT-GROUP-ID` | `X(10)` | `acct_group_id` | `CHAR(10)` |

Tutte le colonne sono `NOT NULL` (un record COBOL non ha campi assenti). Nessun valore predefinito, nessun altro vincolo, nessun indice oltre a quello della chiave primaria (`account_pkey`).

Decisioni della specifica (registro delle approvazioni, voce 100):

- **Valori, non byte.** La tabella conserva valori; il sistema Java accetta solo record in rappresentazione canonica (la scrittura in byte che `encode` di #54 produce). Un record con un'altra rappresentazione dello stesso valore (per esempio lo zero con segno negativo) non viene caricato: il caricatore si ferma e lo segnala. La parità con l'oracle si dichiara per gli ingressi canonici; i 50 conti di esempio lo sono tutti.
- **Le date restano testo** (`CHAR(10)`, non `DATE`): il legacy non le valida al caricamento, e convertirle cambierebbe il comportamento sui valori non validi.
- **Il `FILLER` non ha colonna**: un record con il `FILLER` diverso da 178 spazi non viene caricato.

### Comportamento osservato di PostgreSQL

PostgreSQL 18.7 (immagine di `compose.yaml`), driver JDBC 42.7.14, inserimento parametrizzato (`setBigDecimal`, `setString`) senza cast. È ciò su cui contano i programmi tradotti; ogni riga è un caso di `AccountSchemaTest`.

Importi e chiave:

- Massimo e minimo della `PICTURE` (`9999999999.99` e `-9999999999.99`; per la chiave `99999999999` e `0`) si rileggono con `getBigDecimal` identici, stessa scala (`equals`, non `compareTo`).
- Una cifra intera in più (`10000000000.00`, `-10000000000.00`, chiave `100000000000`) è rifiutata: SQLSTATE `22003`, `numeric field overflow`.
- `acct_id = -1` è rifiutato dal vincolo `account_acct_id_check` (SQLSTATE `23514`); una chiave duplicata da `account_pkey` (SQLSTATE `23505`).
- **Decimali in più: arrotondati, non rifiutati.** `0.005` diventa `0.01`, `-0.005` diventa `-0.01`, `1.234` diventa `1.23` (metà lontano da zero), senza errore. Chi scrive un importo deve portarlo prima alla scala 2 con l'arrotondamento o il troncamento del COBOL, esplicito in Java; non si conta sull'arrotondamento del database.
- `ORDER BY acct_id` è numerico: 9, 10, 100, 99999999999.

Testo `CHAR(n)`:

| Valore scritto in un `CHAR(10)` | Esito | `getString` (JDBC) | `colonna::text` |
| --- | --- | --- | --- |
| più corto (`C`) | accettato, riempito di spazi a 10 caratteri | `C` seguito da 9 spazi | `C` |
| spazi interni e iniziali (` D E`) | accettato, riempito | ` D E` seguito da 6 spazi | ` D E` |
| più lungo, eccedenza di soli spazi | accettato, **troncato** a 10 senza errore | i primi 10 caratteri | i primi 10 caratteri |
| più lungo, eccedenza con un carattere non spazio (`AAAAAAAAAAX`, `AAAAAAAAAA X`, 10 spazi e `X`) | **rifiutato**, SQLSTATE `22001`, `value too long for type character(10)` | — | — |
| soli spazi, o stringa vuota | accettato, 10 spazi (non `NULL`) | 10 spazi | stringa vuota |

`CHAR(1)` si comporta allo stesso modo.

- **Lettura.** `getString` restituisce il valore riempito a `n` caratteri, come il campo `X(n)` del COBOL: gli spazi finali non si perdono in lettura.
- **Confronti.** Con un parametro passato da `setString` (il driver lo invia come `varchar`) PostgreSQL confronta come `CHAR` e gli spazi finali non contano: `acct_group_id = ?` trova il valore memorizzato `G1` (riempito) con `G1`, `G1  ` e `G1` riempito a 10; non lo trova con ` G1` (lo spazio iniziale conta). È lo stesso risultato del COBOL, che nel confronto allunga con spazi l'operando più corto.
- **Conversione a `text`.** `colonna::text` toglie gli spazi finali. Con un parametro convertito a `text` (`acct_group_id = ?::text`) il confronto avviene tra testi: `G1` trova la riga, `G1` riempito a 10 **no**. I programmi tradotti non convertono queste colonne a `text` nei confronti e non usano la forma convertita come valore del campo.

Esito rispetto alla condizione di arresto della specifica ("`CHAR(n)` altera gli spazi finali in lettura o nei confronti in un modo che cambia un risultato osservabile"): in lettura JDBC e nei confronti con i parametri come li invia il driver gli spazi finali non cambiano il risultato rispetto al COBOL; li toglie solo la conversione esplicita a `text`, che è documentata qui come forma da non usare. Per questo l'issue non si è fermata.

### Come si verifica

Test in `carddemo-parity/src/test/java/io/github/ltoscano/carddemo/parity/`, contro PostgreSQL reale (Testcontainers, immagine e digest di `compose.yaml`):

- `AccountSchemaTest` (controlli 1, 3, 4): applica la migrazione con Flyway a un database vuoto e confronta con attese scritte a mano nel test colonne (nome, ordine, tipo, lunghezza, precisione, scala, `NOT NULL`, valore predefinito) lette da `information_schema`, valori predefiniti in `pg_attrdef`, tutte le definizioni dei vincoli in `pg_constraint` (da PostgreSQL 18 anche i `NOT NULL`), indici in `pg_indexes`, oggetti dello schema `public` e trigger; poi i limiti e il comportamento descritti sopra. Ogni caso lavora in una transazione che annulla alla fine.
- `AccountContrattoTest` (controllo 2): legge il contratto dal repository (proprietà `menb.contratto.account`, impostata dal POM di `carddemo-parity`) e, con la regola dei tipi scritta nel test e indipendente dalle attese di `AccountSchemaTest`, pretende per ogni campo elementare non `FILLER` una colonna con nome e tipo corrispondenti, nello stesso ordine, e nessuna colonna in più. Controlla anche che cifre e lunghezza del contratto concordino con la `PICTURE`; una `PICTURE` o un `USAGE` fuori dalla regola fanno fallire il test.
- `AccountMigrazioneTest` (controllo 5): la migrazione applicata due volte non cambia schema né storico; una migrazione applicata e poi modificata fa fallire l'avvio di `online` e di `batch` con `FlywayValidateException` (`checksum mismatch`), mentre la stessa migrazione non modificata, letta dalla stessa cartella, li lascia partire; primo avvio e riavvio delle due applicazioni su un database vuoto, nei due ordini (`batch, online, batch, online` e `online, batch, online, batch`), con lo storico di Flyway che resta una sola riga e le tabelle di Spring Batch create dal loro inizializzatore.
- `./verify.sh` pretende nel rapporto di questa corsa tutti i casi delle tre classi, per nome, eseguiti e non saltati (passo 3/7).
- `./smoke.sh` verifica sullo stack Compose che `online` abbia creato `account` e lo storico di Flyway con la sola `V1__account.sql` riuscita, e che `batch` esegua Flyway al suo avvio.

### Limiti dichiarati

- Parità solo per ingressi canonici (decisione sopra): ciò che l'originale fa con un importo non canonico resta un'osservazione dell'oracle (#55).
- Caratteri oltre ASCII, codifica del database e ordinamento delle colonne di testo non sono esaminati qui: la tabella si ordina solo per chiave numerica; il percorso dei caratteri riguarda il caricamento.
