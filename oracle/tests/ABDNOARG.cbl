      *****************************************************************
      * ABDNOARG - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Chiama CEE3ABD nella forma senza argomenti, come
      * CBSTM03A (riga 923), CBEXPORT (579) e CBIMPORT (484):
      *     CALL 'CEE3ABD'.
      * Prima apre il file ABDFILE, scrive un record e lo lascia aperto.
      * Dopo la CALL non dovrebbe tornare: se tornasse, scriverebbe un
      * secondo record e la riga ABDNOARG DOPO CEE3ABD, che il
      * controllo cerca come segno di errore.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. ABDNOARG.
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
       PROCEDURE DIVISION.
           OPEN OUTPUT ABD-FILE
           DISPLAY 'ABDNOARG OPEN ' ABD-STATUS
           MOVE 'RECORD-PRIMA-ABEND' TO ABD-REC
           WRITE ABD-REC
           DISPLAY 'ABDNOARG WRITE ' ABD-STATUS
           CALL 'CEE3ABD'.
           MOVE 'RECORD-DOPO-ABEND' TO ABD-REC
           WRITE ABD-REC
           DISPLAY 'ABDNOARG DOPO CEE3ABD'
           CLOSE ABD-FILE
           GOBACK.
