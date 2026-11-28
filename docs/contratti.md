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
- `NoFloatingPointBytecodeTest`: ispeziona con ASM (la copia di spring-core) tutte le classi compilate del modulo (`target/classes`, ogni pacchetto): nessuna istruzione, costante, campo, firma, variabile locale, chiamata o riferimento a metodo in virgola mobile, e nessuna conversione con perdita di `BigInteger`, `BigDecimal` o `Number` (`longValue`, `intValue`, `shortValue`, `byteValue`, `doubleValue`, `floatValue`, `toBigInteger`; ammesse le forme `…Exact`). Serve perché le regole sul testo di #26 non vedono i tipi impliciti (`BigDecimal.valueOf(Math.pow(10, s))` le passa). Il test prova anche che l'ispezione vede questi passaggi.
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
- **Test svuotato.** Il controllo del rapporto prova che ogni vettore ha prodotto il suo marcatore dopo i controlli, non che i controlli siano rimasti: un test modificato per scrivere il marcatore senza verificare nulla passerebbe. È una modifica versionata del test, visibile nel diff; la difesa sono le mutazioni di `./quality/regressioni-codec.sh`, che devono restare rosse.
