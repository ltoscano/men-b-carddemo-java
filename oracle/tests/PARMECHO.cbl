      *****************************************************************
      * PARMECHO - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Ha la stessa LINKAGE di CBACT04C
      * (app/cbl/CBACT04C.cbl, righe 175-180) e riceve l'area del PARM
      * dall'avviatore (oracle/launcher/avvia.c).
      * Stampa la lunghezza e il testo ricevuti e scrive l'area grezza
      * (i primi 12 byte, quelli descritti dalla LINKAGE) come unico
      * record del file PARMDUMP, che il controllo legge byte per byte.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PARMECHO.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT DUMP-FILE ASSIGN TO PARMDUMP
                  ORGANIZATION IS SEQUENTIAL
                  ACCESS MODE  IS SEQUENTIAL
                  FILE STATUS  IS DUMP-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  DUMP-FILE RECORDING MODE IS F.
       01  DUMP-REC                PIC X(12).
       WORKING-STORAGE SECTION.
       01  DUMP-STATUS             PIC X(02).
       01  WS-LEN                  PIC -9(5).
       LINKAGE SECTION.
       01  EXTERNAL-PARMS.
           05  PARM-LENGTH         PIC S9(04) COMP.
           05  PARM-DATE           PIC X(10).
       PROCEDURE DIVISION USING EXTERNAL-PARMS.
           MOVE PARM-LENGTH TO WS-LEN
           DISPLAY 'PARMECHO PARM-LENGTH=' WS-LEN
           DISPLAY 'PARMECHO PARM-DATE=' PARM-DATE
           OPEN OUTPUT DUMP-FILE
           IF DUMP-STATUS NOT = '00'
               DISPLAY 'PARMECHO ERRORE OPEN PARMDUMP ' DUMP-STATUS
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           MOVE EXTERNAL-PARMS TO DUMP-REC
           WRITE DUMP-REC
           IF DUMP-STATUS NOT = '00'
               DISPLAY 'PARMECHO ERRORE WRITE PARMDUMP ' DUMP-STATUS
               MOVE 8 TO RETURN-CODE
           END-IF
           CLOSE DUMP-FILE
           GOBACK.
