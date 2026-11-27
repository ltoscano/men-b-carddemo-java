# MVSWAIT: casi ricavati dal sorgente

Equivalente dell'oracle (`oracle/stubs/MVSWAIT.cbl`) della routine assembler `app/asm/MVSWAIT.asm`, chiamata da `app/cbl/COBSWAIT.cbl` (job `app/jcl/WAITSTEP.jcl`). La tabella si ricava dalle istruzioni dell'assembler, dalla macro `app/maclib/ASMWAIT.mac` e dalla documentazione IBM del servizio `STIMER`. La stessa tabella, in forma leggibile da macchina, è in `mvswait-casi.tsv`; i casi di prova sono in `mvswait-prove.tsv`, gli attesi scritti a mano in `mvswait-attesi/`. `mvswait-coerenza.sh` verifica che la tabella copra ogni valore dell'argomento una e una sola volta e che gli attesi siano quelli che la tabella prescrive.

Questo file, la tabella, i casi e gli attesi sono stati scritti e committati **prima** di eseguire la routine (issue #36). Gli ingressi di `COBSWAIT` che il sorgente non determina sono in un file separato, `mvswait-osservazioni.md`: lì ciò che si registra è un'osservazione di GnuCOBOL, non un atteso.

## Che cosa fa l'originale

### `MVSWAIT.asm`, istruzione per istruzione

| Riga | Istruzione | Effetto |
| --- | --- | --- |
| 17-18 | `START 0`, `USING *,15` | indirizzamento sul registro 15 (indirizzo d'ingresso) |
| 19 | `STM 14,12,12(13)` | salva i registri 14-12 nell'area di salvataggio del chiamante |
| 20 | `L 5,0(1)` | R5 = indirizzo del primo argomento (prima parola della lista dei parametri) |
| 21 | `L 1,0(5)` | R1 = i **4 byte** all'indirizzo dell'argomento: un intero binario di 32 bit, letto per riferimento |
| 22 | `ST 1,BINLBL` | copia il valore nell'area propria `BINLBL` (riga 28, `DS F`: una parola) |
| 23 | `ASMWAIT BINLBL` | la macro si espande in `STIMER WAIT,BINTVL=BINLBL` (`ASMWAIT.mac` righe 17-20): attesa sincrona dell'intervallo binario contenuto in `BINLBL` |
| 24 | `LM 14,12,12(13)` | ripristina i registri |
| 25 | `MVI 12(13),X'FF'` | scrive `X'FF'` nel byte 12 dell'area di salvataggio del chiamante (il commento del sorgente stesso si chiede a che serva) |
| 26 | `SR 15,15` | R15 = 0: codice di ritorno 0 |
| 27 | `BR 14` | ritorno al chiamante |

La routine non valida l'argomento, non lo modifica (l'unica scrittura in memoria fuori dall'area di salvataggio è in `BINLBL`, area propria) e non scrive nulla a console. Ritorna 0 **se il servizio di attesa le restituisce il controllo**.

### Il servizio `STIMER` (documentazione IBM)

Fonte: IBM, *z/OS 2.4 MVS Programming: Assembler Services Reference, Volume 2 (IAR-XCT)*, SA23-1370-40 (ultimo aggiornamento 2021-06-24), capitolo 97 "STIMER — Set interval timer", pagine 915-920. La stessa pagina è pubblicata in HTML su IBM Documentation (`SSLTBW_2.4.0/com.ibm.zos.v2r4.ieaa900/stimer.htm`). Letta il 27 novembre 2026.

| Punto | Frase della documentazione (testo originale) | Sezione |
| --- | --- | --- |
| Unità e formato di `BINTVL` | "For BINTVL, the address is a 4-byte area containing the time interval. The time interval is represented as an unsigned 32-bit binary number; however, the high-order bit of the time interval must not be set. Therefore, the time interval specified cannot exceed X'7FFFFFFF'. The low-order bit of the time interval has a value of 0.01 second." | Parameters, `,BINTVL=stor addr` (p. 917) |
| Limite ed esito oltre il limite | "The time interval you specify on the BINTVL parameter must not exceed X'7FFFFFFF'. If the time interval exceeds X'7FFFFFFF', your program receives a X'12F' abend." | Restrictions (p. 916) |
| Codici di abend | "STIMER might abnormally terminate with one the following abend codes: X'12F' (with reason code X'0', X'4', X'C', X'10', X'14', X'28'), or X'AC7' (with reason code X'2')." | ABEND codes (p. 919) |
| `WAIT` | "For WAIT, the interval is decreased continuously. The task is to be placed in the wait condition until the interval expires." | Parameters, `WAIT` (p. 917) |
| Ritorno | "STIMER returns a return code of 0 in register 15." | Return and reason codes (p. 919) |
| Esempio | "Example 3: Request that this task be put into a wait state until 60 seconds have passed." con `STIMER WAIT,BINTVL=INTV2` e `INTV2 DC F'6000'` | Examples (p. 920) |

Conseguenze per la tabella:

- l'unità è il centesimo di secondo (il bit meno significativo vale 0,01 s; l'esempio IBM: 6000 = 60 secondi). Lo conferma il commento di `WAITSTEP.jcl` riga 20: `00003600  = 36 SECONDS`;
- un valore da `X'00000000'` a `X'7FFFFFFF'` è ammesso: il servizio attende e restituisce il controllo, la routine ritorna 0;
- un valore da `X'80000000'` a `X'FFFFFFFF'` ha il bit alto acceso, quindi "exceeds X'7FFFFFFF'": il programma riceve l'abend `X'12F'` e la routine **non ritorna**.

**Non verificato nella documentazione:**

- **intervallo zero.** Il capitolo 97 non contiene alcuna frase sull'intervallo zero (le sole occorrenze di "zero" sono il contenuto del registro 15 al ritorno); nemmeno la sezione "Interval timing" di *z/OS 2.4 MVS Programming: Assembler Services Guide*, SA23-1368-40, pp. 342-343. Ciò che la documentazione determina è solo che zero non supera `X'7FFFFFFF'`, quindi non ricade nell'abend del limite. Se `STIMER WAIT` con intervallo zero restituisca il controllo subito o dopo un tempo minimo non è scritto: per l'equivalente non cambia nulla, perché non attende comunque, e il caso zero è trattato come gli altri valori ammessi (ritorno 0). Va riletto se un giorno la parità dovesse riguardare la durata;
- **codice di motivo dell'abend.** Quale dei codici di motivo di `X'12F'` corrisponda al superamento del limite di `BINTVL` è spiegato in *z/OS MVS System Codes*, che non è stato consultato. L'oracle non lo riproduce in ogni caso.

### Il chiamante: `COBSWAIT.cbl` e `WAITSTEP.jcl`

| Riga | Sorgente | Effetto |
| --- | --- | --- |
| `COBSWAIT.cbl` 30 | `01 MVSWAIT-TIME PIC 9(8) COMP.` | intero binario senza segno; con `binary-size 2-4-8` (come su IBM) occupa 4 byte, ordine big-endian |
| `COBSWAIT.cbl` 31 | `01 PARM-VALUE PIC X(8).` | 8 caratteri |
| `COBSWAIT.cbl` 36 | `ACCEPT PARM-VALUE FROM SYSIN.` | legge i primi 8 caratteri della scheda di `SYSIN` |
| `COBSWAIT.cbl` 37 | `MOVE PARM-VALUE TO MVSWAIT-TIME.` | da alfanumerico a numerico binario |
| `COBSWAIT.cbl` 38 | `CALL 'MVSWAIT' USING MVSWAIT-TIME.` | passa i 4 byte per riferimento |
| `COBSWAIT.cbl` 40 | `STOP RUN.` | il codice di ritorno del passo è `RETURN-CODE`, cioè il R15 lasciato da `MVSWAIT` (0) |
| `WAITSTEP.jcl` 25-26 | `//SYSIN DD *` e la scheda `00003600      VALUE IN CENTISECONDS ...` | la scheda di 80 colonne; i primi 8 caratteri sono `00003600` |

Da `COBSWAIT` arrivano quindi solo valori da 0 a 99999999 (`X'05F5E0FF'`), tutti sotto il limite di `STIMER`: con una scheda di 8 cifre `WAITSTEP` non può produrre l'abend. I valori oltre la `PICTURE` e oltre il limite si provano chiamando la routine direttamente (programma di prova `WAITPRB`).

## L'equivalente

`oracle/stubs/MVSWAIT.cbl`:

- riceve per riferimento l'area di 4 byte (`PIC X(4)` nella `LINKAGE SECTION`) e calcola il valore come intero senza segno big-endian dai 4 byte, senza modificarli;
- **non attende** (primo adattamento dichiarato, temporale: l'oracle deve essere ripetibile e veloce);
- per un valore da `X'00000000'` a `X'7FFFFFFF'` scrive su **stderr** una sola riga e ritorna 0:
  `MENB-ORACLE MVSWAIT: ATTESA RICHIESTA <valore in 10 cifre> (X'<8 cifre esadecimali maiuscole>') CENTESIMI DI SECONDO, NON ESEGUITA`
- per un valore da `X'80000000'` a `X'FFFFFFFF'` scrive su stderr una sola riga e termina l'intera esecuzione con **codice 97**, come i casi non riproducibili di `COBDATFT` (voce 42 del registro): l'abend del servizio non è riprodotto e un arresto del legacy non diventa un successo:
  `MENB-ORACLE MVSWAIT: ATTESA RICHIESTA <valore in 10 cifre> (X'<8 cifre esadecimali maiuscole>') OLTRE X'7FFFFFFF': ABEND X'12F' DI STIMER NON RIPRODOTTO`
- su stdout non scrive nulla.

La riga su stderr è un **secondo adattamento dichiarato, di uscita**: l'originale non scrive nulla.

Che cosa è riferimento di parità per la migrazione Java:

| Elemento | Riferimento di parità? |
| --- | --- |
| il valore richiesto (in centesimi di secondo), che la migrazione deve passare identico al proprio meccanismo di attesa | **sì** |
| il codice di ritorno 0 per i valori ammessi | **sì** |
| l'argomento non modificato | **sì** |
| nessuna uscita su stdout | **sì** |
| l'arresto per un valore con il bit alto acceso (sul mainframe: abend `X'12F'`) | **sì**, come arresto; il codice 97 è dell'oracle |
| la riga di diagnostica su stderr | **no**: esiste solo per rendere osservabile il valore; il Java non la deve riprodurre. I rapporti dell'oracle la contengono e la confrontano esattamente perché è l'evidenza del valore |
| la durata dell'attesa | **no** nell'oracle (non attende); il Java attenderà davvero |

Non riprodotto: la scrittura di `X'FF'` nel byte 12 dell'area di salvataggio del chiamante (riga 25). In GnuCOBOL l'area di salvataggio dei registri non esiste come memoria osservabile dal programma COBOL: non ha un equivalente.

## Tabella dei casi

| Classe | Valore dell'argomento (4 byte, senza segno) | Esito dell'originale | Esito dell'equivalente | Righe |
| --- | --- | --- | --- | --- |
| V | da `X'00000000'` a `X'7FFFFFFF'` (0 … 2147483647) | attesa del valore × 0,01 s, poi ritorno con R15 = 0; argomento invariato | riga di diagnostica su stderr, nessuna attesa, codice di ritorno 0, argomento e byte adiacenti invariati | `MVSWAIT.asm` 20-27, `ASMWAIT.mac` 19, `STIMER` (BINTVL, Restrictions) |
| L | da `X'80000000'` a `X'FFFFFFFF'` (2147483648 … 4294967295) | abend `X'12F'` di `STIMER`: la routine non ritorna | riga dell'arresto su stderr, esecuzione terminata con codice 97 | `MVSWAIT.asm` 20-23, `ASMWAIT.mac` 19, `STIMER` (Restrictions, ABEND codes) |

## Casi di prova (`mvswait-prove.tsv`)

**Chiamata diretta** con `oracle/tests/WAITPRB.cbl`: il PARM sono 8 cifre esadecimali (i 4 byte dell'argomento). Il programma mette l'argomento tra due campi di 4 byte riempiti con `X'A5'`, stampa i 12 byte in esadecimale prima e dopo la `CALL` e il `RETURN-CODE` dopo la `CALL` (prima vale 55): così si vedono l'argomento invariato in tutti i 4 byte e i byte adiacenti invariati.

| Caso | Argomento | Decimale | Perché | Classe |
| --- | --- | --- | --- | --- |
| `D00000000` | `00000000` | 0 | zero (vedi "Non verificato") | V |
| `D00000001` | `00000001` | 1 | il minimo non nullo | V |
| `D00000E10` | `00000E10` | 3600 | il valore di `WAITSTEP` | V |
| `D05F5E0FF` | `05F5E0FF` | 99999999 | il massimo di `PIC 9(8)` | V |
| `D05F5E100` | `05F5E100` | 100000000 | oltre la `PICTURE`, sotto il limite | V |
| `D7FFFFFFF` | `7FFFFFFF` | 2147483647 | il limite di `BINTVL` | V |
| `D80000000` | `80000000` | 2147483648 | il primo valore oltre il limite | L |
| `DFFFFFFFF` | `FFFFFFFF` | 4294967295 | il massimo di 32 bit | L |

**Tramite `COBSWAIT`** con `SYSIN` (opzione `--sysin` di `oracle/esegui.sh`). Le schede si ricavano dal JCL a ogni esecuzione, con un comando, nel container (sorgente nel volume del legacy):

```
sed -n '26{s/\r$//;p}' /legacy/app/jcl/WAITSTEP.jcl                      # S1: la scheda così com'è
sed -n '26{s/\r$//;s/^00003600/12345678/;p}' /legacy/app/jcl/WAITSTEP.jcl  # S2: le prime 8 colonne sostituite
```

Il file del legacy ha righe terminate da CR LF: il CR è il terminatore di riga del file, non una colonna della scheda, e si toglie. Ogni scheda ha 80 colonne più il ritorno a capo: 81 byte.

| Caso | Scheda | Valore | Classe |
| --- | --- | --- | --- |
| `S1` | riga 26 di `WAITSTEP.jcl` | 3600 (`X'00000E10'`) | V |
| `S2` | la stessa con `12345678` nelle colonne 1-8 | 12345678 (`X'00BC614E'`) | V |

Atteso di ogni caso: `mvswait-attesi/<caso>.txt`, nel formato del rapporto di `esegui.sh`; per `S1` e `S2` con la sezione `== sysin` (byte e SHA-256 della scheda). Ambiente atteso: `mvswait-attesi/ambiente`.

## Limite operativo

Ogni esecuzione che chiama `MVSWAIT` (casi qui sopra e osservazioni, quindi anche ogni lancio di `COBSWAIT`) ha due limiti, applicati all'artefatto vero e non solo alle varianti delle prove negative:

- **durata misurata** attorno a `esegui.sh` nel container: al massimo **800 ms**, come minimo su fino a 3 tentativi (le esecuzioni sane misurano circa 15-140 ms; un picco di 561 ms, osservato con Docker appena riavviato, ha suggerito il secondo tentativo: un picco di carico sparisce, un'attesa vera non scende mai sotto la propria durata). Respinge anche un'attesa fissa di un secondo (prova negativa `unsecondo`, aggiunta dopo il giro 1 di validazione della PR #52, che aveva mostrato una routine con `sleep 1` passare il controllo);
- **arresto** dopo **3 secondi** (`ORACLE_TIMEOUT_RUN=3` passato a `esegui.sh`, che allo scadere termina il programma e fallisce con codice 3): una routine che attendesse davvero l'intervallo richiesto (36 secondi per `S1`) fallisce senza restare appesa.

La prova di avvio (`oracle/avvio/`) lancia `COBSWAIT` anche lei, con il limite generale di 60 s e senza misura di durata: un'attesa fissa vi passerebbe, ma lo stesso artefatto è respinto dal passo `routines`, che fa parte di `./oracle/run.sh --all --check`.

## Che cosa è specifico di CardDemo

Specifico: la routine, la scheda di `WAITSTEP` e il limite di `BINTVL`. Trasferibile: per una routine di sistema il cui effetto è il tempo, l'oracle rende osservabile il **valore** che il programma chiede al servizio (che è ciò che la migrazione deve preservare) e non riproduce l'effetto; i valori che il servizio rifiuta diventano un arresto, non un successo.
