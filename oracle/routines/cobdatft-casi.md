# COBDATFT: casi determinati e non determinati

Equivalente dell'oracle (`oracle/stubs/COBDATFT.cbl`) della routine assembler `app/asm/COBDATFT.asm`. La tabella si ricava leggendo una per una le istruzioni dell'assembler. Non dice cosa la routine "dovrebbe" fare. La stessa tabella, in forma leggibile da macchina, è in `cobdatft-casi.tsv`: `coerenza.sh` la usa per verificare che copra ogni combinazione e che gli attesi scritti a mano siano conformi.

## Area

Un solo argomento per riferimento: `L R2,0(R1)` (riga 27) carica l'indirizzo dell'area, descritta dalla DSECT `app/maclib/COCDATFT.mac` (righe 17-23) e, lato COBOL, da `app/cpy/CODATECN.cpy` (righe 17-52). Le posizioni sono i byte dell'area, contati da 1.

| Byte | Campo assembler | Lunghezza | Campo COBOL |
| --- | --- | --- | --- |
| 1 | `COINTYPE` | 1 | `CODATECN-TYPE` |
| 2-21 | `COINPDT` | 20 | `CODATECN-INP-DATE` |
| 22 | `COOUTYPE` | 1 | `CODATECN-OUTTYPE` |
| 23-42 | `COOUTDT` | 20 | `CODATECN-0UT-DATE` |
| 43-80 | `COERMSG` | 38 | `CODATECN-ERROR-MSG` |

## Lettura istruzione per istruzione

| Riga | Istruzione | Effetto |
| --- | --- | --- |
| 18-26 | `USING`, `STM`, `LA`, `ST`, `LR` | collegamento standard delle aree di salvataggio; l'area non viene toccata |
| 27 | `L R2,0(R1)` | R2 = indirizzo dell'area (primo indirizzo della lista dei parametri) |
| 30-31 | `CLI COINTYPE,C'1'` / `BE VALIDIN1` | byte 1 = `'1'` → `VALIDIN1` |
| 32-33 | `CLI COINTYPE,C'2'` / `BE VALIDIN2` | byte 1 = `'2'` → `VALIDIN2` |
| 34 | `B GOTOERR` | ogni altro valore del byte 1 → `GOTOERR` |
| 36-37 | `CLC COINPDT+4,=C'-'` / `BE GOTOERR` | **20 byte** (vedi sotto): byte 6-25 dell'area confrontati con il letterale e i 19 byte che lo seguono in memoria; se uguali → `GOTOERR` |
| 38-39 | `CLI COOUTYPE,C'2'` / `BE GOTOERR` | byte 22 = `'2'` → `GOTOERR` |
| 40 | `MVC COOUTDT(4),COINPDT` | byte 23-26 ← byte 2-5 |
| 41 | `MVI COOUTDT+4,C'-'` | byte 27 ← `'-'` |
| 42 | `MVC COOUTDT+5(2),COINPDT+4` | byte 28-29 ← byte 6-7 |
| 43 | `MVI COOUTDT+7,C'-'` | byte 30 ← `'-'` |
| 44 | `MVC COOUTDT+8(2),COINPDT+6` | byte 31-32 ← byte 8-9 |
| 45 | `B EXITL` | uscita |
| 47-48 | `*CLC ...` / `*BNE ...` | commentate: nessun controllo dei separatori con ingresso `2` |
| 49-50 | `CLI COOUTYPE,C'1'` / `BE GOTOERR` | byte 22 = `'1'` → `GOTOERR` |
| 51 | `MVC COOUTDT(4),COINPDT` | byte 23-26 ← byte 2-5 |
| 52 | `MVC COOUTDT+4(2),COINPDT+5` | byte 27-28 ← byte 7-8 |
| 53 | `MVC COOUTDT+6(2),COINPDT+8` | byte 29-30 ← byte 10-11 |
| 54 | `B EXITL` | uscita |
| 56 | `MVC COERMSG,=C'INVALID INPUT'` | **38 byte** (vedi sotto) copiati nei byte 43-80 |
| 59-62 | `L R13,SAVE+4`, `LM R14,R12,12(R13)`, `SR R15,R15`, `BR R14` | registri ripristinati, **codice di ritorno 0** in ogni ramo, compreso l'errore |

Nessuna istruzione controlla cifre o calendario: un mese 13 o un 30 febbraio passano così come sono.

### Lunghezze implicite

In un'istruzione SS (`CLC`, `MVC`) senza lunghezza esplicita l'assemblatore usa l'attributo di lunghezza del primo operando. Per un'espressione `simbolo+n` è l'attributo di lunghezza del simbolo più a sinistra. Quindi:

- riga 36: `CLC COINPDT+4,=C'-'` confronta `L'COINPDT` = **20 byte**, non 1. Il secondo operando è il letterale di un byte `C'-'` seguito da 19 byte che dipendono da come è disposta la memoria del programma assemblato. Il `CLC` confronta da sinistra e si ferma al primo byte diverso, e il primo byte del secondo operando è certamente `'-'`. Perciò, **se il byte 6 dell'area è diverso da `'-'`, il confronto dà "diverso" qualunque cosa segua** e l'esito è determinato. Se il byte 6 è `'-'`, l'esito dipende dai 19 byte successivi e non è determinato;
- riga 56: `MVC COERMSG,=C'INVALID INPUT'` copia `L'COERMSG` = **38 byte**, non 13. I primi 13 sono `INVALID INPUT`, gli altri 25 vengono dalla memoria oltre il letterale e non sono determinati.

Dove si trovino quei byte in memoria dipende dall'ordinamento del pool dei letterali (qui non c'è `LTORG`: il pool va in fondo alla sezione di controllo) e da ciò che segue la sezione nel modulo caricato. Lo si potrebbe ricostruire in parte: con ogni probabilità dopo `C'-'` c'è `C'INVALID INPUT'`. Ma questa ricostruzione si basa su regole di disposizione dei letterali che qui non sono verificate su un assemblatore reale, e in ogni caso non arriva oltre la fine della sezione. Perciò l'oracle non la usa: tutto ciò che dipende da quei byte è trattato come non determinato.

## Tabella dei casi

`non-2` = qualsiasi byte diverso da `'2'`; `altro` = diverso da `'1'` e da `'2'`. Byte 6 = quinto byte della data d'ingresso (`COINPDT+4`).

| Caso | Ingresso (byte 1) | Uscita (byte 22) | Condizione | Esito | Byte scritti | Byte conservati | Righe |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | `1` | `non-2` | byte 6 ≠ `'-'` | determinato, codice 0 | 23-26 ← 2-5; 27 ← `'-'`; 28-29 ← 6-7; 30 ← `'-'`; 31-32 ← 8-9 | 1-22, 33-80 | 30-31, 36-37, 38-39, 40-45, 59-62 |
| C2 | `1` | `non-2` | byte 6 = `'-'` | **non determinato** (97) | — | — | 36-37 |
| C3 | `1` | `2` | — | **non determinato** (97) | — | — | 36-39, 56 |
| C4 | `2` | `non-1` | — | determinato, codice 0 | 23-26 ← 2-5; 27-28 ← 7-8; 29-30 ← 10-11 | 1-22, 31-80 | 32-33, 49-50, 51-54, 59-62 |
| C5 | `2` | `1` | — | **non determinato** (97) | — | — | 49-50, 56 |
| C6 | `altro` | qualsiasi | — | **non determinato** (97) | — | — | 30-34, 56 |

- C3: se il confronto di riga 36 dà "uguale" si va a `GOTOERR`; se dà "diverso", le righe 38-39 vanno comunque a `GOTOERR`. In entrambi i casi si arriva alla riga 56.
- `CBACT01C` (righe 223-231) usa solo C4: ingresso `2`, uscita `2`, data `ACCT-REISSUE-DATE` (formato `AAAA-MM-GG`), da cui si ottiene `AAAAMMGG`.
- Nessun errore del legacy è interamente determinato: ogni ramo di errore passa dalla riga 56. Per questo nessun caso "errore con codice 0 e area modificata" viene riprodotto.

## Comportamento dell'oracle

- Casi determinati: scrive esattamente i byte della colonna "Byte scritti", lascia invariati tutti gli altri e restituisce `RETURN-CODE` 0.
- Casi non determinati: scrive su stderr `MENB-ORACLE COBDATFT: caso non riproducibile dall'oracle` e termina l'intera esecuzione con **codice di uscita 97**, senza tornare al chiamante (`STOP RUN`, come lo stub di `CEE3ABD`). Non inventa i byte mancanti e non li sostituisce con spazi.
- I confronti con `'1'`, `'2'` e `'-'` e le copie avvengono byte per byte nella codifica del programma chiamante (ASCII sotto GnuCOBOL, EBCDIC su z/OS). Con dati coerenti tra chiamante e routine l'esito è lo stesso.

## Prove (passo `routines`)

`oracle/tests/DATFTPRB.cbl` riempie l'area con X'A5', vi scrive i byte del caso (dal PARM: tipo d'ingresso, tipo d'uscita, 0-20 byte di data), la stampa in esadecimale, chiama `COBDATFT` come `CBACT01C` (`CALL 'COBDATFT' USING` l'area) e stampa il codice di ritorno e l'area dopo la chiamata. I casi sono in `casi.tsv`, gli attesi scritti a mano in `expected/`:

| Caso | PARM | Combinazione | Cosa mostra |
| --- | --- | --- | --- |
| D1A | `1120250317` | C1 | `20250317` → `2025-03-17` |
| D1B | `1X20251399` | C1 | uscita diversa da `1` e `2`; mese 13 e giorno 99 non controllati |
| D1C | `11` | C1 | data tutta X'A5': i byte copiati sono X'A5', cambiano solo i byte 27 e 30 |
| D2A | `222025-03-17` | C4 | la combinazione di `CBACT01C`: `2025-03-17` → `20250317` |
| D2B | `222024-02-30` | C4 | 30 febbraio non controllato |
| D2C | `2XABCD/EF.GH` | C4 | separatori e cifre non controllati: `ABCDEFGH` |
| D2D | `222025` | C4 | data corta: i byte 27-30 ricevono X'A5' |
| N1 | `112025-03-17` | C2 | byte 6 `'-'`: arresto 97 |
| N2 | `1220250317` | C3 | arresto 97 |
| N3 | `212025-03-17` | C5 | arresto 97 |
| N4 | `3220250317` | C6 | arresto 97 |
