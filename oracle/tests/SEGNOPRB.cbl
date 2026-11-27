      *****************************************************************
      * SEGNOPRB - programma di prova dell'oracle MEN-B (non e' codice
      * del legacy). Sonda sul segno dei campi numerici DISPLAY
      * (zoned con segno incorporato nell'ultima cifra).
      * 1. Legge il file dei dati originali app/data/ASCII/dailytran.txt
      *    (assegnato con DD_DALYTRAN) con il copybook originale
      *    CVTRA06Y e, per i record 1, 2, 23 e 26, stampa i byte grezzi
      *    di DALYTRAN-AMT (PIC S9(09)V99, posizioni 133-143), il valore
      *    letto e il ramo che sceglierebbe CBTRN02C (righe 547-551,
      *    IF DALYTRAN-AMT >= 0: credito, altrimenti debito).
      *    Il file ha una riga per record: si legge come LINE SEQUENTIAL.
      * 2. Ricalcola ogni importo in un campo con la stessa PICTURE e
      *    stampa i byte prodotti (come GnuCOBOL SCRIVE il segno); li
      *    scrive anche nel file SEGNOOUT. Lo stesso per alcune costanti.
      * 3. DISPLAY diretto a console di un campo con segno.
      * 4. Confronti numerici e alfanumerici tra importi letti.
      *****************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SEGNOPRB.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT DALYTRAN-FILE ASSIGN TO DALYTRAN
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS  IS WS-STATO.
           SELECT OUT-FILE ASSIGN TO SEGNOOUT
                  ORGANIZATION IS SEQUENTIAL
                  ACCESS MODE  IS SEQUENTIAL
                  FILE STATUS  IS WS-STATO-OUT.
       DATA DIVISION.
       FILE SECTION.
       FD  DALYTRAN-FILE.
       COPY CVTRA06Y.
       FD  OUT-FILE RECORDING MODE IS F.
       01  OUT-REC                 PIC X(11).
       WORKING-STORAGE SECTION.
       01  WS-STATO                PIC X(02).
       01  WS-STATO-OUT            PIC X(02).
       01  WS-NUM                  PIC 9(04) VALUE 0.
       01  WS-FINE                 PIC X(01) VALUE 'N'.
       01  WS-EDIT                 PIC -9(09).99.
       01  WS-ZONED                PIC S9(09)V99.
       01  WS-ZONED-X REDEFINES WS-ZONED PIC X(11).
       01  WS-AMT-1                PIC S9(09)V99 VALUE 0.
       01  WS-AMT-2                PIC S9(09)V99 VALUE 0.
       01  WS-RAW-1                PIC X(11) VALUE SPACES.
       01  WS-RAW-2                PIC X(11) VALUE SPACES.
       PROCEDURE DIVISION.
           OPEN INPUT DALYTRAN-FILE
           IF WS-STATO NOT = '00'
               DISPLAY 'SEGNOPRB ERRORE OPEN DALYTRAN ' WS-STATO
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           OPEN OUTPUT OUT-FILE
           IF WS-STATO-OUT NOT = '00'
               DISPLAY 'SEGNOPRB ERRORE OPEN SEGNOOUT ' WS-STATO-OUT
               MOVE 8 TO RETURN-CODE
               GOBACK
           END-IF
           PERFORM UNTIL WS-FINE = 'Y'
               READ DALYTRAN-FILE
                   AT END MOVE 'Y' TO WS-FINE
                   NOT AT END
                       ADD 1 TO WS-NUM
                       IF WS-NUM = 1 OR 2 OR 23 OR 26
                           PERFORM 1000-LEGGI
                       END-IF
               END-READ
           END-PERFORM
           DISPLAY 'LETTI ' WS-NUM ' RECORD'
           MOVE +1      TO WS-ZONED
           PERFORM 2000-SCRIVI-COSTANTE
           MOVE -1      TO WS-ZONED
           PERFORM 2000-SCRIVI-COSTANTE
           MOVE 0       TO WS-ZONED
           PERFORM 2000-SCRIVI-COSTANTE
           MOVE -12.34  TO WS-ZONED
           PERFORM 2000-SCRIVI-COSTANTE
           DISPLAY 'CONSOLE AMT-1=' WS-AMT-1 ' AMT-2=' WS-AMT-2
           IF WS-AMT-2 < WS-AMT-1
               DISPLAY 'CONFRONTO NUMERICO AMT-2 < AMT-1: SI'
           ELSE
               DISPLAY 'CONFRONTO NUMERICO AMT-2 < AMT-1: NO'
           END-IF
           IF WS-AMT-2 < ZERO
               DISPLAY 'CONFRONTO NUMERICO AMT-2 < ZERO: SI'
           ELSE
               DISPLAY 'CONFRONTO NUMERICO AMT-2 < ZERO: NO'
           END-IF
           IF WS-RAW-2 < WS-RAW-1
               DISPLAY 'CONFRONTO ALFANUMERICO BYTE-2 < BYTE-1: SI'
           ELSE
               DISPLAY 'CONFRONTO ALFANUMERICO BYTE-2 < BYTE-1: NO'
           END-IF
           CLOSE DALYTRAN-FILE OUT-FILE
           GOBACK.
       1000-LEGGI.
           MOVE DALYTRAN-AMT TO WS-EDIT
           IF DALYTRAN-AMT >= 0
               DISPLAY 'LETTO   REC=' WS-NUM ' ID=' DALYTRAN-ID
                       ' BYTE=' DALYTRAN-RECORD(133:11)
                       ' VALORE=' WS-EDIT ' RAMO=CREDITO'
           ELSE
               DISPLAY 'LETTO   REC=' WS-NUM ' ID=' DALYTRAN-ID
                       ' BYTE=' DALYTRAN-RECORD(133:11)
                       ' VALORE=' WS-EDIT ' RAMO=DEBITO'
           END-IF
           COMPUTE WS-ZONED = DALYTRAN-AMT * 1
           DISPLAY 'SCRITTO REC=' WS-NUM ' BYTE=' WS-ZONED-X
           MOVE WS-ZONED-X TO OUT-REC
           WRITE OUT-REC
           IF WS-NUM = 1
               MOVE DALYTRAN-AMT TO WS-AMT-1
               MOVE DALYTRAN-RECORD(133:11) TO WS-RAW-1
           END-IF
           IF WS-NUM = 2
               MOVE DALYTRAN-AMT TO WS-AMT-2
               MOVE DALYTRAN-RECORD(133:11) TO WS-RAW-2
           END-IF.
       2000-SCRIVI-COSTANTE.
           MOVE WS-ZONED TO WS-EDIT
           DISPLAY 'COSTANTE VALORE=' WS-EDIT ' BYTE=' WS-ZONED-X
           MOVE WS-ZONED-X TO OUT-REC
           WRITE OUT-REC.
