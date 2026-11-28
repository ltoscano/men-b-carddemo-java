      *****************************************************************
      * MVSWAIT - equivalente dell'oracle MEN-B (non e' codice del
      * legacy) della routine assembler app/asm/MVSWAIT.asm, chiamata
      * da COBSWAIT (riga 38) con un PIC 9(8) COMP (4 byte).
      *
      * L'originale (righe 19-27) legge per riferimento un intero di
      * 4 byte, chiama la macro ASMWAIT (app/maclib/ASMWAIT.mac,
      * STIMER WAIT,BINTVL=...): attesa sincrona in centesimi di
      * secondo; poi ritorna con R15 = 0. Non modifica l'argomento e
      * non scrive nulla. STIMER ammette al massimo X'7FFFFFFF'; oltre,
      * abend X'12F' (documentazione IBM: oracle/routines/
      * mvswait-casi.md).
      *
      * Qui (issue #36), con due adattamenti dichiarati:
      * - NON attende (adattamento temporale);
      * - scrive su stderr una riga con il valore richiesto, in
      *   decimale e in esadecimale (adattamento di uscita: rende
      *   osservabile il valore, non e' riferimento di parita').
      * Valore da X'00000000' a X'7FFFFFFF': ritorno 0, argomento
      * invariato. Valore con il bit alto acceso: l'abend di STIMER
      * non e' riprodotto; riga dell'arresto su stderr e fine
      * dell'esecuzione con codice 97, fisso.
      * Non riprodotto: MVI 12(13),X'FF' (riga 25), che scrive
      * nell'area di salvataggio del chiamante, senza equivalente
      * osservabile in GnuCOBOL.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MVSWAIT.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-HEXDIG               PIC X(16) VALUE '0123456789ABCDEF'.
       01  WS-BYTE                 PIC 9(3)  COMP-5 OCCURS 4.
       01  WS-VALORE               PIC S9(10) COMP-5.
       01  WS-DEC                  PIC 9(10).
       01  WS-HEX                  PIC X(8).
       01  WS-I                    PIC 9(2)  COMP-5.
       01  WS-HI                   PIC 9(3)  COMP-5.
       01  WS-LO                   PIC 9(3)  COMP-5.
       LINKAGE SECTION.
      * Righe 20-21: L 5,0(1) / L 1,0(5): i 4 byte dell'argomento.
       01  LK-INTERVALLO           PIC X(4).
       PROCEDURE DIVISION USING LK-INTERVALLO.
      * Valore senza segno, big-endian, dai 4 byte (letti, mai scritti).
           MOVE 0 TO WS-VALORE
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 4
               COMPUTE WS-BYTE(WS-I) =
                   FUNCTION ORD(LK-INTERVALLO(WS-I:1)) - 1
               MULTIPLY 256 BY WS-VALORE
               ADD WS-BYTE(WS-I) TO WS-VALORE
               DIVIDE WS-BYTE(WS-I) BY 16 GIVING WS-HI
                   REMAINDER WS-LO
               MOVE WS-HEXDIG(WS-HI + 1:1) TO WS-HEX(2 * WS-I - 1:1)
               MOVE WS-HEXDIG(WS-LO + 1:1) TO WS-HEX(2 * WS-I:1)
           END-PERFORM
           MOVE WS-VALORE TO WS-DEC
      * Oltre X'7FFFFFFF' (bit alto acceso): abend X'12F' di STIMER.
           IF WS-VALORE > 2147483647
               DISPLAY 'MENB-ORACLE MVSWAIT: ATTESA RICHIESTA '
                       WS-DEC ' (X''' WS-HEX ''')'
                       ' OLTRE X''7FFFFFFF'': ABEND X''12F'''
                       ' DI STIMER NON RIPRODOTTO'
                       UPON SYSERR
               MOVE 97 TO RETURN-CODE
               STOP RUN
           END-IF
      * Riga 23 (ASMWAIT): l'attesa non e' eseguita.
           DISPLAY 'MENB-ORACLE MVSWAIT: ATTESA RICHIESTA '
                   WS-DEC ' (X''' WS-HEX ''')'
                   ' CENTESIMI DI SECONDO, NON ESEGUITA'
                   UPON SYSERR
      * Righe 26-27: SR 15,15 / BR 14.
           MOVE 0 TO RETURN-CODE
           GOBACK.
