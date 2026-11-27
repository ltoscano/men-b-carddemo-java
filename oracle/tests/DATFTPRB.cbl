      *****************************************************************
      * DATFTPRB - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Chiama COBDATFT come CBACT01C (righe 223-231):
      * CALL 'COBDATFT' USING un'area di 80 byte con il tracciato di
      * app/cpy/CODATECN.cpy.
      * Il caso arriva nel PARM (avviatore oracle/launcher/avvia.c):
      *   byte 1      tipo d'ingresso   (CODATECN-TYPE)
      *   byte 2      tipo d'uscita     (CODATECN-OUTTYPE)
      *   byte 3-22   data d'ingresso   (CODATECN-INP-DATE), 0-20 byte
      * Prima l'intera area e' riempita con X'A5' (valore riconoscibile),
      * poi vi si scrivono i byte del caso; gli altri restano X'A5'.
      * Stampa l'area in esadecimale, campo per campo, prima e dopo la
      * CALL, e il RETURN-CODE dopo la CALL (prima della CALL vale 55).
      * Il codice di uscita e' il RETURN-CODE lasciato dalla routine.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. DATFTPRB.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-AREA.
           05  WS-INTYPE           PIC X(01).
           05  WS-INPDT            PIC X(20).
           05  WS-OUTYPE           PIC X(01).
           05  WS-OUTDT            PIC X(20).
           05  WS-ERMSG            PIC X(38).
       01  WS-NDATA                PIC S9(4) BINARY.
       01  WS-RC                   PIC -9(9).
       01  WS-HEXDIG               PIC X(16) VALUE '0123456789abcdef'.
       01  WS-HEX                  PIC X(76).
       01  WS-RIGA                 PIC X(200).
       01  WS-PTR                  PIC S9(4) BINARY.
       01  WS-I                    PIC S9(4) BINARY.
       01  WS-B                    PIC S9(4) BINARY.
       01  WS-HI                   PIC S9(4) BINARY.
       01  WS-LO                   PIC S9(4) BINARY.
       01  WS-CAMPO                PIC X(38).
       01  WS-LCAMPO               PIC S9(4) BINARY.
       LINKAGE SECTION.
       01  LK-PARM.
           05  LK-PARM-LEN         PIC S9(04) COMP.
           05  LK-PARM-TXT         PIC X(100).
       PROCEDURE DIVISION USING LK-PARM.
           IF LK-PARM-LEN < 2 OR LK-PARM-LEN > 22
               DISPLAY 'DATFTPRB PARM DI LUNGHEZZA NON VALIDA'
               MOVE 2 TO RETURN-CODE
               GOBACK
           END-IF
           MOVE ALL X'A5' TO WS-AREA
           MOVE LK-PARM-TXT(1:1) TO WS-INTYPE
           MOVE LK-PARM-TXT(2:1) TO WS-OUTYPE
           COMPUTE WS-NDATA = LK-PARM-LEN - 2
           IF WS-NDATA > 0
               MOVE LK-PARM-TXT(3:WS-NDATA) TO WS-INPDT(1:WS-NDATA)
           END-IF
           MOVE 'PRIMA' TO WS-RIGA
           PERFORM STAMPA-AREA
           MOVE 55 TO RETURN-CODE
           CALL 'COBDATFT' USING WS-AREA
           MOVE RETURN-CODE TO WS-RC
           DISPLAY 'RC ' WS-RC
           MOVE 'DOPO ' TO WS-RIGA
           PERFORM STAMPA-AREA
           GOBACK.

      * Una riga: etichetta e i cinque campi in esadecimale, separati da
      * uno spazio.
       STAMPA-AREA.
           MOVE 6 TO WS-PTR
           MOVE WS-INTYPE TO WS-CAMPO
           MOVE 1 TO WS-LCAMPO
           PERFORM AGGIUNGI-CAMPO
           MOVE WS-INPDT TO WS-CAMPO
           MOVE 20 TO WS-LCAMPO
           PERFORM AGGIUNGI-CAMPO
           MOVE WS-OUTYPE TO WS-CAMPO
           MOVE 1 TO WS-LCAMPO
           PERFORM AGGIUNGI-CAMPO
           MOVE WS-OUTDT TO WS-CAMPO
           MOVE 20 TO WS-LCAMPO
           PERFORM AGGIUNGI-CAMPO
           MOVE WS-ERMSG TO WS-CAMPO
           MOVE 38 TO WS-LCAMPO
           PERFORM AGGIUNGI-CAMPO
           DISPLAY WS-RIGA(1:WS-PTR - 1).

       AGGIUNGI-CAMPO.
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-LCAMPO
               COMPUTE WS-B = FUNCTION ORD(WS-CAMPO(WS-I:1)) - 1
               DIVIDE WS-B BY 16 GIVING WS-HI REMAINDER WS-LO
               MOVE WS-HEXDIG(WS-HI + 1:1) TO WS-HEX(2 * WS-I - 1:1)
               MOVE WS-HEXDIG(WS-LO + 1:1) TO WS-HEX(2 * WS-I:1)
           END-PERFORM
           MOVE ' ' TO WS-RIGA(WS-PTR:1)
           ADD 1 TO WS-PTR
           MOVE WS-HEX(1:2 * WS-LCAMPO) TO WS-RIGA(WS-PTR:2 * WS-LCAMPO)
           ADD WS-LCAMPO TO WS-PTR
           ADD WS-LCAMPO TO WS-PTR.
