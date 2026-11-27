# MVSWAIT: ingressi di COBSWAIT non determinati dal sorgente (osservazioni)

`COBSWAIT.cbl` legge 8 caratteri da `SYSIN` (`ACCEPT PARM-VALUE FROM SYSIN`, riga 36) e li sposta in un campo binario (`MOVE PARM-VALUE TO MVSWAIT-TIME`, riga 37; `PIC X(8)` verso `PIC 9(8) COMP`). Con una scheda di 8 cifre il valore è determinato (casi `S1` e `S2` di `mvswait-casi.md`). Non lo è per:

- `SYSIN` vuoto: che cosa lasci in `PARM-VALUE` un `ACCEPT` senza schede dipende dal runtime;
- meno di 8 caratteri e caratteri non numerici: il `MOVE` di un alfanumerico che non contiene un numero valido in un campo numerico non ha un risultato che si possa attribuire a z/OS leggendo il sorgente.

Per questi ingressi si **registra ciò che fa GnuCOBOL** (`mvswait-osservazioni.tsv`, rapporti osservati in `mvswait-osservati/`). Non sono attesi ricavati dal sorgente, nessun atteso "ricavato" li copre, e **non sono un riferimento per la migrazione**: il Java non deve imitarli. Il controllo del passo `routines` li confronta comunque esattamente, come registrazione dell'oracle: se cambiano, qualcosa è cambiato nell'oracle.

## Previsioni scritte prima di eseguire

Scritte dall'Esecutore prima della prima esecuzione e committate insieme agli attesi ricavati, per poter dire se l'osservazione le contraddice. Sono ipotesi sul runtime di GnuCOBOL 3.2 (`libcob`), non verificate sul suo codice.

| Caso | `SYSIN` | Previsione | Ragionamento |
| --- | --- | --- | --- |
| `O1` | vuoto (0 byte) | valore 0, codice 0 | a fine file `ACCEPT` lascia spazi nel campo; un `MOVE` di spazi in un numerico dà 0 |
| `O2` | `3600` | valore 3600, codice 0 | il `MOVE` alfanumerico → numerico di `libcob` ignora gli spazi e allinea le cifre a destra |
| `O3` | `ABCDEFGH` | non saputo prevedere (0 oppure 12345678, dai semibyte bassi) | |
| `O4` | `0000360X` | non saputo prevedere | |

Tutti e quattro chiamano `MVSWAIT` con un valore sotto `X'7FFFFFFF'` (un `PIC 9(8) COMP` non supera 99999999), quindi la previsione dell'esito è in ogni caso codice 0 con la riga di diagnostica.

## Osservato

Prima esecuzione: 27 novembre 2026, GnuCOBOL 3.2 dell'immagine dell'oracle, con l'equivalente di `MVSWAIT` della issue #36. Rapporti registrati in `mvswait-osservati/` così come prodotti.

| Caso | Valore passato a `MVSWAIT` | Codice | Rispetto alla previsione |
| --- | --- | --- | --- |
| `O1` | 0 (`X'00000000'`) | 0 | coincide |
| `O2` | 3600 (`X'00000E10'`) | 0 | coincide |
| `O3` | 0 (`X'00000000'`) | 0 | la previsione era incerta (0 oppure 12345678): è 0 |
| `O4` | 0 (`X'00000000'`) | 0 | nessuna previsione; da notare che 7 cifre valide seguite da una lettera danno 0, non 360 o 3600 |

Nessuna osservazione contraddice una previsione scritta. Nessun messaggio di `libcob` su stderr per questi ingressi (nemmeno con `SYSIN` vuoto). Perché `O3` e `O4` diano 0 non è stato indagato nel codice di `libcob`: è un comportamento di GnuCOBOL, non un riferimento, e la migrazione non lo deve imitare. Se la parità su questi ingressi servisse, andrebbe stabilita su z/OS, che non abbiamo.

## La prova di avvio

`oracle/avvio/expected/COBSWAIT.txt` (passo `avvio`: ingresso standard vuoto, senza `--sysin`) rientra in questi casi: fino alla issue #24 pretendeva il codice 98 del segnaposto; dalla issue #36 registra l'esito osservato con `SYSIN` vuoto, lo stesso di `O1` senza la sezione `== sysin`. È un'osservazione, non un atteso ricavato dal sorgente.
