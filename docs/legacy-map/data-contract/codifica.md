# Regole di codifica dei campi (issue #23)

Questo documento fissa come i byte di un campo di CardDemo diventano un valore e come un valore diventa byte, per ogni rappresentazione che compare nei contratti dati di #3 (`contratti/`). È il ponte tra il contratto, che dice *dove* sta ogni campo, e chi leggerà o scriverà i dati: fixture, loader, confronti di parità.

Tutto si rigenera e si controlla in container:

```
./analysis/run.sh data-codec            # censimento, pagina di codici, sonda nell'ambiente dell'oracle -> analysis/data-codec/out/
./analysis/run.sh data-codec --check    # rigenera in una cartella temporanea, confronta, verifica, prove negative
```

| Percorso | Contenuto | Come nasce |
| --- | --- | --- |
| `analysis/data-codec/glue/codec.py` | la colla: decodifica, ricodifica conservativa, codifica di un valore nuovo, nei due profili | scritta a mano |
| `analysis/data-codec/vettori/oracle-gnucobol.tsv`, `zos-ebcdic.tsv` | vettori di prova: byte → validità, valore, byte di scrittura; valore → byte | scritti a mano, prima delle sonde |
| `analysis/data-codec/vettori/oracle-oltre-picture.tsv` | ciò che GnuCOBOL fa con i binari oltre la `PICTURE` (osservazioni dichiarate) | trascritto dalla sonda, poi verificato a ogni controllo |
| `analysis/data-codec/sonde/CODECPRB.cbl` | sonda COBOL del profilo `oracle-gnucobol` (`ADDPRB.cbl`: programma per ispezionare a mano il C generato, non eseguito dai controlli) | scritta a mano |
| `analysis/data-codec/out/censimento*.tsv` | censimento delle rappresentazioni | `glue/censimento.py` dai contratti |
| `analysis/data-codec/out/pagina*.tsv` | byte che distinguono 037 da 1047 nei file EBCDIC | `glue/pagina.py` |
| `analysis/data-codec/out/sonde/` | compilazione, rapporto, ambiente e osservazioni della sonda | `oracle/build/compile.sh` e `oracle/esegui.sh` |

## Censimento delle rappresentazioni

Ricavato da `glue/censimento.py` leggendo ogni riga `elementare` dei contratti (gli `OCCURS` sono già espansi da #3: un elemento, una riga). La categoria dipende da `USAGE` e `PICTURE`; la **variante** è la `PICTURE` normalizzata (`X(n)`, `9(i)`, `S9(i)V9(d)`), cioè ciò da cui la regola ricava lunghezza, scala, segno e limiti. Una combinazione senza categoria fa fallire il censimento. Per ogni campo la lunghezza che la regola ricava dalla variante deve coincidere con quella del contratto: coincide per tutti i 329.

| Categoria | Campi | Con segno | Senza segno | Varianti | Lunghezze (byte) |
| --- | --- | --- | --- | --- | --- |
| alfanumerico (`PIC X`, `DISPLAY`) | 239 | 0 | 239 | 44 | da 1 a 500 |
| display-senza-segno (`PIC 9`, `DISPLAY`) | 50 | 0 | 50 | 7 | 1, 3, 4, 7, 9, 11, 16 |
| display-con-segno (`PIC S9…V99`, `DISPLAY`, segno incorporato nell'ultima cifra) | 23 | 23 | 0 | 3 | 6, 11, 12 |
| comp-3 (`PACKED-DECIMAL`) | 10 | 9 | 1 | 3 | 2, 6, 7 |
| comp (`BINARY`) | 7 | 1 | 6 | 4 | 2, 4, 8 |

Nessun campo dei contratti usa `SIGN SEPARATE`, `SYNCHRONIZED`, `JUSTIFIED` o `BLANK WHEN ZERO` (ricerca nei sorgenti di `app/cpy` e `app/cbl`): queste clausole non hanno regole qui.

### Varianti del censimento

Ogni variante ha una regola (sezione della sua categoria) e vettori in entrambi i profili; il controllo fallisce se una variante del censimento manca da questa tabella o dai vettori.

| Categoria | Variante | Byte | Campi |
| --- | --- | --- | --- |
| alfanumerico | `X(1)` | 1 | 19 |
| alfanumerico | `X(2)` | 2 | 16 |
| alfanumerico | `X(3)` | 3 | 3 |
| alfanumerico | `X(4)` | 4 | 6 |
| alfanumerico | `X(5)` | 5 | 1 |
| alfanumerico | `X(7)` | 7 | 2 |
| alfanumerico | `X(8)` | 8 | 6 |
| alfanumerico | `X(9)` | 9 | 1 |
| alfanumerico | `X(10)` | 10 | 38 |
| alfanumerico | `X(14)` | 14 | 2 |
| alfanumerico | `X(15)` | 15 | 7 |
| alfanumerico | `X(16)` | 16 | 27 |
| alfanumerico | `X(20)` | 20 | 9 |
| alfanumerico | `X(22)` | 22 | 1 |
| alfanumerico | `X(23)` | 23 | 1 |
| alfanumerico | `X(25)` | 25 | 12 |
| alfanumerico | `X(26)` | 26 | 13 |
| alfanumerico | `X(28)` | 28 | 1 |
| alfanumerico | `X(33)` | 33 | 2 |
| alfanumerico | `X(34)` | 34 | 6 |
| alfanumerico | `X(43)` | 43 | 1 |
| alfanumerico | `X(50)` | 50 | 22 |
| alfanumerico | `X(54)` | 54 | 1 |
| alfanumerico | `X(58)` | 58 | 1 |
| alfanumerico | `X(59)` | 59 | 1 |
| alfanumerico | `X(76)` | 76 | 1 |
| alfanumerico | `X(80)` | 80 | 4 |
| alfanumerico | `X(100)` | 100 | 4 |
| alfanumerico | `X(132)` | 132 | 1 |
| alfanumerico | `X(134)` | 134 | 3 |
| alfanumerico | `X(140)` | 140 | 1 |
| alfanumerico | `X(168)` | 168 | 2 |
| alfanumerico | `X(178)` | 178 | 1 |
| alfanumerico | `X(289)` | 289 | 5 |
| alfanumerico | `X(304)` | 304 | 1 |
| alfanumerico | `X(318)` | 318 | 1 |
| alfanumerico | `X(334)` | 334 | 5 |
| alfanumerico | `X(350)` | 350 | 2 |
| alfanumerico | `X(352)` | 352 | 1 |
| alfanumerico | `X(373)` | 373 | 1 |
| alfanumerico | `X(427)` | 427 | 1 |
| alfanumerico | `X(460)` | 460 | 1 |
| alfanumerico | `X(491)` | 491 | 3 |
| alfanumerico | `X(500)` | 500 | 2 |
| display-senza-segno | `9(1)` | 1 | 1 |
| display-senza-segno | `9(3)` | 3 | 3 |
| display-senza-segno | `9(4)` | 4 | 12 |
| display-senza-segno | `9(7)` | 7 | 1 |
| display-senza-segno | `9(9)` | 9 | 14 |
| display-senza-segno | `9(11)` | 11 | 18 |
| display-senza-segno | `9(16)` | 16 | 1 |
| display-con-segno | `S9(4)V9(2)` | 6 | 1 |
| display-con-segno | `S9(9)V9(2)` | 11 | 4 |
| display-con-segno | `S9(10)V9(2)` | 12 | 18 |
| comp-3 | `9(3)` | 2 | 1 |
| comp-3 | `S9(9)V9(2)` | 6 | 1 |
| comp-3 | `S9(10)V9(2)` | 7 | 8 |
| comp | `9(3)` | 2 | 1 |
| comp | `9(9)` | 4 | 3 |
| comp | `9(11)` | 8 | 2 |
| comp | `S9(10)V9(2)` | 8 | 1 |

## Due profili, mai mescolati

- **`oracle-gnucobol`**: i byte come li legge e scrive l'oracle di questo repository (GnuCOBOL 3.2, opzioni di `oracle/cobc.opts`: `-std=ibm -fbinary-truncate -fsingle-quote -fsign=EBCDIC`). Ogni regola è **osservata** dalla sonda `CODECPRB`, compilata con `oracle/build/compile.sh uno` (stessa immagine, stesse opzioni, stesso ambiente fissato con `env -i`) ed eseguita con `oracle/esegui.sh`. Gli script dell'oracle sono usati in sola lettura, attraverso le sue stesse funzioni (`oracle/lib.sh`, `orun`). Il controllo verifica anche che la sonda risulti compilata esattamente con le opzioni di `oracle/cobc.opts` e che abbia ricevuto solo le variabili dell'ambiente fissato.
- **`zos-ebcdic`**: i byte come sono su z/OS. Non è osservabile qui: ogni regola cita la documentazione IBM (sezione "Fonti"). Opzioni assunte: `NUMPROC(NOPFD)` e `TRUNC(STD)` (default del compilatore; il JCL di compilazione del legacy non le cambia), `NUMCLS(PRIM)` (default dell'opzione di installazione: l'installazione originale non è nota, è un'assunzione dichiarata).

I vettori di un profilo citano solo fonti di quel profilo (`GC-…` per l'oracle; `IBM-…`, `CP037`, `ICU-1047`, `ZOS-…` per z/OS): il controllo lo verifica.

## Tre cose distinte per ogni campo

1. **Validità della rappresentazione**: i byte sono una codifica ammessa del tipo. La stabilisce il controllo di classe `IS NUMERIC` dove si applica (`DISPLAY` numerico e `COMP-3`). Per i binari il controllo di classe non si applica: ogni sequenza di byte è un intero; si distingue invece se l'intero sta nella `PICTURE`. Per gli alfanumerici non esiste un dominio di valori non validi.
2. **Valore**: ciò che il COBOL ottiene usando il campo in un'operazione numerica. La sonda lo osserva due volte, con `MOVE` verso un campo largo e con `ADD` a un campo largo azzerato.
3. **Byte prodotti in scrittura**: ciò che un `MOVE` di un valore produce. La sonda scrive il valore ottenuto con `ADD` in un campo con la stessa `PICTURE`; per i vettori di codifica, `MOVE` del valore nuovo.

## Operazioni della colla

- **Decodifica** (`codec.decodifica`) restituisce lo stato (`valido`, `non-valido`, `oltre-picture`), il valore e **sempre** i byte originali. Nessun valore inventato: se lo stato non è `valido` il valore è assente. Nessuna normalizzazione in lettura, nessun record scartato. I valori numerici sono `Decimal` con la scala della `PICTURE`.
- **Campo incompleto** (rilievo 2 del giro 1 della PR #47). Prima di qualsiasi conversione la decodifica verifica che il campo stia tutto nel record: offset intero e non negativo, `offset + lunghezza ≤ lunghezza del record`. Se non è così solleva `CampoIncompleto` (sottoclasse di `CodificaErrore`), senza stato e senza valore. Un record troncato, vuoto o un offset oltre la fine non diventano mai un numero, nemmeno zero. Il controllo lo prova, per ogni vettore di decodifica dei due profili, con cinque casi: record troncato di un byte, record vuoto, campo che scavalca la fine, offset oltre la fine, offset negativo.
- **Ricodifica conservativa** (`codec.ricodifica`) restituisce i byte originali tali e quali: uno zero negativo (`}` nell'oracle, zona `D` su z/OS, `D` in un packed) resta tale, una rappresentazione alternativa ammessa resta com'è. Il controllo lo verifica su ogni vettore di decodifica.
- **Codifica di un valore nuovo** (`codec.codifica`) produce la rappresentazione prescritta dal profilo. Rifiuta con un errore esplicito ciò che non è rappresentabile: valore oltre la `PICTURE`, decimali oltre la scala, negativo in un campo senza segno, testo più lungo del campo, carattere fuori dalla pagina di codici. Non tronca e non arrotonda in silenzio. Il troncamento che farebbe un `MOVE` COBOL è registrato a parte nei vettori (colonna `move`) e osservato dalla sonda: è un comportamento del COBOL, non una regola della colla.

**Valori numerici non validi** (voce 20 del registro): la decodifica conserva i byte, marca il campo `non-valido` e non gli assegna alcun valore; non converte in zero, non scarta il record.

**Validità della rappresentazione e risultato di un'operazione sono due cose diverse.** Lo stato dice soltanto se i byte sono una codifica ammessa del tipo, come stabilisce il controllo di classe o la regola documentata. Che cosa ottenga un'operazione COBOL su un dato non valido è un'altra domanda. Nell'oracle è osservato e registrato a parte (sezione "Comportamento osservato di GnuCOBOL su dati non validi"); su z/OS non è documentato. Che il risultato di un'operazione sia incerto non rende "non determinata" la validità.

## Alfanumerico (`PIC X(n)`)

| | `oracle-gnucobol` | `zos-ebcdic` |
| --- | --- | --- |
| Lunghezza | n byte | n byte |
| Validità | ogni byte | ogni byte |
| Valore | i byte stessi; come testo, ogni byte è il carattere con lo stesso codice (ISO-8859-1, identità sui byte: decisione dichiarata, `GC-ALFA-BYTE`) | testo nella pagina di codici 037 (`CP037`) |
| Scrittura | allineato a sinistra, riempito a destra con X'20' (`GC-SRC-ALFA`) | allineato a sinistra, riempito con X'40' (`IBM-PG64-MOVE`) |
| Testo più lungo del campo | la colla rifiuta; il `MOVE` tronca a destra (osservato) | la colla rifiuta; il `MOVE` tronca a destra (`IBM-PG64-MOVE`) |
| Carattere non rappresentabile | errore esplicito (oltre U+00FF) | errore esplicito (fuori da 037), nessuna sostituzione |

La sonda osserva l'alfanumerico con un riferimento a sottostringa di un campo `X(500)` lungo n (`MOVE` verso `G-ALFA(1:n)`), che ha la semantica di un campo `X(n)`. Il valore vuoto non ha un letterale COBOL: la sonda lo scrive con `MOVE SPACES`, che è ciò che un valore più corto lascia nel campo.

## DISPLAY senza segno (`PIC 9(n)`)

| | `oracle-gnucobol` | `zos-ebcdic` |
| --- | --- | --- |
| Lunghezza, scala | n byte, nessun decimale (tutte le varianti del censimento hanno scala 0) | uguale (`IBM-PG62-FORMATI`) |
| Validità (`IS NUMERIC`) | ogni byte X'30'-X'39'; spazi, X'00', lettere e caratteri della tabella del segno sono non validi (`GC-SRC-NUMDISP`) | ogni byte con zona F e cifra 0-9; zona C o D non ammessa in un campo senza segno (`IBM-PG62-CLASSE`) |
| Valore | le cifre | le cifre |
| Scrittura | cifre ASCII, zeri a sinistra | zona F, zeri a sinistra (`IBM-PG63-NUMPROC`) |

## DISPLAY con segno (`PIC S9(i)V9(d)`, segno nell'ultima cifra)

Lunghezza i+d byte, punto decimale implicito prima delle ultime d cifre. Il segno sta nell'ultimo byte.

### Tabella completa byte → (cifra, segno)

| Cifra | `oracle-gnucobol` positivo | negativo | `zos-ebcdic` positivo | negativo |
| --- | --- | --- | --- | --- |
| 0 | `{` X'7B' | `}` X'7D' | X'C0' | X'D0' |
| 1 | `A` X'41' | `J` X'4A' | X'C1' | X'D1' |
| 2 | `B` X'42' | `K` X'4B' | X'C2' | X'D2' |
| 3 | `C` X'43' | `L` X'4C' | X'C3' | X'D3' |
| 4 | `D` X'44' | `M` X'4D' | X'C4' | X'D4' |
| 5 | `E` X'45' | `N` X'4E' | X'C5' | X'D5' |
| 6 | `F` X'46' | `O` X'4F' | X'C6' | X'D6' |
| 7 | `G` X'47' | `P` X'50' | X'C7' | X'D7' |
| 8 | `H` X'48' | `Q` X'51' | X'C8' | X'D8' |
| 9 | `I` X'49' | `R` X'52' | X'C9' | X'D9' |

Fonti: oracle `GC-README-SEGNO` (convenzione EBCDIC di `-fsign=EBCDIC`) e `GC-SRC-SEGNO`; z/OS `IBM-PG63-NUMPROC` (zona C positivo o zero, D negativo).

Oltre alle 20 righe della tabella, l'ultimo byte ammette altre 10 forme, positive. Le **30 forme ammesse** per variante e profilo sono quindi:

| Cifra | `oracle-gnucobol`: cifra semplice | `zos-ebcdic`: zona F |
| --- | --- | --- |
| 0 … 9 | X'30' … X'39' (`GC-SRC-NUMDISP`) | X'F0' … X'F9' (`IBM-PG62-CLASSE`, con `NUMPROC(NOPFD)` e `NUMCLS(PRIM)`) |

Ogni forma ammessa ha un vettore in ognuna delle tre varianti con segno, nei due profili (180 righe). In scrittura le forme alternative diventano la riga positiva della tabella. Ogni altro valore dell'ultimo byte è non valido. Oltre ai vettori, il controllo prova sulla colla i 256 valori dell'ultimo byte e del primo byte del corpo, per ogni variante `DISPLAY` nei due profili, contro la regola riscritta a mano in `verifica.py` (casi esaustivi, `comune.casi_esaustivi`). Nel profilo dell'oracle la sonda esegue gli stessi casi per l'ultimo byte delle tre varianti con segno e per il primo byte del corpo di `9(4)` e `S9(4)V9(2)`: 1280 osservazioni confrontate con la stessa regola.

| | `oracle-gnucobol` | `zos-ebcdic` |
| --- | --- | --- |
| Rappresentazione alternativa ammessa | ultimo byte cifra semplice X'30'-X'39': valida, positiva (`GC-SRC-NUMDISP`) | zona F nell'ultimo byte: valida, positiva con `NUMPROC(NOPFD)` (`IBM-PG62-CLASSE`) |
| Fuori tabella (non valido) | ogni altro ultimo byte, compresi `p`-`y` della convenzione ASCII, spazio, `-`, `S`, `Z` | zone A, B, E (non ammesse con `NUMCLS(PRIM)`), cifra A-F, spazio |
| Corpo (tutti i byte tranne l'ultimo) | X'30'-X'39', altrimenti non valido | zona F e cifra 0-9, altrimenti non valido |
| Scrittura | ultimo byte dalla tabella: `{`…`I` se positivo o zero, `}`…`R` se negativo | zona C se positivo o zero, D se negativo; corpo con zona F |
| Zero negativo in lettura | `}` vale 0; la ricodifica conservativa lo conserva; il valore nuovo 0 si scrive `{` | X'D0' vale 0; si conserva; il valore nuovo 0 si scrive X'C0' |

## COMP-3 (packed decimal)

Due cifre per byte; l'ultimo semiottetto è il codice del segno. Lunghezza (i+d)/2+1 byte (divisione intera). Con un numero pari di cifre (`S9(10)V9(2)`, 12 cifre in 7 byte) il primo semiottetto è di riempimento.

| | `oracle-gnucobol` | `zos-ebcdic` |
| --- | --- | --- |
| Codici accettati, campo con segno | C (+), D (−), F (+) (`GC-SRC-PACKED`: `hostsign` di `-std=ibm`) | C (+), D (−), F (+) (`IBM-PG62-CLASSE`, `NUMPROC(NOPFD)` e `NUMCLS(PRIM)`) |
| Codici accettati, campo senza segno | solo F | solo F |
| Codici non ammessi | 0-9, A, B, E (con segno); 0-9, A-E (senza segno) | uguale |
| Semiottetti di cifra | 0-9; A-F non validi | uguale |
| Semiottetto di riempimento 1-9 | valido, ignorato nel valore (`GC-SRC-PACKED`) | **non valido**: i quattro bit iniziali di un packed a precisione pari devono essere 0 (`IBM-APAR-PI96135`); nessun valore |
| Semiottetto di riempimento A-F | non valido | non valido |
| Scrittura | C positivo o zero, D negativo, F senza segno; riempimento 0 | uguale (`IBM-PG63-NUMPROC`) |
| Zero negativo | `…0D` vale 0, si conserva; il valore nuovo 0 si scrive `…0C` | uguale |

## COMP (binario)

| | `oracle-gnucobol` | `zos-ebcdic` |
| --- | --- | --- |
| Ampiezza | 1-4 cifre 2 byte, 5-9 cifre 4 byte, 10-18 cifre 8 byte (`binary-size 2-4-8`, `GC-README-BINARI`) | uguale (`IBM-PG62-FORMATI`) |
| Ordine dei byte | big-endian (`binary-byteorder big-endian`, `GC-README-BINARI`) | big-endian (`ZOS-ARCH`) |
| Segno | campo con segno: complemento a due; senza segno: intero senza segno | uguale |
| Validità | il controllo di classe non si applica; un intero fuori dalla `PICTURE` è `oltre-picture` | uguale |
| Valore | intero / 10^d se dentro la `PICTURE` | uguale |
| Oltre la `PICTURE` | **nessun valore** (sotto) | **nessun valore**: `TRUNC(STD)` regola i campi riceventi, non il valore letto (`IBM-PG63-TRUNC`) |
| Scrittura | intero scalato, big-endian; il `MOVE` di un valore oltre la `PICTURE` tronca alle cifre della `PICTURE` (`-fbinary-truncate`, osservato) | uguale; troncamento del `MOVE` per `TRUNC(STD)` (`IBM-PG63-TRUNC`) |

La capienza fisica (per esempio 65535 in `9(3) COMP`, due byte) e il limite della `PICTURE` (999) sono due cose diverse. Un valore fisicamente rappresentabile ma oltre la `PICTURE` letto da un campo è il caso `oltre-picture`; il troncamento in assegnazione (che cosa produce un `MOVE` di 1000 in `9(3) COMP`) è un'altra cosa e sta nei vettori di codifica, colonna `move`.

### Binari oltre la PICTURE: previsione, osservazione, decisione

- **Previsione iniziale.** Gli attesi del profilo `oracle-gnucobol` erano stati scritti prima di eseguire qualsiasi sonda, nel commit `aa22593`. Per i 10 casi `oltre-picture` prevedevano il valore intero, uguale per ogni operazione. La previsione veniva dal sorgente di GnuCOBOL 3.2 (`libcob/numeric.c`, `cob_decimal_set_binary`; `libcob/move.c`, `cob_move_binary_to_display`).
- **Osservazione.** La prima esecuzione della sonda l'ha smentita in un caso su dieci: `9(9) COMP` con byte `FF FF FF FF` vale 4294967295 con `MOVE` ma **-1** con `ADD`. Riscrivere il valore di `ADD` nello stesso campo senza segno produce `00 00 00 01`. Negli altri nove casi `MOVE` e `ADD` danno lo stesso valore.
- **Causa, verificata sul C generato da cobc** (verifica manuale, non automatizzata nel controllo). Per `ADD F TO W` con `F PIC 9(9) COMP`, cobc genera `cob_add_int (&f_18, ((unsigned int)COB_BSWAP_32(*(int *)(b_17))), 0);`. `cob_add_int` riceve un `const int` (GnuCOBOL 3.2, `libcob/common.h` e `libcob/numeric.c`), quindi il valore senza segno 4294967295 diventa -1 nella conversione. Il `MOVE` passa invece per `cob_move_binary_to_display`, che legge l'intero senza segno a 64 bit. Comando per rifare la verifica, nell'immagine dell'oracle, su un programma di prova con quei due campi e quell'`ADD`: `env -i PATH=/usr/bin:/bin HOME=/tmp LC_ALL=C cobc -std=ibm -fbinary-truncate -fsingle-quote -fsign=EBCDIC -C -o ADDPRB.c ADDPRB.cbl`. Sono le opzioni di `oracle/cobc.opts` senza `-Wall` e `-I`, che non cambiano il codice generato. Il programma è `analysis/data-codec/sonde/ADDPRB.cbl`.
- **Decisione** (voce 63 del registro delle approvazioni): in entrambi i profili la colla non assegna un valore a un binario oltre la `PICTURE`; conserva i byte e marca il campo `oltre-picture`. Ciò che fa l'oracle è dichiarato per operazione in `vettori/oracle-oltre-picture.tsv` ed è verificato dalla sonda a ogni controllo. I 10 attesi sono cambiati apertamente nel commit `11ba1dd`.

| Variante | Byte | `MOVE` | `ADD` | Riscrittura (valore di `ADD`, stessa `PICTURE`) |
| --- | --- | --- | --- | --- |
| `9(3)` | `03 E8` | 1000 | 1000 | `00 00` |
| `9(3)` | `FF FF` | 65535 | 65535 | `02 17` |
| `9(9)` | `3B 9A CA 00` | 1000000000 | 1000000000 | `00 00 00 00` |
| `9(9)` | `FF FF FF FF` | 4294967295 | **-1** | `00 00 00 01` |
| `9(11)` | `00 00 00 17 48 76 E8 00` | 100000000000 | 100000000000 | `00 × 8` |
| `9(11)` | `FF × 8` | 18446744073709551615 | 18446744073709551615 | `00 00 00 11 29 6E 7F FF` |
| `S9(10)V9(2)` | `00 00 00 E8 D4 A5 10 00` | 10000000000.00 | 10000000000.00 | `00 × 8` |
| `S9(10)V9(2)` | `FF FF FF 17 2B 5A F0 00` | -10000000000.00 | -10000000000.00 | `00 × 8` |
| `S9(10)V9(2)` | `7F FF FF FF FF FF FF FF` | 92233720368547758.07 | 92233720368547758.07 | `00 00 00 08 94 B7 3F FF` |
| `S9(10)V9(2)` | `80 00 00 00 00 00 00 00` | -92233720368547758.08 | -92233720368547758.08 | `FF FF FF F7 6B 48 C0 00` |

Le riscritture sono il troncamento alle cifre della `PICTURE` (per esempio 65535 → 535, 9223372036854775807 → 36854775807 in centesimi).

## Pagina di codici del profilo z/OS

Le pagine candidate sono 037 e 1047. Confrontate byte per byte (tabella 037 del codec `cp037` di Python; tabella 1047 di ICU, `ibm-1047_P100-1995.ucm`), differiscono in sei byte:

| Byte | 037 | 1047 |
| --- | --- | --- |
| X'5F' | ¬ | ^ |
| X'AD' | Ý | [ |
| X'B0' | ^ | ¬ |
| X'BA' | [ | Ý |
| X'BB' | ] | ¨ |
| X'BD' | ¨ | ] |

`glue/pagina.py` cerca questi byte in ogni file di `app/data/EBCDIC/` e colloca ogni occorrenza nel campo del tracciato che la contiene, senza decodificare valori. Risultato (`out/pagina.tsv`, `out/pagina-esito.tsv`): 17 occorrenze, tutte in `AWS.M2.CARDDEMO.EXPORT.DATA.PS`. Sono 4 in `EXP-CUST-FICO-CREDIT-SCORE` (`COMP-3`), 12 in `EXPORT-SEQUENCE-NUM` (`COMP`) e 1 in `EXP-CARD-CVV-CD` (`COMP`); nessuna in un campo alfanumerico. Gli altri 12 file non ne contengono. L'area di `EXPORT-RECORD` si sceglie dal tipo di record (byte 0), secondo `app/cbl/CBEXPORT.cbl` (righe 274, 343, 407, 462, 527, verificate dallo script).

Conclusione: `037-convenzione`. I dati non distinguono le due pagine; si adotta 037 come **convenzione**, non come fatto verificato. Il controllo fallisce se un'occorrenza cade in un campo alfanumerico: in quel caso la pagina andrebbe scelta sui dati.

## Vettori di prova

I vettori sono scritti a mano, un file per profilo, una riga per caso. In decodifica: byte → stato, valore, byte di scrittura del valore. In codifica: valore → byte della colla (o errore) e byte del `MOVE` COBOL. Il formato è descritto in testa a ogni file. Totali: 375 righe `oracle-gnucobol` e 366 `zos-ebcdic`. Nella prima versione erano 267 e 257, poi una riga z/OS è stata aggiunta (`9(4)`, quattro spazi); le altre righe sono state aggiunte nel giro di correzione 1 della PR #47 e sono marcate in coda ai file. Il criterio della copertura è **tutte le righe di ogni regola**, non un rappresentante per famiglia. Il controllo elenca ogni riga mancante, per ogni profilo:

- ogni variante del censimento ha almeno un vettore di decodifica;
- `DISPLAY` con segno, per ogni variante: le 30 forme ammesse dell'ultimo byte (20 della tabella e 10 alternative), almeno un byte fuori tabella, lo zero negativo, le cifre 0-9 nel corpo. Gli altri valori dell'ultimo byte sono provati dai casi esaustivi;
- `DISPLAY` senza segno, per ogni variante: le cifre 0-9, un campo di spazi, un carattere non numerico. Gli altri valori del primo byte sono provati dai casi esaustivi;
- `COMP-3`, per ogni variante: i 16 codici di segno (accettati validi, gli altri non validi), le cifre 0-9 e i semiottetti A-F nelle posizioni di cifra; per la precisione pari, i 16 valori del semiottetto di riempimento;
- binario, per ogni variante: zero, estremi della `PICTURE`, estremi fisici (positivi e negativi se con segno), almeno un caso oltre la `PICTURE`;
- alfanumerico: tutti i 256 byte in un vettore di decodifica; riempimento a destra; campo pieno; testo o carattere non rappresentabile; nel profilo z/OS ciascuno dei sei byte che distinguono 037 da 1047. Il vettore z/OS dei 256 byte ha il valore trascritto da ICU, una fonte indipendente dal codec;
- per categoria: almeno una codifica riuscita e, per i numerici, almeno una rifiutata.

Casi `non-determinato` (rilievo 3 del giro 1). La prima versione ne aveva uno solo: il semiottetto di riempimento `1` di un packed z/OS a precisione pari, con fonte `ZOS-NONDOC`. Ora è `non-valido`, con fonte `IBM-APAR-PI96135`. Non resta alcun caso non determinato, e lo stato `non-determinato` e la fonte `ZOS-NONDOC` sono stati tolti. Restano tre vettori di codifica z/OS con colonna `move` vuota, perché la documentazione consultata non dà il troncamento delle cifre alte in un `MOVE` verso un `DISPLAY` o un `COMP-3`. Manca la pagina "Alignment rules" del Language Reference, che non sono riuscito a leggere. Sono `12345` in `9(4)`, `12345678901.00` in `S9(10)V9(2)` e `1000` in `COMP-3 9(3)`. Non sono stati di validità: la colla rifiuta comunque quei valori.

La colla si verifica decodificando il campo **dentro un record**, con otto byte di guardia prima e dopo: una lunghezza sbagliata include un byte di guardia o ne perde uno del campo, e cambia valore o stato invece di essere rifiutata per struttura.

## Ordine di lavoro e scostamenti dalla previsione

1. Commit `aa22593`: vettori dei due profili, scritti prima di eseguire qualsiasi sonda.
2. Prima esecuzione della sonda. Due difetti della sonda stessa, non degli attesi, corretti prima del confronto: il `MOVE` del gruppo `IN-VALORE` al posto del campo numerico `IN-VALORE-N` produceva byte senza senso nei vettori di codifica; la riga di uscita di 2200 caratteri troncava i campi da 373 byte in su.
3. Confronto di 267 righe: una sola differenza, il caso `9(9) COMP` `FF FF FF FF` descritto sopra. Esecutore fermato, decisione dell'Approvatore (voce 63), attesi cambiati nel commit `11ba1dd`.

## Comportamento osservato di GnuCOBOL su dati non validi (informativo)

La sonda registra, anche per i vettori non validi, il valore che GnuCOBOL calcola e i byte del campo dopo l'uso (`out/sonde/osservazioni.tsv`, colonne `valore_move`, `valore_add`, `dopo`). Non sono regole della colla, che non assegna valori ai non validi. Sono fissati dal confronto con l'output versionato, quindi un cambiamento si vede. Fatti utili per la parità (#5 e successive):

- con `ADD` un campo non valido produce comunque un numero. Ogni byte vale il suo semiottetto basso: per esempio `31 41 33` in `9(3)` vale 113 e gli spazi valgono 0. Con `MOVE` verso un `DISPLAY` i byte non validi sono copiati tali e quali (`+…1A3…`);
- un ultimo byte fuori tabella in un `DISPLAY` con segno viene **riscritto in memoria** quando il campo è usato. Per esempio `p` (X'70') diventa `{`, `S` diventa `C`, `y` diventa `I`; lo spazio resta spazio. Per i campi validi i byte non cambiano;
- un packed con codice B o E è trattato come positivo, con D come negativo (anche in un campo senza segno, dove D non è ammesso).

## Strumenti

Nessuna libreria di decodifica adottata: la colla è scritta in Python (standard library, `decimal`, codec `cp037`) nell'immagine Python delle analisi. JRecord resta tra gli strumenti non provati: le regole qui sono poche e piccole, e il punto era verificarle contro l'oracle, non delegarle.

## Fonti

| Chiave | Fonte |
| --- | --- |
| `GC-README-SEGNO` | `oracle/README.md`, sezione "Segno dei numeri DISPLAY", e `oracle/cobc.opts` (`-fsign=EBCDIC`): tabella `{` `A`-`I` / `}` `J`-`R` ed esempi di scrittura |
| `GC-README-BINARI` | `oracle/README.md`, tabella "Differenze note", righe sui binari (`binary-size 2-4-8`, `binary-byteorder big-endian`, `-fbinary-truncate`) |
| `GC-SRC-NUMDISP` | GnuCOBOL 3.2, `libcob/common.c`, `cob_check_numdisp` (controllo di classe dei `DISPLAY`) e `libcob/numeric.c`, `cob_decimal_set_display` |
| `GC-SRC-SEGNO` | GnuCOBOL 3.2, `libcob/common.c`, `cob_get_sign_ebcdic` e `cob_put_sign_ebcdic` |
| `GC-SRC-PACKED` | GnuCOBOL 3.2, `libcob/common.c`, `cob_is_numeric` (caso packed, `flag_host_sign`); `libcob/numeric.c`, `cob_decimal_set_packed`, `cob_set_packed_u64`, `cob_set_packed_zero`; `libcob/move.c`, `cob_move_display_to_packed` |
| `GC-SRC-BINARY` | GnuCOBOL 3.2, `libcob/numeric.c`, `cob_decimal_set_binary`, `cob_decimal_get_binary`; `libcob/move.c`, `cob_move_binary_to_display`, `cob_move_display_to_binary` |
| `GC-SRC-ALFA` | GnuCOBOL 3.2, `libcob/move.c`, `cob_move_alphanum_to_alphanum` (riempimento con spazi, troncamento a destra) |
| `GC-ALFA-BYTE` | decisione di questa issue: nel profilo dell'oracle un alfanumerico è la sua sequenza di byte, presentata come testo ISO-8859-1 (corrispondenza uno a uno) |
| `IBM-PG62-CLASSE` | IBM Enterprise COBOL for z/OS 6.2, Programming Guide, "Checking for incompatible data (numeric class test)": tabelle dei segni validi per `NUMPROC`/`NUMCLS` (con segno C, D, F con `NOPFD`/`PRIM`; senza segno solo F) e zone non valide nei `DISPLAY` |
| `IBM-PG63-NUMPROC` | IBM Enterprise COBOL for z/OS 6.3, Programming Guide, "NUMPROC": default `NOPFD`; segni preferiti (zoned con segno C positivo o zero, D negativo; senza segno F; packed C/D/F) |
| `IBM-PG62-FORMATI` | IBM Enterprise COBOL for z/OS 6.2, Programming Guide, "Formats for numeric data": `BINARY` di 2, 4, 8 byte per 1-4, 5-9, 10-18 cifre; packed un byte ogni due cifre; zoned una cifra per byte |
| `IBM-PG63-TRUNC` | IBM Enterprise COBOL for z/OS 6.3, Programming Guide, "TRUNC": `TRUNC(STD)` tronca alle cifre della `PICTURE` del campo binario **ricevente** (esempio 1234567891 → 567891); nulla sul valore di un campo mittente oltre la `PICTURE` |
| `IBM-PG64-MOVE` | IBM Enterprise COBOL for z/OS 6.4, Programming Guide, "Assigning values to elementary data items (MOVE)": troncamento a destra e riempimento con spazi degli alfanumerici; esempio 3.06 → 3.0 in `PIC 999V9` |
| `CP037` | pagina di codici IBM 037, tabella del codec `cp037` della libreria standard di Python 3.12 (dalla tabella di mappatura Unicode di CP037) |
| `ICU-1047` | pagina di codici IBM 1047, ICU `ibm-1047_P100-1995.ucm` (repository unicode-org/icu-data), usata solo per trovare i sei byte che la distinguono da 037 |
| `ZOS-ARCH` | IBM z/Architecture Principles of Operation (SA22-7832): interi binari big-endian, con segno in complemento a due. Citata e non riletta in questa issue; "Formats for numeric data" conferma che il bit più a sinistra porta il segno |
| `IBM-APAR-PI96135` | IBM APAR PI96135, Enterprise COBOL for z/OS 6.2, `NUMCHECK(PAC)`: un `PACKED-DECIMAL` di lunghezza pari "must contain 0s in the leftmost four bits to be considered a valid PACKED-DECIMAL data item" |
| `IBM-LR64-MOVE` | IBM Enterprise COBOL for z/OS 6.4, Language Reference, "Elementary move rules": se il ricevente numerico è senza segno, nel `MOVE` si usa il valore assoluto del mittente |
| `ICU-037` | pagina di codici IBM 037, ICU `ibm-37_P100-1995.ucm` (repository unicode-org/icu, `icu4c/source/data/mappings`, SHA-256 `e9ad7c15…d8ba`). Da qui è trascritto il valore atteso del vettore z/OS con tutti i 256 byte: è una tabella indipendente dal codec `cp037` di Python, e coincide con quella byte per byte |

Il sorgente di GnuCOBOL citato è il tarball `gnucobol-3.2.tar.xz` di ftp.gnu.org (SHA-256 `3bb48af46ced4779facf41fdc2ee60e4ccb86eaa99d010b36685315df39c2ee2`), letto fuori dal repository. L'immagine dell'oracle usa il pacchetto Debian `3.2-3`, che può avere patch: il riferimento per il profilo `oracle-gnucobol` resta la sonda, non il sorgente.

## Limiti

- Il profilo `zos-ebcdic` non è osservato: è documentazione. Le opzioni `NUMCLS(PRIM)` e la pagina 037 sono assunzioni dichiarate.
- La sonda osserva il valore con `MOVE` e con `ADD`. Altri usi (`COMPUTE` con espressioni, confronti, `DISPLAY`) non sono coperti; per i binari oltre la `PICTURE` la differenza fra operazioni è appunto il motivo per cui la colla non assegna valori.
- La causa della differenza `MOVE`/`ADD` per `9(9) COMP` `FF FF FF FF` è stata verificata a mano sul C generato (`sonde/ADDPRB.cbl`): nessun controllo automatico la ripete.
- I comandi della colla Python e `docker build` non hanno un limite di tempo proprio; compilazione (900 s) ed esecuzione della sonda (60 s per il programma, 180 s per lo script) sì.
