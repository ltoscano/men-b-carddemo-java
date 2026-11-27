      *****************************************************************
      * WAITPRB - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Chiama MVSWAIT come COBSWAIT (riga 38):
      * CALL 'MVSWAIT' USING un'area di 4 byte, per riferimento.
      * Il valore arriva nel PARM (avviatore oracle/launcher/avvia.c):
      * 8 cifre esadecimali maiuscole, i 4 byte dell'argomento, cosi'
      * si provano anche i valori oltre PIC 9(8) e con il bit alto
      * acceso, che COBSWAIT non puo' produrre.
      * L'argomento sta tra due campi di 4 byte riempiti con X'A5'
      * (valore riconoscibile). Stampa i 12 byte in esadecimale prima
      * e dopo la CALL, e il RETURN-CODE dopo la CALL (prima vale 55).
      * Il codice di uscita e' il RETURN-CODE lasciato dalla routine.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. WAITPRB.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-AREA.
           05  WS-PRIMA            PIC X(4).
           05  WS-ARG              PIC X(4).
           05  WS-DOPO             PIC X(4).
       01  WS-RC                   PIC -9(9).
       01  WS-HEXDIG               PIC X(16) VALUE '0123456789abcdef'.
       01  WS-HEXMAI               PIC X(16) VALUE '0123456789ABCDEF'.
       01  WS-HEX                  PIC X(8).
       01  WS-RIGA                 PIC X(80).
       01  WS-PTR                  PIC S9(4) BINARY.
       01  WS-I                    PIC S9(4) BINARY.
       01  WS-J                    PIC S9(4) BINARY.
       01  WS-B                    PIC S9(4) BINARY.
       01  WS-HI                   PIC S9(4) BINARY.
       01  WS-LO                   PIC S9(4) BINARY.
       01  WS-CAMPO                PIC X(4).
       LINKAGE SECTION.
       01  LK-PARM.
           05  LK-PARM-LEN         PIC S9(04) COMP.
           05  LK-PARM-TXT         PIC X(100).
       PROCEDURE DIVISION USING LK-PARM.
           IF LK-PARM-LEN NOT = 8
               DISPLAY 'WAITPRB PARM DI LUNGHEZZA NON VALIDA'
               MOVE 2 TO RETURN-CODE
               GOBACK
           END-IF
           MOVE ALL X'A5' TO WS-AREA
      * Le 8 cifre esadecimali del PARM diventano i 4 byte di WS-ARG.
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 4
               MOVE -1 TO WS-HI WS-LO
               PERFORM VARYING WS-J FROM 1 BY 1 UNTIL WS-J > 16
                   IF LK-PARM-TXT(2 * WS-I - 1:1) = WS-HEXMAI(WS-J:1)
                       COMPUTE WS-HI = WS-J - 1
                   END-IF
                   IF LK-PARM-TXT(2 * WS-I:1) = WS-HEXMAI(WS-J:1)
                       COMPUTE WS-LO = WS-J - 1
                   END-IF
               END-PERFORM
               IF WS-HI < 0 OR WS-LO < 0
                   DISPLAY 'WAITPRB PARM NON ESADECIMALE'
                   MOVE 2 TO RETURN-CODE
                   GOBACK
               END-IF
               MOVE FUNCTION CHAR(WS-HI * 16 + WS-LO + 1)
                   TO WS-ARG(WS-I:1)
           END-PERFORM
           MOVE 'PRIMA' TO WS-RIGA
           PERFORM STAMPA-AREA
           MOVE 55 TO RETURN-CODE
           CALL 'MVSWAIT' USING WS-ARG
           MOVE RETURN-CODE TO WS-RC
           DISPLAY 'RC ' WS-RC
           MOVE 'DOPO ' TO WS-RIGA
           PERFORM STAMPA-AREA
           GOBACK.

      * Una riga: etichetta e i tre campi in esadecimale, separati da
      * uno spazio.
       STAMPA-AREA.
           MOVE 6 TO WS-PTR
           MOVE WS-PRIMA TO WS-CAMPO
           PERFORM AGGIUNGI-CAMPO
           MOVE WS-ARG TO WS-CAMPO
           PERFORM AGGIUNGI-CAMPO
           MOVE WS-DOPO TO WS-CAMPO
           PERFORM AGGIUNGI-CAMPO
           DISPLAY WS-RIGA(1:WS-PTR - 1).

       AGGIUNGI-CAMPO.
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 4
               COMPUTE WS-B = FUNCTION ORD(WS-CAMPO(WS-I:1)) - 1
               DIVIDE WS-B BY 16 GIVING WS-HI REMAINDER WS-LO
               MOVE WS-HEXDIG(WS-HI + 1:1) TO WS-HEX(2 * WS-I - 1:1)
               MOVE WS-HEXDIG(WS-LO + 1:1) TO WS-HEX(2 * WS-I:1)
           END-PERFORM
           MOVE ' ' TO WS-RIGA(WS-PTR:1)
           ADD 1 TO WS-PTR
           MOVE WS-HEX TO WS-RIGA(WS-PTR:8)
           ADD 8 TO WS-PTR.
