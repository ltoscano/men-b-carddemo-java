      *****************************************************************
      * ABDUSING - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Chiama CEE3ABD nella forma con due argomenti,
      * come CBACT01C (riga 410) e gli altri batch:
      *     CALL 'CEE3ABD' USING ABCODE, TIMING.
      * Prima apre il file ABDFILE, scrive un record e lo lascia aperto.
      * Dopo la CALL non dovrebbe tornare: se tornasse, scriverebbe un
      * secondo record e la riga ABDUSING DOPO CEE3ABD, che il
      * controllo cerca come segno di errore.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. ABDUSING.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ABD-FILE ASSIGN TO ABDFILE
                  ORGANIZATION IS SEQUENTIAL
                  ACCESS MODE  IS SEQUENTIAL
                  FILE STATUS  IS ABD-STATUS.
       DATA DIVISION.
       FILE SECTION.
       FD  ABD-FILE RECORDING MODE IS F.
       01  ABD-REC                 PIC X(20).
       WORKING-STORAGE SECTION.
       01  ABD-STATUS              PIC X(02).
       01  ABCODE                  PIC S9(9) BINARY.
       01  TIMING                  PIC S9(9) BINARY.
       PROCEDURE DIVISION.
           OPEN OUTPUT ABD-FILE
           DISPLAY 'ABDUSING OPEN ' ABD-STATUS
           MOVE 'RECORD-PRIMA-ABEND' TO ABD-REC
           WRITE ABD-REC
           DISPLAY 'ABDUSING WRITE ' ABD-STATUS
           MOVE 0 TO TIMING
           MOVE 999 TO ABCODE
           CALL 'CEE3ABD' USING ABCODE, TIMING.
           MOVE 'RECORD-DOPO-ABEND' TO ABD-REC
           WRITE ABD-REC
           DISPLAY 'ABDUSING DOPO CEE3ABD'
           CLOSE ABD-FILE
           GOBACK.
